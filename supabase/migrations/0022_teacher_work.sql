-- 0022_teacher_work: ภาพรวมงานส่งสำหรับครู — T08 ยอดต่องาน และ T03 รายชื่อสถานะของงานหนึ่ง (P3-09)
-- UX_DESIGN ส่วน 9 (T03 [ยืนยันเพิ่มใน HTML ครู], T08 [ข้อเสนอ]); TECHNICAL_DESIGN ส่วน 2 (memberships: เอาออกแล้วงานไม่หาย), 5
-- อ่านอย่างเดียว: ครูเจ้าของห้อง หรือผู้ดูแล (ไม่ต้องส่ง admin mode — การอ่านใช้สิทธิ์เดียวกับ RLS can_teach_classroom)
-- นักเรียน/ครูห้องอื่น/ห้องหรืองานที่ไม่มี → forbidden (ไม่บอกว่ามีอยู่หรือไม่)
-- คนในรายชื่อของงาน = สมาชิกขณะนี้ ∪ นักเรียนที่ถูกเอาออกแล้วแต่มีงานส่งของงานนี้ (member = false → ป้าย “ออกจากห้องแล้ว”)
-- เลขที่ = roster_entries ของภาคเรียนของห้อง (แบบเดียวกับ classroom_view) เรียงเลขที่ ไม่มีเลขที่ไว้ท้าย แล้วชื่อ
-- รอตรวจ = งานส่งที่รุ่นล่าสุดยังไม่มีผลตรวจ (private.submission_latest_graded — P4-01 แทนที่); ส่งช้า = submission_timing
-- รหัสใหม่: ไม่มี

-- คนในรายชื่อของงาน (ไม่ GRANT ใคร)
create function private.assignment_people(p_assignment_id uuid)
returns table (student_id uuid, member boolean)
language sql
stable
set search_path = ''
as $$
  select m.student_id, true
    from public.posts p
    join public.memberships m on m.classroom_id = p.classroom_id
   where p.id = p_assignment_id
  union all
  select s.student_id, false
    from public.submissions s
    join public.posts p on p.id = s.assignment_id
   where s.assignment_id = p_assignment_id
     and not exists (select 1 from public.memberships m
                      where m.classroom_id = p.classroom_id and m.student_id = s.student_id)
$$;

-- T08: งานทุกชิ้นของห้อง (เรียงจากโพสต์ล่าสุด) พร้อมยอด
-- ผล: [{ post_id, due_at, close_at, intake, solution_published, total, submitted, not_submitted, waiting, late }]
create function public.teacher_work_summary(p_classroom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
begin
  if p_classroom_id is null or not private.can_teach_classroom(p_classroom_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'post_id', p.id,
             'due_at', a.due_at,
             'close_at', a.close_at,
             'intake', private.assignment_intake(p.id, v_now),
             'solution_published', exists (select 1 from public.solutions x
                                            where x.assignment_id = p.id and x.published_at is not null),
             'total', k.total,
             'submitted', k.submitted,
             'not_submitted', k.total - k.submitted,
             'waiting', k.waiting,
             'late', k.late) order by p.published_at desc, p.id)
      from public.posts p
      join public.assignments a on a.post_id = p.id
      cross join lateral (
        select count(*)::integer as total,
               count(s.id)::integer as submitted,
               count(s.id) filter (where not private.submission_latest_graded(s.id))::integer as waiting,
               count(s.id) filter (where private.submission_timing(s.first_submitted_at, s.first_after_solution,
                                                                  a.due_at) = 'late')::integer as late
          from private.assignment_people(p.id) x
          left join public.submissions s on s.assignment_id = p.id and s.student_id = x.student_id
      ) k
     where p.classroom_id = p_classroom_id), '[]'::jsonb);
end
$$;
revoke all on function public.teacher_work_summary(uuid) from public, anon;
grant execute on function public.teacher_work_summary(uuid) to authenticated;

-- T03: รายชื่อสถานะของงานหนึ่ง
-- ผล: { assignment_id, classroom_id, server_now, intake, solution_published,
--       rows: [{ student_id, roll_number, display_name, member, submission_id, first_submitted_at, last_submitted_at,
--                content_revision, timing, graded, file_count }] }
create function public.teacher_submission_list(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_classroom_id uuid;
  v_term_id uuid;
  v_due timestamptz;
  v_now timestamptz := clock_timestamp();
begin
  select c.id, c.term_id, a.due_at into v_classroom_id, v_term_id, v_due
    from public.posts p
    join public.assignments a on a.post_id = p.id
    join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id;
  if v_classroom_id is null or not private.can_teach_classroom(v_classroom_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return jsonb_build_object(
    'assignment_id', p_assignment_id,
    'classroom_id', v_classroom_id,
    'server_now', v_now,
    'intake', private.assignment_intake(p_assignment_id, v_now),
    'solution_published', exists (select 1 from public.solutions x
                                   where x.assignment_id = p_assignment_id and x.published_at is not null),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'student_id', st.id,
               'roll_number', e.roll_number,
               'display_name', st.display_name,
               'member', x.member,
               'submission_id', s.id,
               'first_submitted_at', s.first_submitted_at,
               'last_submitted_at', s.last_submitted_at,
               'content_revision', s.content_revision,
               'timing', case when s.id is not null
                              then private.submission_timing(s.first_submitted_at, s.first_after_solution, v_due) end,
               'graded', s.id is not null and private.submission_latest_graded(s.id),
               'file_count', (select count(*) from public.attachments t where t.submission_id = s.id)::integer)
               order by e.roll_number nulls last, st.display_name, st.id)
        from private.assignment_people(p_assignment_id) x
        join public.students st on st.id = x.student_id
        left join public.roster_entries e on e.student_id = st.id and e.term_id = v_term_id
        left join public.submissions s on s.assignment_id = p_assignment_id and s.student_id = st.id), '[]'::jsonb));
end
$$;
revoke all on function public.teacher_submission_list(uuid) from public, anon;
grant execute on function public.teacher_submission_list(uuid) to authenticated;
