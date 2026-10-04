-- 0015_post_update: แก้โพสต์หลังโพสต์ (T02 โหมดแก้ไข) — TECHNICAL_BUILD_PLAN 4.2 แถว 6e (P3-02b)
-- TECHNICAL_DESIGN ส่วน 10 (PATCH /posts/:id, /assignments/:id); SYSTEM_SPEC N1, N2, I4, J2/L4/K2; UX_DESIGN ส่วน 9
-- update_post(p_post_id, p_post jsonb, p_expected_version, p_request_key, p_admin_mode)
--   p_post รูปแบบเดียวกับ create_post (0014) — คีย์ที่ไม่ส่ง = คงค่าเดิม; kind ต้องตรงกับของเดิม (N2 เปลี่ยนชนิดไม่ได้)
--   แก้ได้: ชื่อ, รายละเอียด/ข้อความ; การบ้านแก้คะแนนเต็ม, % หัก, โทเคน, รับหลังเฉลย ได้จนกว่าจะล็อก (ตัวกันใน 0010_posts
--   ตอบ full_score_locked / reward_locked / after_solution_locked — ส่งค่าเดิมของช่องที่ล็อกมาได้)
--   กำหนดส่ง/วันปิดรับยังไม่รับการเปลี่ยนในรอบนี้ (M1/M2 + I2 ใน P4-03): ส่งค่าต่างจากเดิม → invalid_request
--   content_updated_at (N1: "ครูแก้ไขโจทย์ล่าสุด") ขยับเฉพาะเมื่อชื่อหรือรายละเอียดเปลี่ยนจริง; ไม่มีอะไรเปลี่ยน = ไม่ขยับ version
--   และเวลา; ไม่สร้างแจ้งเตือน (N1); ไม่จำกัดตามสถานะภาคเรียน (N2: หลังจบภาคเรียนครูยังแก้ได้)
--   request key ตรวจก่อน version: ส่งซ้ำจากเน็ตหลุดได้ผลเดิม ไม่ใช่ stale_revision

-- รหัสที่หน้าเว็บอาจเจอ: stale_revision, full_score_locked, reward_locked, after_solution_locked และรหัสเนื้อหาเดียวกับ
-- create_post (post_title_invalid, post_body_required, post_body_too_long, full_score_invalid, late_penalty_invalid,
-- reward_tokens_invalid), forbidden, admin_mode_required — รหัสภายใน: invalid_request, request_key_required,
-- request_key_conflict
-- ผล: { post_id, classroom_id, kind, title, body, published_at, content_updated_at, version, changed,
--       assignment: { full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution } | null }
create function public.update_post(
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
                                   when 'homework' then array['kind', 'title', 'body', 'full_score', 'late_penalty_pct',
                                                              'reward_tokens', 'due_at', 'close_at', 'accept_after_solution']
                                   else array['kind', 'title', 'body']
                                 end))
     or (p_post ? 'title' and jsonb_typeof(p_post -> 'title') <> 'string')
     or (p_post ? 'body' and jsonb_typeof(p_post -> 'body') not in ('string', 'null'))
     or (p_post ? 'accept_after_solution' and jsonb_typeof(p_post -> 'accept_after_solution') <> 'boolean') then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

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
  if v_post.kind = 'announcement' and v_body is null then
    raise exception using errcode = 'P0001', message = 'post_body_required';
  end if;
  v_content_changed := v_title is distinct from v_post.title or v_body is distinct from v_post.body;

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
grant execute on function public.update_post(uuid, jsonb, integer, uuid, boolean) to authenticated;
