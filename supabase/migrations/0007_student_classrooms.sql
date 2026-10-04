-- 0007_student_classrooms: ข้อมูลห้องฝั่งนักเรียน (S01 การ์ดห้อง, S02 หัวห้องและสมาชิก, S06 ชั้นเรียน)
-- นักเรียนอ่าน teachers/รายชื่อเพื่อนผ่านตารางตรงไม่ได้ (RLS เห็นแค่แถวตัวเอง) จึงให้ RPC คืนเฉพาะช่องที่หน้าจอใช้:
-- ชื่อห้อง ชื่อครู จำนวนสมาชิก และชื่อ + เลขที่ของเพื่อนในห้อง — ไม่คืนเลขประจำตัว อีเมล หรือห้องตามรายชื่อของคนอื่น (UX 5)
-- ตรวจ membership ทุกคำขอ: เอาออกแล้วเรียก classroom_view ได้ not_member ทันที

-- ชั้นเรียนของฉันในภาคเรียนปัจจุบัน เรียงตามวันที่เข้า — ยังไม่ผูกชื่อได้รายการว่าง
-- ผล: [{ id, name, description, teacher_name, member_count, joined_at }]
create function public.my_classrooms()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  perform private.require_student_account();
  v_student_id := private.current_student();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id,
             'name', c.name,
             'description', c.description,
             'teacher_name', t.display_name,
             'member_count', (select count(*) from public.memberships x where x.classroom_id = c.id),
             'joined_at', m.joined_at
           ) order by m.joined_at, c.name)
      from public.memberships m
      join public.classrooms c on c.id = m.classroom_id
      join public.teachers t on t.id = c.teacher_id
      join public.term_control tc on tc.singleton and tc.term_id = c.term_id
     where m.student_id = v_student_id
  ), '[]'::jsonb);
end
$$;
grant execute on function public.my_classrooms() to authenticated;

-- หัวห้องและสมาชิกสำหรับนักเรียนในห้อง (S02) — ไม่ใช่สมาชิกขณะนี้ → not_member (UX 7.1)
-- ผล: { id, name, description, teacher_name, term_name, member_count,
--        members: [{ display_name, roll_number, is_me }] }  (เลขที่ตามรายชื่อภาคเรียนของห้องนั้น)
create function public.classroom_view(p_classroom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  perform private.require_student_account();
  v_student_id := private.require_member(p_classroom_id);
  return (
    select jsonb_build_object(
             'id', c.id,
             'name', c.name,
             'description', c.description,
             'teacher_name', t.display_name,
             'term_name', tm.name,
             'member_count', (select count(*) from public.memberships x where x.classroom_id = c.id),
             'members', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'display_name', s.display_name,
                        'roll_number', e.roll_number,
                        'is_me', s.id = v_student_id
                      ) order by e.roll_number nulls last, s.display_name)
                 from public.memberships m
                 join public.students s on s.id = m.student_id
                 left join public.roster_entries e on e.student_id = s.id and e.term_id = c.term_id
                where m.classroom_id = c.id
             ), '[]'::jsonb))
      from public.classrooms c
      join public.teachers t on t.id = c.teacher_id
      join public.terms tm on tm.id = c.term_id
     where c.id = p_classroom_id
  );
end
$$;
grant execute on function public.classroom_view(uuid) to authenticated;
