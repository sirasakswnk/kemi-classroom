-- 0027_feedback: เปิดสิทธิ์แก้ (K3) และความคิดเห็นส่วนตัว เขียน/ยกเลิก (F5) — migration กลุ่ม grading ส่วนที่สอง (P4-02)
-- TECHNICAL_DESIGN ส่วน 5 (K3), 10 (POST /submissions/:id/revision-permission, POST /assignments/:id/comments,
-- POST /comments/:id/retract), 11; SYSTEM_SPEC ส่วน 6, K3, K5, F5; UX_DESIGN ส่วน 8
-- หลัก:
--   - open_revision_permission: ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแลเปิดสิทธิ์ส่งแก้หนึ่งครั้งให้งานส่งที่มีอยู่
--     (มีสิทธิ์ได้เฉพาะงานที่เคยส่งแล้ว — แถว 7); เปิดค้างได้ทีละหนึ่ง: กดเมื่อมีสิทธิ์ค้างอยู่คืนสิทธิ์เดิม
--     (already_open = true) ไม่สร้างแถวใหม่; ใช้แล้ว (submit_assignment ใน transaction เดียวกับการส่งสำเร็จ — 0020)
--     ครูเปิดใหม่เป็นแถวใหม่ได้; ไม่มีคำสั่งยกเลิกสิทธิ์ (แบบ v2 มีแค่ปุ่มเปิด) — สถานะ revoked ของตารางยังไม่ใช้
--   - post_comment: ช่องความคิดเห็นของ (งาน, นักเรียน) แม้ยังไม่ส่ง; นักเรียนเขียนในช่องตัวเองเท่านั้น ต้องเป็นสมาชิก
--     ขณะนี้และภาคเรียนยังเปิด (K5: จบภาคเรียนแล้วเขียนใหม่ไม่ได้); ครูเขียนถึงคนในรายชื่อของงาน
--     (สมาชิกขณะนี้ ∪ คนที่ถูกเอาออกแต่มีงานส่ง — private.assignment_people) ได้แม้จบภาคเรียน
--   - retract_comment: เจ้าของข้อความเท่านั้น; ล้างข้อความ + ตั้ง retracted_at (ไม่เก็บสำเนา) ไม่ย้อนคะแนน ผ่าน
--     สิทธิ์แก้ หรือโทเคน (ความคิดเห็นที่เป็นเหตุผลปรับการหักยกเลิกได้ ผลตรวจคงอยู่); เรียกซ้ำคืนผลเดิม;
--     นักเรียนยกเลิกได้ภายใต้เงื่อนไขเดียวกับการเขียน (สมาชิกขณะนี้ + ภาคเรียนเปิด)
--   - แจ้งเตือน (ครูเขียน/เปิดแก้ → นักเรียน, นักเรียนเขียน → ครู) มากับระยะ 6
--
-- รหัสที่หน้าเว็บอาจเจอ: forbidden, admin_mode_required, not_member, term_ended, student_not_found, comment_too_long
-- รหัสภายใน: invalid_request (ข้อความว่าง — ปุ่มส่งปิดอยู่แล้ว), request_key_required, request_key_conflict

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- ครูเจ้าของห้องของโพสต์ หรือผู้ดูแลในโหมดผู้ดูแล — ไม่ล็อกแถวห้อง (คงลำดับล็อกของ RPC ที่เรียก); โพสต์ที่ไม่มี = forbidden
create function private.require_post_teacher(p_post_id uuid, p_admin_mode boolean)
returns public.accounts
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_teacher_id uuid;
begin
  v_account := private.require_teacher(p_admin_mode);
  select c.teacher_id into v_teacher_id
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_post_id;
  if not found or (v_account.role = 'teacher' and v_teacher_id is distinct from v_account.teacher_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return v_account;
end
$$;

-- นักเรียนเขียน/ยกเลิกความคิดเห็นในงานนี้ได้หรือไม่: สมาชิกขณะนี้ (not_member) และภาคเรียนเปิด (term_ended)
-- ผู้เรียกถือล็อก term_control แบบ share ก่อน; คืน student_id ของผู้เรียก
create function private.require_comment_student(p_assignment_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_classroom public.classrooms;
  v_student_id uuid;
begin
  select c.* into v_classroom
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id and p.kind = 'homework';
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  v_student_id := private.require_member(v_classroom.id);
  perform private.require_current_term(v_classroom.term_id);
  return v_student_id;
end
$$;

create function private.comment_json(p_comment public.comments)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'comment_id', p_comment.id,
    'assignment_id', p_comment.assignment_id,
    'student_id', p_comment.student_id,
    'author_account_id', p_comment.author_account_id,
    'author_role', (select a.role from public.accounts a where a.id = p_comment.author_account_id),
    'body', p_comment.body,
    'created_at', p_comment.created_at,
    'retracted_at', p_comment.retracted_at)
$$;

-- ---------------------------------------------------------------------------
-- 2. เปิดสิทธิ์แก้ (POST /submissions/:id/revision-permission)
-- ---------------------------------------------------------------------------
-- ผล: { permission_id, submission_id, status: 'open', opened_at, already_open }
create function public.open_revision_permission(
  p_submission_id uuid,
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
  v_assignment_id uuid;
  v_operation text;
  v_prior jsonb;
  v_perm public.revision_permissions;
  v_already boolean := true;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_submission_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'open_revision_permission:' || p_submission_id;
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  select s.assignment_id into v_assignment_id from public.submissions s where s.id = p_submission_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.require_post_teacher(v_assignment_id, p_admin_mode);

  -- ล็อกงานส่ง (ล็อกเดียวกับ submit_assignment) แล้วจึงสิทธิ์ค้าง — การส่งที่กำลังใช้สิทธิ์จบก่อน
  perform 1 from public.submissions s where s.id = p_submission_id for update;
  select r.* into v_perm from public.revision_permissions r
   where r.submission_id = p_submission_id and r.status = 'open' for update;
  if not found then
    insert into public.revision_permissions (submission_id, opened_by_account_id, opened_at)
    values (p_submission_id, v_account.id, clock_timestamp())
    returning * into v_perm;
    v_already := false;
  end if;

  v_result := jsonb_build_object(
    'permission_id', v_perm.id,
    'submission_id', v_perm.submission_id,
    'status', v_perm.status,
    'opened_at', v_perm.opened_at,
    'already_open', v_already);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.open_revision_permission(uuid, uuid, boolean) from public, anon;
grant execute on function public.open_revision_permission(uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. เขียนความคิดเห็น (POST /assignments/:id/comments)
-- ---------------------------------------------------------------------------
-- p_student_id: นักเรียนส่ง null (หรือ id ตัวเอง); ครู/ผู้ดูแลต้องระบุ
-- ผล: comment_json
create function public.post_comment(
  p_assignment_id uuid,
  p_student_id uuid,
  p_body text,
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
  v_body text;
  v_student_id uuid;
  v_operation text;
  v_prior jsonb;
  v_comment public.comments;
  v_result jsonb;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  -- ครู/ผู้ดูแล: ตรวจโหมดผู้ดูแลก่อนอย่างอื่น (แบบเดียวกับ RPC ฝั่งครูทุกตัว — เทสต์รวมใน 0009)
  if v_account.role <> 'student' then
    v_account := private.require_teacher(p_admin_mode);
  end if;
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  v_body := private.trim_text(p_body);
  if p_assignment_id is null or v_body is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if length(v_body) > 2000 then
    raise exception using errcode = 'P0001', message = 'comment_too_long';
  end if;

  v_operation := 'post_comment:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'student_id', p_student_id, 'body', v_body)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  if v_account.role = 'student' then
    -- K5: การจบภาคเรียนล็อก term_control แบบ exclusive จึงไม่มีข้อความที่หลุดเข้ามาหลังจบภาคเรียน
    perform 1 from public.term_control c where c.singleton for share;
    v_student_id := private.require_comment_student(p_assignment_id);
    if p_student_id is not null and p_student_id <> v_student_id then
      raise exception using errcode = 'P0001', message = 'forbidden';
    end if;
  else
    perform private.require_post_teacher(p_assignment_id, p_admin_mode);
    if not exists (select 1 from public.assignments a where a.post_id = p_assignment_id) then
      raise exception using errcode = 'P0001', message = 'forbidden';
    end if;
    if p_student_id is null
       or not exists (select 1 from private.assignment_people(p_assignment_id) x where x.student_id = p_student_id) then
      raise exception using errcode = 'P0001', message = 'student_not_found';
    end if;
    v_student_id := p_student_id;
  end if;

  insert into public.comments (assignment_id, student_id, author_account_id, body, created_at)
  values (p_assignment_id, v_student_id, v_account.id, v_body, clock_timestamp())
  returning * into v_comment;

  v_result := private.comment_json(v_comment);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.post_comment(uuid, uuid, text, uuid, boolean) from public, anon;
grant execute on function public.post_comment(uuid, uuid, text, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. ยกเลิกความคิดเห็น (POST /comments/:id/retract)
-- ---------------------------------------------------------------------------
-- ผล: comment_json (body = null) — เรียกซ้ำคืนผลเดิม
create function public.retract_comment(
  p_comment_id uuid,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_comment public.comments;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  -- ครู/ผู้ดูแล: ตรวจโหมดผู้ดูแลก่อนอย่างอื่น (แบบเดียวกับ RPC ฝั่งครูทุกตัว — เทสต์รวมใน 0009)
  if v_account.role <> 'student' then
    v_account := private.require_teacher(p_admin_mode);
  end if;
  if p_comment_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select c.* into v_comment from public.comments c where c.id = p_comment_id;
  -- เฉพาะข้อความของตัวเอง (ไม่บอกว่าข้อความของคนอื่นมีอยู่หรือไม่)
  if not found or v_comment.author_account_id <> v_account.id then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  if v_account.role = 'student' then
    perform 1 from public.term_control c where c.singleton for share;
    perform private.require_comment_student(v_comment.assignment_id);
  else
    perform private.require_post_teacher(v_comment.assignment_id, p_admin_mode);
  end if;

  select c.* into v_comment from public.comments c where c.id = p_comment_id for update;
  if v_comment.retracted_at is null then
    update public.comments set body = null, retracted_at = clock_timestamp()
     where id = p_comment_id
    returning * into v_comment;
  end if;
  return private.comment_json(v_comment);
end
$$;
revoke all on function public.retract_comment(uuid, boolean) from public, anon;
grant execute on function public.retract_comment(uuid, boolean) to authenticated;
