-- 0014_post_rpcs: สร้างโพสต์ (T02) — TECHNICAL_BUILD_PLAN 4.2 แถว 6d (P3-02; แก้โพสต์ N2 มากับ P3-02b)
-- TECHNICAL_DESIGN ส่วน 2, 5, 7 (K5), 10; SYSTEM_SPEC K1, J1, I4, N; UX_DESIGN ส่วน 9 (T02)
-- create_post(p_classroom_id, p_post jsonb, p_request_key, p_admin_mode)
--   p_post = { kind: 'homework' | 'announcement', title, body?,
--              (การบ้านเท่านั้น) full_score, late_penalty_pct?, reward_tokens?, due_at, close_at?, accept_after_solution? }
--   เนื้อหาทั้งฟอร์มเป็น jsonb ก้อนเดียว: ไฟล์โจทย์ (P3-06) เพิ่มเป็นคีย์ใหม่โดยไม่เปลี่ยน signature
--   ตรวจตามลำดับ: ครู/ผู้ดูแลในโหมดผู้ดูแล → request key → เนื้อหา (เพดานเดียวกับ 0010_posts) → ภาคเรียน (K5) → ห้อง
--   กดซ้ำด้วย request key เดิมได้โพสต์เดียว (operation_receipts 24 ชม.); ช่องที่ล็อกและเพดานยังถูกกันซ้ำโดย 0010_posts

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- ค่า jsonb ที่เป็นจำนวนเต็ม (ไม่รับทศนิยม ข้อความ หรือเกินช่วง integer) — อย่างอื่นคืน null
create function private.jsonb_int(p_value jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
           when jsonb_typeof(p_value) = 'number'
            and (p_value #>> '{}')::numeric = trunc((p_value #>> '{}')::numeric)
            and (p_value #>> '{}')::numeric between -2147483648 and 2147483647
           then (p_value #>> '{}')::integer
         end
$$;

-- เวลาแบบ ISO 8601 ที่ระบุเขตเวลาชัดเจน (Z หรือ ±hh:mm) — ไม่ให้ขึ้นกับ TimeZone ของ session; อ่านไม่ได้คืน null
create function private.jsonb_timestamptz(p_value jsonb)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$' then
    return null;
  end if;
  return (p_value #>> '{}')::timestamptz;
exception when others then
  return null;
end
$$;

-- ตัดช่องว่างหัวท้ายทุกชนิด (รวมขึ้นบรรทัดใหม่) — ว่างแล้วคืน null
create function private.trim_text(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(coalesce(p_value, ''), '^\s+|\s+$', '', 'g'), '')
$$;

-- ---------------------------------------------------------------------------
-- 2. สร้างโพสต์
-- ---------------------------------------------------------------------------
-- รหัสที่หน้าเว็บอาจเจอ: post_title_invalid, post_body_required, post_body_too_long, full_score_invalid,
-- late_penalty_invalid, reward_tokens_invalid, due_at_invalid, close_at_invalid, close_before_due, term_ended,
-- forbidden, admin_mode_required — รหัสภายใน (หน้าเว็บไม่ส่งแบบนี้): invalid_request, request_key_required,
-- request_key_conflict
-- ผล: { post_id, classroom_id, kind, title, body, published_at, version,
--       assignment: { full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution } | null }
create function public.create_post(
  p_classroom_id uuid,
  p_post jsonb,
  p_request_key uuid,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_kind text;
  v_title text;
  v_body text;
  v_full integer;
  v_late integer := 50;
  v_reward integer := 1;
  v_due timestamptz;
  v_close timestamptz;
  v_after boolean := false;
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_term_status text;
  v_classroom public.classrooms;
  v_post public.posts;
  v_assignment public.assignments;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;

  -- รูปแบบก้อนข้อมูล (หน้าเว็บส่งถูกเสมอ ผิดได้จากบั๊กเท่านั้น)
  if jsonb_typeof(p_post) is distinct from 'object' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_kind := p_post ->> 'kind';
  if v_kind is null or v_kind not in ('homework', 'announcement')
     or exists (select 1 from jsonb_object_keys(p_post) k
                 where k <> all (case v_kind
                                   when 'homework' then array['kind', 'title', 'body', 'full_score', 'late_penalty_pct',
                                                              'reward_tokens', 'due_at', 'close_at', 'accept_after_solution']
                                   else array['kind', 'title', 'body']
                                 end))
     or (p_post ? 'body' and jsonb_typeof(p_post -> 'body') not in ('string', 'null'))
     or (p_post ? 'accept_after_solution' and jsonb_typeof(p_post -> 'accept_after_solution') <> 'boolean') then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- ชื่อ 1–120 ตัว · รายละเอียดไม่บังคับสำหรับการบ้าน (N) ไม่เกิน 10,000 · ประกาศต้องมีข้อความ (แบบ v2)
  v_title := private.trim_text(case when jsonb_typeof(p_post -> 'title') = 'string' then p_post ->> 'title' end);
  if v_title is null or length(v_title) > 120 then
    raise exception using errcode = 'P0001', message = 'post_title_invalid';
  end if;
  v_body := private.trim_text(p_post ->> 'body');
  if length(v_body) > 10000 then
    raise exception using errcode = 'P0001', message = 'post_body_too_long';
  end if;
  if v_kind = 'announcement' and v_body is null then
    raise exception using errcode = 'P0001', message = 'post_body_required';
  end if;

  if v_kind = 'homework' then
    -- K1: จำนวนเต็มตั้งแต่ 1 (เพดาน 1,000,000 กันค่าผิดพลาด)
    v_full := private.jsonb_int(p_post -> 'full_score');
    if v_full is null or v_full not between 1 and 1000000 then
      raise exception using errcode = 'P0001', message = 'full_score_invalid';
    end if;
    -- J1: 0–100 ค่าเริ่มต้น 50
    if p_post ? 'late_penalty_pct' then
      v_late := private.jsonb_int(p_post -> 'late_penalty_pct');
      if v_late is null or v_late not between 0 and 100 then
        raise exception using errcode = 'P0001', message = 'late_penalty_invalid';
      end if;
    end if;
    -- โทเคนค่าเริ่มต้น 1 (เพดาน 1,000 กันค่าผิดพลาด)
    if p_post ? 'reward_tokens' then
      v_reward := private.jsonb_int(p_post -> 'reward_tokens');
      if v_reward is null or v_reward not between 0 and 1000 then
        raise exception using errcode = 'P0001', message = 'reward_tokens_invalid';
      end if;
    end if;
    -- กำหนดส่งเป็นนาทีเต็ม (ส่วน 5); กำหนดที่ผ่านไปแล้วรับได้ (T02 เตือนสีเหลืองตาม J7)
    v_due := private.jsonb_timestamptz(p_post -> 'due_at');
    if v_due is null or mod(extract(epoch from v_due), 60) <> 0 then
      raise exception using errcode = 'P0001', message = 'due_at_invalid';
    end if;
    -- วันปิดรับไม่บังคับ (null = รับงานสายจนกว่าครูปิด) ต้องไม่ก่อนกำหนดส่ง
    if p_post ? 'close_at' and jsonb_typeof(p_post -> 'close_at') <> 'null' then
      v_close := private.jsonb_timestamptz(p_post -> 'close_at');
      if v_close is null then
        raise exception using errcode = 'P0001', message = 'close_at_invalid';
      end if;
      if v_close < v_due then
        raise exception using errcode = 'P0001', message = 'close_before_due';
      end if;
    end if;
    v_after := coalesce((p_post ->> 'accept_after_solution')::boolean, false);
  end if;

  v_operation := 'create_post:' || md5(jsonb_build_object(
    'classroom_id', p_classroom_id, 'kind', v_kind, 'title', v_title, 'body', v_body, 'full_score', v_full,
    'late_penalty_pct', v_late, 'reward_tokens', v_reward, 'due_at', v_due, 'close_at', v_close,
    'accept_after_solution', v_after)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: term_control ก่อนเสมอ (BUILD_PLAN 4.1 ข้อ 5) แล้วจึงห้อง (ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล)
  select c.term_id, c.status into v_term_id, v_term_status from public.term_control c where c.singleton for share;
  v_classroom := private.require_classroom_teacher(p_classroom_id, p_admin_mode);
  -- K5: ห้องของเทอมเก่า (หลังเปิดเทอมใหม่) โพสต์ไม่ได้ทั้งสองชนิด; เทอมปัจจุบันจบแล้ว (ended) สร้างการบ้านไม่ได้
  -- เพราะนักเรียนส่งไม่ได้แล้ว แต่ประกาศยังโพสต์ได้ เช่นแจ้งคะแนนหรือนัดหมาย
  if v_term_id is null or v_classroom.term_id <> v_term_id
     or (v_term_status <> 'active' and v_kind = 'homework') then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;

  insert into public.posts (classroom_id, kind, title, body)
  values (v_classroom.id, v_kind, v_title, v_body)
  returning * into v_post;
  if v_kind = 'homework' then
    insert into public.assignments (post_id, full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution)
    values (v_post.id, v_full, v_late, v_reward, v_due, v_close, v_after)
    returning * into v_assignment;
  end if;

  v_result := jsonb_build_object(
    'post_id', v_post.id,
    'classroom_id', v_post.classroom_id,
    'kind', v_post.kind,
    'title', v_post.title,
    'body', v_post.body,
    'published_at', v_post.published_at,
    'version', v_post.version,
    'assignment', case when v_kind = 'homework' then jsonb_build_object(
      'full_score', v_assignment.full_score,
      'late_penalty_pct', v_assignment.late_penalty_pct,
      'reward_tokens', v_assignment.reward_tokens,
      'due_at', v_assignment.due_at,
      'close_at', v_assignment.close_at,
      'accept_after_solution', v_assignment.accept_after_solution) end);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
grant execute on function public.create_post(uuid, jsonb, uuid, boolean) to authenticated;
