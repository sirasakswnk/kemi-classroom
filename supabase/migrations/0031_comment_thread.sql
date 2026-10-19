-- 0031_comment_thread: อ่านช่องความคิดเห็นส่วนตัวของ (งาน, นักเรียน) สำหรับหน้าจอ — P4-05a
-- UX_DESIGN ส่วน 8 (แสดงผู้ส่งและเวลา, ยกเลิกเฉพาะของตน, “ข้อความนี้ถูกยกเลิก”); SYSTEM_SPEC ส่วน 6, K5
-- ทำไมต้องเป็น RPC: นักเรียนอ่านตาราง accounts/teachers ของครูผ่าน RLS ไม่ได้ จึงไม่รู้ชื่อผู้ส่ง และหน้าจอต้องรู้ว่าผู้เรียก
-- เขียนได้หรือไม่ (ซ่อนกล่องเขียน/ปุ่มยกเลิกเมื่อจบภาคเรียนหรือไม่ได้อยู่ในห้องแล้ว — เงื่อนไขเดียวกับ post_comment 0027)
-- อ่านอย่างเดียว: นักเรียนเจ้าของช่อง (แม้ถูกเอาออกจากห้องแล้ว — แบบเดียวกับ RLS comments_select) หรือครูเจ้าของห้อง/
-- ผู้ดูแล (ไม่ต้องโหมดผู้ดูแล — การเขียนตรวจโหมดเอง)
-- ผล: { assignment_id, student_id, can_write,
--       comments: [{ comment_id, author_role, author_name, mine, body, created_at, retracted_at }] } เรียงเวลาเขียน
--   author_name: นักเรียน = ชื่อในรายชื่อ, ครู = ชื่อครู, ผู้ดูแล = null (หน้าจอแสดง “ผู้ดูแลระบบ”); ยกเลิกแล้ว body = null
-- รหัสที่หน้าเว็บอาจเจอ: forbidden, student_not_found

create function public.comment_thread(p_assignment_id uuid, p_student_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_classroom public.classrooms;
  v_student_id uuid;
  v_can_write boolean;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  select c.* into v_classroom
    from public.posts p
    join public.assignments a on a.post_id = p.id
    join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  if v_account.role = 'student' then
    v_student_id := private.current_student();
    if v_student_id is null or (p_student_id is not null and p_student_id <> v_student_id) then
      raise exception using errcode = 'P0001', message = 'forbidden';
    end if;
    -- เขียนได้: สมาชิกขณะนี้ และภาคเรียนของห้องเป็นภาคเรียนปัจจุบันที่ยังเปิด (K5)
    v_can_write := private.is_member(v_classroom.id)
                   and exists (select 1 from public.term_control t
                                where t.singleton and t.status = 'active' and t.term_id = v_classroom.term_id);
  else
    if not private.can_teach_classroom(v_classroom.id) then
      raise exception using errcode = 'P0001', message = 'forbidden';
    end if;
    if p_student_id is null
       or not exists (select 1 from private.assignment_people(p_assignment_id) x where x.student_id = p_student_id) then
      raise exception using errcode = 'P0001', message = 'student_not_found';
    end if;
    v_student_id := p_student_id;
    v_can_write := true;
  end if;

  return jsonb_build_object(
    'assignment_id', p_assignment_id,
    'student_id', v_student_id,
    'can_write', v_can_write,
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'comment_id', c.id,
               'author_role', a.role,
               'author_name', case a.role
                                when 'student' then (select s.display_name from public.students s where s.account_id = a.id)
                                when 'teacher' then (select t.display_name from public.teachers t where t.id = a.teacher_id)
                              end,
               'mine', c.author_account_id = v_account.id,
               'body', c.body,
               'created_at', c.created_at,
               'retracted_at', c.retracted_at)
               order by c.created_at, c.id)
        from public.comments c
        join public.accounts a on a.id = c.author_account_id
       where c.assignment_id = p_assignment_id and c.student_id = v_student_id), '[]'::jsonb));
end
$$;
revoke all on function public.comment_thread(uuid, uuid) from public, anon;
grant execute on function public.comment_thread(uuid, uuid) to authenticated;
