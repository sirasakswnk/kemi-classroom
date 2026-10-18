-- ทดสอบ 0032_grade_table: ตารางคะแนน (T04) — ยังไม่ส่ง / รอตรวจ (รวมผลของรุ่นเก่า) / ตรวจแล้วมีและไม่มีคะแนน / ได้ 0,
-- แถวสมาชิก + คนที่ถูกเอาออกแต่มีงานส่ง, เลขที่ตามรายชื่อเทอม, สิทธิ์ — ข้อมูลสมมติ rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure
      from pg_proc p
      join pg_depend d on d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
      join pg_extension e on e.oid = d.refobjid and e.extname = 'pgtap'
  loop
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end
$$;

select plan(11);

-- ครู 1 ห้อง 1, ครู 2, ผู้ดูแล, นักเรียน; S1–S3,S5 สมาชิก, S4 ถูกเอาออกแต่มีงานส่ง
insert into public.terms (id, name, status) values ('4e200000-0000-4000-8000-000000000001', 'ภาคทดสอบตาราง', 'active');
insert into public.term_control (term_id) values ('4e200000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e200000-0000-4000-8000-000000000001', 'ครูตารางหนึ่ง'), ('1e200000-0000-4000-8000-000000000002', 'ครูตารางสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e200000-0000-4000-8000-000000000001', '2e200000-0000-4000-8000-000000000001', 'google', 'gt-1', 'g32a@example.com', 'teacher', '1e200000-0000-4000-8000-000000000001'),
  ('3e200000-0000-4000-8000-000000000002', '2e200000-0000-4000-8000-000000000002', 'google', 'gt-2', 'g32b@example.com', 'teacher', '1e200000-0000-4000-8000-000000000002'),
  ('3e200000-0000-4000-8000-000000000003', '2e200000-0000-4000-8000-000000000003', 'google', 'gt-3', 'g32c@example.com', 'admin', null),
  ('3e200000-0000-4000-8000-000000000011', '2e200000-0000-4000-8000-000000000011', 'google', 'gt-11', 'g32s@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e200000-0000-4000-8000-000000000001', '932000000000321', 'หนึ่ง ตาราง', '3e200000-0000-4000-8000-000000000011'),
  ('6e200000-0000-4000-8000-000000000002', '932000000000322', 'สอง ตาราง', null),
  ('6e200000-0000-4000-8000-000000000003', '932000000000323', 'สาม ตาราง', null),
  ('6e200000-0000-4000-8000-000000000004', '932000000000324', 'สี่ ตาราง', null),
  ('6e200000-0000-4000-8000-000000000005', '932000000000325', 'ห้า ตาราง', null);
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('4e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000001', 'ม.5/9', 2),
  ('4e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000002', 'ม.5/9', 1);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e200000-0000-4000-8000-000000000001', '4e200000-0000-4000-8000-000000000001', '1e200000-0000-4000-8000-000000000001', 'เคมีตาราง 1', 'ZZZZ92');
insert into public.memberships (classroom_id, student_id) values
  ('7e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000001'),
  ('7e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000002'),
  ('7e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000003'),
  ('7e200000-0000-4000-8000-000000000001', '6e200000-0000-4000-8000-000000000005');
-- งาน A (เก่า) / B (ใหม่) + ประกาศ (ต้องไม่อยู่ในตาราง)
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8e200000-0000-4000-8000-00000000000a', '7e200000-0000-4000-8000-000000000001', 'homework', 'งาน A', '2026-09-20T01:00:00Z'),
  ('8e200000-0000-4000-8000-00000000000b', '7e200000-0000-4000-8000-000000000001', 'homework', 'งาน B', '2026-09-25T01:00:00Z');
insert into public.posts (id, classroom_id, kind, title, body, published_at) values
  ('8e200000-0000-4000-8000-00000000000c', '7e200000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ', 'x', '2026-09-26T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('8e200000-0000-4000-8000-00000000000a', 10, '2026-09-30T13:00:00Z'),
  ('8e200000-0000-4000-8000-00000000000b', 20, '2026-10-05T13:00:00Z');
-- งานส่ง: S1: A graded(สาย) B waiting · S2: A ผลของรุ่นเก่า(rev 2 / graded 1) · S3: A ตรวจไม่ให้คะแนน, B ได้ 0
--         S4 (ถูกเอาออก): A waiting
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, content_revision) values
  ('5e200000-0000-4000-8000-0000000000a1', '8e200000-0000-4000-8000-00000000000a', '6e200000-0000-4000-8000-000000000001', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', 1),
  ('5e200000-0000-4000-8000-0000000000b1', '8e200000-0000-4000-8000-00000000000b', '6e200000-0000-4000-8000-000000000001', '2026-10-02T01:00:00Z', '2026-10-02T01:00:00Z', 1),
  ('5e200000-0000-4000-8000-0000000000a2', '8e200000-0000-4000-8000-00000000000a', '6e200000-0000-4000-8000-000000000002', '2026-09-29T01:00:00Z', '2026-09-29T02:00:00Z', 2),
  ('5e200000-0000-4000-8000-0000000000a3', '8e200000-0000-4000-8000-00000000000a', '6e200000-0000-4000-8000-000000000003', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', 1),
  ('5e200000-0000-4000-8000-0000000000b3', '8e200000-0000-4000-8000-00000000000b', '6e200000-0000-4000-8000-000000000003', '2026-10-04T01:00:00Z', '2026-10-04T01:00:00Z', 1),
  ('5e200000-0000-4000-8000-0000000000a4', '8e200000-0000-4000-8000-00000000000a', '6e200000-0000-4000-8000-000000000004', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', 1);
insert into public.grades (submission_id, raw_score, passed, timing, timing_due_at, timing_basis_at, timing_i1,
                           applied_penalty_pct, deduction, net_score, graded_revision, graded_at, graded_by_account_id) values
  ('5e200000-0000-4000-8000-0000000000a1', 9, true, 'late', '2026-09-30T13:00:00Z', '2026-10-01T01:00:00Z', false, 20, 1, 8, 1, '2026-10-03T01:00:00Z', '3e200000-0000-4000-8000-000000000001'),
  ('5e200000-0000-4000-8000-0000000000a2', 7, true, 'on_time', '2026-09-30T13:00:00Z', '2026-09-29T01:00:00Z', false, 0, 0, 7, 1, '2026-10-03T01:00:00Z', '3e200000-0000-4000-8000-000000000001'),
  ('5e200000-0000-4000-8000-0000000000a3', null, true, 'on_time', '2026-09-30T13:00:00Z', '2026-09-29T01:00:00Z', false, 0, null, null, 1, '2026-10-03T01:00:00Z', '3e200000-0000-4000-8000-000000000001'),
  ('5e200000-0000-4000-8000-0000000000b3', 0, false, 'late', '2026-10-05T13:00:00Z', '2026-10-04T01:00:00Z', false, 0, 0, 0, 1, '2026-10-06T01:00:00Z', '3e200000-0000-4000-8000-000000000001');

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- เซลล์ของนักเรียนชื่อหนึ่งในตารางของห้องทดสอบ
create function pg_temp.cells_of(p_name text) returns jsonb language sql stable as
  $$ select e -> 'cells'
       from jsonb_array_elements(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'rows') e
      where e ->> 'display_name' = p_name $$;
grant execute on function pg_temp.cells_of(text) to authenticated;

set local role authenticated;
select pg_temp.as_user('2e200000-0000-4000-8000-000000000001');

select is((select jsonb_agg(e -> 'title') from jsonb_array_elements(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'assignments') e),
  '["งาน A", "งาน B"]'::jsonb, 'คอลัมน์เป็นการบ้านเรียงเก่า → ใหม่ ไม่มีประกาศ');
select is(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'term_name', '"ภาคทดสอบตาราง"'::jsonb, 'บอกชื่อภาคเรียนของห้อง');
select is((select jsonb_agg(e -> 'full_score') from jsonb_array_elements(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'assignments') e),
  '[10, 20]'::jsonb, 'คะแนนเต็มต่องาน');

select is((select jsonb_agg(e -> 'display_name') from jsonb_array_elements(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'rows') e),
  '["สอง ตาราง", "หนึ่ง ตาราง", "สาม ตาราง", "สี่ ตาราง", "ห้า ตาราง"]'::jsonb,
  'แถว = สมาชิก 4 คน + คนที่ถูกเอาออกแต่มีงานส่ง เรียงเลขที่ (สอง = 1, หนึ่ง = 2) คนไม่มีเลขที่ตามชื่อ');
select is((select jsonb_agg(e -> 'member') from jsonb_array_elements(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'rows') e),
  '[true, true, true, false, true]'::jsonb, 'คนที่ถูกเอาออก member = false');

select is(pg_temp.cells_of('หนึ่ง ตาราง'),
  '{"8e200000-0000-4000-8000-00000000000a": {"net": 8, "raw": 9, "late": true, "state": "graded"},
    "8e200000-0000-4000-8000-00000000000b": {"state": "waiting"}}'::jsonb,
  'ตรวจแล้ว = คะแนนสุทธิ/ก่อนหัก/ส่งช้า · ส่งแล้วยังไม่ตรวจ = waiting');
select is(pg_temp.cells_of('สอง ตาราง'),
  '{"8e200000-0000-4000-8000-00000000000a": {"state": "waiting"}}'::jsonb,
  'ผลตรวจเป็นของรุ่นเก่า (ส่งแก้แล้ว) = รอตรวจ ไม่แสดงคะแนนเก่า');
select is(pg_temp.cells_of('สาม ตาราง'),
  '{"8e200000-0000-4000-8000-00000000000a": {"net": null, "raw": null, "late": false, "state": "graded"},
    "8e200000-0000-4000-8000-00000000000b": {"net": 0, "raw": 0, "late": true, "state": "graded"}}'::jsonb,
  'ตรวจแล้วไม่ให้คะแนน net = null (ไม่ใช่ 0) · ตรวจแล้วได้ 0 net = 0');
select is(pg_temp.cells_of('ห้า ตาราง'), '{}'::jsonb, 'ยังไม่ส่งสักงาน = ไม่มีเซลล์');

-- สิทธิ์
select pg_temp.as_user('2e200000-0000-4000-8000-000000000002');
select throws_ok($$ select public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden', 'ครูห้องอื่น → forbidden');
select pg_temp.as_user('2e200000-0000-4000-8000-000000000003');
select is(jsonb_array_length(public.teacher_grade_table('7e200000-0000-4000-8000-000000000001') -> 'rows'), 5, 'ผู้ดูแลอ่านได้โดยไม่ต้องโหมดผู้ดูแล');

select * from finish();
rollback;
