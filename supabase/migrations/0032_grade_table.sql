-- 0032_grade_table: ตารางคะแนนของห้อง (T04) — แถวนักเรียน/คอลัมน์งาน — P4-07
-- UX_DESIGN ส่วน 9 (T04 แยกช่อง “ยังไม่ส่ง”, “รอตรวจ”, “0”), TECHNICAL_DESIGN ส่วน 2 (ยังไม่ตรวจไม่เท่ากับ 0 คะแนน)
-- อ่านอย่างเดียว: ครูเจ้าของห้อง หรือผู้ดูแล (ไม่ต้องโหมดผู้ดูแล — แบบเดียวกับ teacher_work_summary 0022); ห้องที่ไม่มี/ไม่มีสิทธิ์ → forbidden
-- ผล: { classroom_id, term_id, term_name,
--        assignments: [{ post_id, title, due_at, full_score, published_at }]   เรียงโพสต์เก่า → ใหม่ (ซ้าย → ขวา)
--        rows: [{ student_id, roll_number, display_name, member, cells: { <post_id>: { state, raw, net, late } } }] }
--   cells ไม่มีคีย์ของงานนั้น = ยังไม่ส่ง
--   state = 'waiting'  ส่งแล้วแต่รุ่นล่าสุดยังไม่มีผลตรวจ (private.submission_latest_graded = false — ผลของรุ่นเก่านับเป็นรอตรวจ)
--         = 'graded'   รุ่นล่าสุดมีผลตรวจ: net = คะแนนสุทธิหลังหัก (null เมื่อครูบันทึกเฉพาะความครบถ้วน ไม่ให้คะแนน), raw = ก่อนหัก,
--                      late = เวลาที่ใช้ตรวจนับเป็นส่งช้า (grades.timing)
-- แถว = สมาชิกขณะนี้ ∪ นักเรียนที่ถูกเอาออกแล้วแต่มีงานส่งในห้องนี้ (member = false) เลขที่ตามรายชื่อของภาคเรียนของห้อง
--   เรียงเลขที่ (ไม่มีไว้ท้าย) แล้วชื่อ
-- รหัสที่หน้าเว็บอาจเจอ: forbidden

create function public.teacher_grade_table(p_classroom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_classroom public.classrooms;
begin
  select c.* into v_classroom from public.classrooms c where c.id = p_classroom_id;
  if v_classroom.id is null or not private.can_teach_classroom(p_classroom_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return jsonb_build_object(
    'classroom_id', v_classroom.id,
    'term_id', v_classroom.term_id,
    'term_name', (select t.name from public.terms t where t.id = v_classroom.term_id),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'post_id', p.id, 'title', p.title, 'due_at', a.due_at,
               'full_score', a.full_score, 'published_at', p.published_at)
               order by p.published_at, p.id)
        from public.posts p
        join public.assignments a on a.post_id = p.id
       where p.classroom_id = p_classroom_id), '[]'::jsonb),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'student_id', st.id,
               'roll_number', e.roll_number,
               'display_name', st.display_name,
               'member', x.member,
               'cells', coalesce((
                 select jsonb_object_agg(s.assignment_id::text,
                          case when private.submission_latest_graded(s.id)
                               then jsonb_build_object('state', 'graded', 'raw', g.raw_score,
                                                       'net', g.net_score, 'late', g.timing = 'late')
                               else jsonb_build_object('state', 'waiting') end)
                   from public.submissions s
                   join public.posts p on p.id = s.assignment_id and p.classroom_id = p_classroom_id
                   left join public.grades g on g.submission_id = s.id
                  where s.student_id = st.id), '{}'::jsonb))
               order by e.roll_number nulls last, st.display_name, st.id)
        from (select m.student_id, true as member
                from public.memberships m
               where m.classroom_id = p_classroom_id
              union all
              select distinct s.student_id, false
                from public.submissions s
                join public.posts p on p.id = s.assignment_id
               where p.classroom_id = p_classroom_id
                 and not exists (select 1 from public.memberships m
                                  where m.classroom_id = p_classroom_id and m.student_id = s.student_id)) x
        join public.students st on st.id = x.student_id
        left join public.roster_entries e on e.student_id = st.id and e.term_id = v_classroom.term_id), '[]'::jsonb));
end
$$;
revoke all on function public.teacher_grade_table(uuid) from public, anon;
grant execute on function public.teacher_grade_table(uuid) to authenticated;
