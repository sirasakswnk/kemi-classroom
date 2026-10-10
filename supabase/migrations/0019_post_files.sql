-- 0019_post_files: ผูกไฟล์โจทย์/ไฟล์แนบกับโพสต์ (T02) — P3-06b
-- TECHNICAL_DESIGN ส่วน 2 (assets/attachments), 9, 10 (POST /classrooms/:id/posts, PATCH /posts/:id); SYSTEM_SPEC J6, N1, N2
-- UX_DESIGN ส่วน 9 (ไฟล์โจทย์ 10 ไฟล์/20 MB, ประกาศต้องมีข้อความหรือไฟล์)
-- create_post / update_post (signature เดิมของ 0014/0015) รับคีย์ใหม่ใน p_post:
--   files: [asset_id, …] ตามลำดับที่แสดง — create: ไม่ส่ง = ไม่มีไฟล์ · update: ไม่ส่ง = คงชุดเดิม, ส่ง = ชุดใหม่ทั้งชุด
--   ทุก asset ต้อง ready, วัตถุประสงค์ post และ (ผูกกับโพสต์นี้อยู่แล้ว หรือ เป็นของผู้เรียกและยังไม่ผูกที่ใด)
--   ผู้ดูแลในโหมดผู้ดูแลแนบได้เฉพาะ asset ของตัวเอง (ไฟล์เดิมของครูในโพสต์นั้นคงไว้ได้)
--   ผิดข้อใด → ปฏิเสธทั้งคำขอด้วยรหัสเดียว post_file_unavailable (ไม่บอกว่า asset ของคนอื่นมีอยู่หรือไม่)
--   id ซ้ำในรายการ → invalid_request · เกิน 10 ไฟล์ → too_many_files · รวมเกิน 20 MB → batch_too_large (J6)
-- เอาไฟล์ออก = ลบแถวผูกเท่านั้น: asset คงอยู่และนับพื้นที่จนงานลบ asset ที่ไม่มีแถวผูก (P3-10) เข้าคิวลบ B2 แบบระบุ version_id
-- ชุดหรือลำดับไฟล์เปลี่ยน = แก้โจทย์ (N1/N2: ขยับ content_updated_at + version) · ส่งชุดเดิมลำดับเดิม = ไม่ขยับ
-- ประกาศต้องมีข้อความหรือไฟล์อย่างน้อยหนึ่งอย่าง (รหัสเดิม post_body_required — ความหมายกว้างขึ้น)
-- batch ที่ทุกไฟล์ถูกผูกแล้วตั้งเป็น consumed (เลิกจองพื้นที่) — ยอดพื้นที่ (0011) นับขนาดจาก assets และหักส่วนที่ complete
-- แล้วออกจากยอดจองของ batch อยู่แล้ว จึงไม่นับซ้ำทั้งก่อนและหลังตั้งสถานะ
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: post_file_unavailable (และ too_many_files, batch_too_large เดิมของ 0016)
-- ผลของ create_post/update_post เพิ่ม files: [{ asset_id, file_name, content_type, size_bytes }] ตามลำดับ

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร — เรียกจาก create_post/update_post ซึ่งเป็น SECURITY DEFINER)
-- ---------------------------------------------------------------------------
-- รายการ asset id จาก p_post -> 'files' — null = ไม่ส่งคีย์; ไม่ใช่อาร์เรย์ของ uuid หรือมีตัวซ้ำ → invalid_request
create function private.post_files_ids(p_post jsonb)
returns uuid[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (p_post ? 'files') then
    return null;
  end if;
  if jsonb_typeof(p_post -> 'files') <> 'array'
     or exists (select 1 from jsonb_array_elements(p_post -> 'files') e
                 where jsonb_typeof(e) <> 'string'
                    or (e #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select coalesce(array_agg((e.value #>> '{}')::uuid order by e.n), '{}')
    into v_ids
    from jsonb_array_elements(p_post -> 'files') with ordinality e(value, n);
  if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  -- J6: ไฟล์โจทย์สูงสุด 10 (ค่าเดียวกับ private.upload_limits())
  if cardinality(v_ids) > (private.upload_limits() ->> 'max_files')::integer then
    raise exception using errcode = 'P0001', message = 'too_many_files';
  end if;
  return v_ids;
end
$$;

-- ทำให้ไฟล์ของโพสต์ตรงกับรายการ (ตามลำดับ) — คืน true ถ้าชุดหรือลำดับเปลี่ยน
-- ล็อกแถว asset ที่ขอ (FOR UPDATE ตามลำดับ id) ก่อนตรวจ: สองคำขอที่แนบ asset เดียวกันพร้อมกันรอกัน และรายหลังเห็นว่า
-- ผูกไปแล้ว → post_file_unavailable (ไม่ชน unique ของ attachments เป็นข้อผิดพลาดดิบ)
create function private.post_files_apply(p_post_id uuid, p_ids uuid[], p_account uuid)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_current uuid[];
  v_count integer;
  v_total bigint;
begin
  select coalesce(array_agg(t.asset_id order by t.position), '{}') into v_current
    from public.attachments t where t.post_id = p_post_id;
  if v_current = p_ids then
    return false;
  end if;

  perform 1 from public.assets a where a.id = any(p_ids) order by a.id for update;
  select count(*)::integer, coalesce(sum(a.size_bytes), 0)::bigint into v_count, v_total
    from public.assets a
    left join public.attachments t on t.asset_id = a.id
   where a.id = any(p_ids)
     and a.status = 'ready'
     and a.purpose = 'post'
     and (t.post_id = p_post_id or (t.id is null and a.owner_account_id = p_account));
  if v_count <> cardinality(p_ids) then
    raise exception using errcode = 'P0001', message = 'post_file_unavailable';
  end if;
  -- J6: รวมต่อชุดโจทย์ไม่เกิน 20 MB (ค่าเดียวกับ private.upload_limits())
  if v_total > (private.upload_limits() ->> 'max_batch_bytes')::bigint then
    raise exception using errcode = 'P0001', message = 'batch_too_large';
  end if;

  -- เรียงใหม่สลับลำดับกันได้ (unique (post_id, position) ตรวจตอนจบ transaction)
  set constraints public.attachments_post_position_key deferred;
  delete from public.attachments t where t.post_id = p_post_id and t.asset_id <> all (p_ids);
  update public.attachments t
     set position = u.n
    from unnest(p_ids) with ordinality u(id, n)
   where t.post_id = p_post_id and t.asset_id = u.id and t.position <> u.n;
  insert into public.attachments (asset_id, post_id, position)
  select u.id, p_post_id, u.n
    from unnest(p_ids) with ordinality u(id, n)
   where not exists (select 1 from public.attachments t where t.asset_id = u.id);

  -- batch ที่ทุกไฟล์ถูกผูกแล้ว: เลิกจอง (batch ที่ยังมีไฟล์ไม่ complete/ไม่ผูก คงเปิดไว้ ไฟล์ที่เหลือยังอัปต่อได้
  -- และพื้นที่ส่วนนั้นปล่อยเองเมื่อ batch หมดอายุ)
  update public.upload_batches b
     set status = 'consumed'
   where b.status = 'open'
     and b.id in (select a.upload_batch_id from public.assets a where a.id = any(p_ids))
     and jsonb_array_length(b.files) = (select count(*) from public.assets a
                                          join public.attachments t on t.asset_id = a.id
                                         where a.upload_batch_id = b.id);
  return true;
end
$$;

-- รายการไฟล์ของโพสต์สำหรับผลของ RPC
create function private.post_files_json(p_post_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'asset_id', a.id, 'file_name', a.file_name, 'content_type', a.content_type, 'size_bytes', a.size_bytes)
           order by t.position), '[]'::jsonb)
    from public.attachments t
    join public.assets a on a.id = t.asset_id
   where t.post_id = p_post_id
$$;

-- ---------------------------------------------------------------------------
-- 2. สร้างโพสต์ (จาก 0014 + ไฟล์)
-- ---------------------------------------------------------------------------
create or replace function public.create_post(
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
  v_files uuid[];
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
                                   when 'homework' then array['kind', 'title', 'body', 'files', 'full_score',
                                                              'late_penalty_pct', 'reward_tokens', 'due_at', 'close_at',
                                                              'accept_after_solution']
                                   else array['kind', 'title', 'body', 'files']
                                 end))
     or (p_post ? 'body' and jsonb_typeof(p_post -> 'body') not in ('string', 'null'))
     or (p_post ? 'accept_after_solution' and jsonb_typeof(p_post -> 'accept_after_solution') <> 'boolean') then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- ไฟล์โจทย์/ไฟล์แนบ (P3-06b): รายการ asset id ตามลำดับ ไม่ส่ง = ไม่มีไฟล์
  v_files := coalesce(private.post_files_ids(p_post), '{}');

  -- ชื่อ 1–120 ตัว · รายละเอียดไม่บังคับสำหรับการบ้าน (N) ไม่เกิน 10,000 · ประกาศต้องมีข้อความหรือไฟล์อย่างน้อยหนึ่งอย่าง
  v_title := private.trim_text(case when jsonb_typeof(p_post -> 'title') = 'string' then p_post ->> 'title' end);
  if v_title is null or length(v_title) > 120 then
    raise exception using errcode = 'P0001', message = 'post_title_invalid';
  end if;
  v_body := private.trim_text(p_post ->> 'body');
  if length(v_body) > 10000 then
    raise exception using errcode = 'P0001', message = 'post_body_too_long';
  end if;
  if v_kind = 'announcement' and v_body is null and cardinality(v_files) = 0 then
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
    'accept_after_solution', v_after, 'files', v_files)::text);
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

  -- ผูกไฟล์หลังสร้างโพสต์ (ลำดับล็อก term_control → ห้อง → assets)
  perform private.post_files_apply(v_post.id, v_files, v_account.id);

  v_result := jsonb_build_object(
    'post_id', v_post.id,
    'classroom_id', v_post.classroom_id,
    'kind', v_post.kind,
    'title', v_post.title,
    'body', v_post.body,
    'published_at', v_post.published_at,
    'version', v_post.version,
    'files', private.post_files_json(v_post.id),
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

-- ---------------------------------------------------------------------------
-- 3. แก้โพสต์ (จาก 0015 + ไฟล์)
-- ---------------------------------------------------------------------------
create or replace function public.update_post(
  p_post_id uuid,
  p_post jsonb,
  p_expected_version integer,
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
  v_operation text;
  v_prior jsonb;
  v_classroom_id uuid;
  v_post public.posts;
  v_assignment public.assignments;
  v_title text;
  v_body text;
  v_full integer;
  v_late integer;
  v_reward integer;
  v_after boolean;
  v_due timestamptz;
  v_close timestamptz;
  v_content_changed boolean;
  v_assignment_changed boolean;
  v_files uuid[];
  v_file_count integer;
  v_files_changed boolean := false;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;

  -- รูปแบบก้อนข้อมูล (หน้าเว็บส่งถูกเสมอ ผิดได้จากบั๊กเท่านั้น)
  v_kind := case when jsonb_typeof(p_post) = 'object' then p_post ->> 'kind' end;
  if p_expected_version is null or v_kind is null or v_kind not in ('homework', 'announcement')
     or exists (select 1 from jsonb_object_keys(p_post) k
                 where k <> all (case v_kind
                                   when 'homework' then array['kind', 'title', 'body', 'files', 'full_score',
                                                              'late_penalty_pct', 'reward_tokens', 'due_at', 'close_at',
                                                              'accept_after_solution']
                                   else array['kind', 'title', 'body', 'files']
                                 end))
     or (p_post ? 'title' and jsonb_typeof(p_post -> 'title') <> 'string')
     or (p_post ? 'body' and jsonb_typeof(p_post -> 'body') not in ('string', 'null'))
     or (p_post ? 'accept_after_solution' and jsonb_typeof(p_post -> 'accept_after_solution') <> 'boolean') then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  -- ไฟล์: ส่งคีย์ files = ชุดใหม่ทั้งชุดตามลำดับ (รายการว่าง = เอาออกทั้งหมด) · ไม่ส่ง = คงชุดเดิม
  v_files := private.post_files_ids(p_post);

  v_operation := 'update_post:' || md5(jsonb_build_object(
    'post_id', p_post_id, 'expected_version', p_expected_version, 'post', p_post)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: ห้อง → โพสต์ → งาน (ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล; โพสต์ที่ไม่มี = forbidden เหมือนห้องที่ไม่มี)
  select p.classroom_id into v_classroom_id from public.posts p where p.id = p_post_id;
  if v_classroom_id is null then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.require_classroom_teacher(v_classroom_id, p_admin_mode);
  select p.* into v_post from public.posts p where p.id = p_post_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if v_kind <> v_post.kind then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if v_post.version <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  if v_post.kind = 'homework' then
    select a.* into v_assignment from public.assignments a where a.post_id = p_post_id for update;
  end if;

  -- เนื้อหา: คีย์ที่ไม่ส่ง = คงค่าเดิม; ตรวจเพดานเดียวกับ create_post
  v_title := case when p_post ? 'title' then private.trim_text(p_post ->> 'title') else v_post.title end;
  if v_title is null or length(v_title) > 120 then
    raise exception using errcode = 'P0001', message = 'post_title_invalid';
  end if;
  v_body := case when p_post ? 'body' then private.trim_text(p_post ->> 'body') else v_post.body end;
  if length(v_body) > 10000 then
    raise exception using errcode = 'P0001', message = 'post_body_too_long';
  end if;
  v_file_count := coalesce(cardinality(v_files),
                           (select count(*)::integer from public.attachments t where t.post_id = p_post_id));
  if v_post.kind = 'announcement' and v_body is null and v_file_count = 0 then
    raise exception using errcode = 'P0001', message = 'post_body_required';
  end if;
  -- ชุดไฟล์: ผูก/เลิกผูก/เรียงใหม่ (ชุดและลำดับเดิม = ไม่เปลี่ยน) — ล็อก assets ต่อจากโพสต์/งาน
  if v_files is not null then
    v_files_changed := private.post_files_apply(p_post_id, v_files, v_account.id);
  end if;
  -- N1/N2: ชื่อ รายละเอียด หรือชุดไฟล์เปลี่ยน = แก้โจทย์ (ขยับ content_updated_at และ version)
  v_content_changed := v_title is distinct from v_post.title or v_body is distinct from v_post.body or v_files_changed;

  v_assignment_changed := false;
  if v_post.kind = 'homework' then
    v_full := v_assignment.full_score;
    if p_post ? 'full_score' then
      v_full := private.jsonb_int(p_post -> 'full_score');
      if v_full is null or v_full not between 1 and 1000000 then
        raise exception using errcode = 'P0001', message = 'full_score_invalid';
      end if;
    end if;
    v_late := v_assignment.late_penalty_pct;
    if p_post ? 'late_penalty_pct' then
      v_late := private.jsonb_int(p_post -> 'late_penalty_pct');
      if v_late is null or v_late not between 0 and 100 then
        raise exception using errcode = 'P0001', message = 'late_penalty_invalid';
      end if;
    end if;
    v_reward := v_assignment.reward_tokens;
    if p_post ? 'reward_tokens' then
      v_reward := private.jsonb_int(p_post -> 'reward_tokens');
      if v_reward is null or v_reward not between 0 and 1000 then
        raise exception using errcode = 'P0001', message = 'reward_tokens_invalid';
      end if;
    end if;
    v_after := coalesce((p_post ->> 'accept_after_solution')::boolean, v_assignment.accept_after_solution);
    -- กำหนดส่ง/วันปิดรับ: ส่งมาได้เฉพาะค่าเดิม (การเปลี่ยนมากับ M1/M2 ใน P4-03)
    if p_post ? 'due_at' then
      v_due := private.jsonb_timestamptz(p_post -> 'due_at');
      if v_due is distinct from v_assignment.due_at then
        raise exception using errcode = 'P0001', message = 'invalid_request';
      end if;
    end if;
    if p_post ? 'close_at' then
      v_close := case when jsonb_typeof(p_post -> 'close_at') = 'null' then null
                      else coalesce(private.jsonb_timestamptz(p_post -> 'close_at'), '-infinity') end;
      if v_close is distinct from v_assignment.close_at then
        raise exception using errcode = 'P0001', message = 'invalid_request';
      end if;
    end if;
    v_assignment_changed := v_full <> v_assignment.full_score or v_late <> v_assignment.late_penalty_pct
                            or v_reward <> v_assignment.reward_tokens
                            or v_after <> v_assignment.accept_after_solution;
  end if;

  if v_content_changed or v_assignment_changed then
    update public.posts
       set title = v_title,
           body = v_body,
           content_updated_at = case when v_content_changed then clock_timestamp() else content_updated_at end,
           version = version + 1
     where id = p_post_id
    returning * into v_post;
    if v_assignment_changed then
      -- ช่องที่ล็อกแล้วถูกกันโดย trigger ใน 0010_posts (reward_locked / full_score_locked / after_solution_locked)
      update public.assignments
         set full_score = v_full, late_penalty_pct = v_late, reward_tokens = v_reward, accept_after_solution = v_after
       where post_id = p_post_id
      returning * into v_assignment;
    end if;
  end if;

  v_result := jsonb_build_object(
    'post_id', v_post.id,
    'classroom_id', v_post.classroom_id,
    'kind', v_post.kind,
    'title', v_post.title,
    'body', v_post.body,
    'published_at', v_post.published_at,
    'content_updated_at', v_post.content_updated_at,
    'version', v_post.version,
    'files', private.post_files_json(v_post.id),
    'changed', v_content_changed or v_assignment_changed,
    'assignment', case when v_post.kind = 'homework' then jsonb_build_object(
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
