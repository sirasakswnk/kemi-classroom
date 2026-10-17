-- ทดสอบ 0030_reopen: เปิดรับอีกครั้ง / เปลี่ยนหรือยกเลิกเวลาปิดรับก่อนเผยแพร่เฉลย; หลังเผยแพร่เปิดไม่ได้ — ข้อมูลสมมติ rollback
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

select plan(17);

-- ข้อมูลสมมติ: ครู 1 ห้อง 1, ครู 2, ผู้ดูแล; N1 สมาชิก ยังไม่ส่งงานใด
-- H1 กำหนด 2099 (ยังไม่ถึงกำหนด) · H2 กำหนดผ่านแล้ว 1 ต.ค. · H3 กำหนดผ่านแล้ว (ทดสอบหลังเผยแพร่เฉลย)
insert into public.terms (id, name, status) values ('4a100000-0000-4000-8000-000000000001', 'ภาคทดสอบเปิดรับ', 'active');
insert into public.term_control (term_id) values ('4a100000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1a100000-0000-4000-8000-000000000001', 'ครูเปิดรับหนึ่ง'), ('1a100000-0000-4000-8000-000000000002', 'ครูเปิดรับสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3a100000-0000-4000-8000-000000000001', '2a100000-0000-4000-8000-000000000001', 'google', 'ro-1', 't30a@example.com', 'teacher', '1a100000-0000-4000-8000-000000000001'),
  ('3a100000-0000-4000-8000-000000000002', '2a100000-0000-4000-8000-000000000002', 'google', 'ro-2', 't30b@example.com', 'teacher', '1a100000-0000-4000-8000-000000000002'),
  ('3a100000-0000-4000-8000-000000000003', '2a100000-0000-4000-8000-000000000003', 'google', 'ro-3', 'a30@example.com', 'admin', null),
  ('3a100000-0000-4000-8000-000000000011', '2a100000-0000-4000-8000-000000000011', 'google', 'ro-11', 's30a@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6a100000-0000-4000-8000-000000000001', '930000000000301', 'หนึ่ง เปิดรับ', '3a100000-0000-4000-8000-000000000011');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7a100000-0000-4000-8000-000000000001', '4a100000-0000-4000-8000-000000000001', '1a100000-0000-4000-8000-000000000001', 'เคมีเปิดรับ 1', 'ZZZZ83');
insert into public.memberships (classroom_id, student_id) values
  ('7a100000-0000-4000-8000-000000000001', '6a100000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8a100000-0000-4000-8000-000000000001', '7a100000-0000-4000-8000-000000000001', 'homework', 'งานเปิดรับหนึ่ง', '2026-09-20T01:00:00Z'),
  ('8a100000-0000-4000-8000-000000000002', '7a100000-0000-4000-8000-000000000001', 'homework', 'งานเปิดรับสอง', '2026-09-21T01:00:00Z'),
  ('8a100000-0000-4000-8000-000000000003', '7a100000-0000-4000-8000-000000000001', 'homework', 'งานเปิดรับสาม', '2026-09-22T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, close_at, accept_after_solution) values
  ('8a100000-0000-4000-8000-000000000001', 10, '2099-10-01T13:00:00Z', null, false),
  ('8a100000-0000-4000-8000-000000000002', 10, '2026-10-01T13:00:00Z', '2026-10-05T13:00:00Z', false),
  ('8a100000-0000-4000-8000-000000000003', 10, '2026-10-01T13:00:00Z', null, true);

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ก: ปิด → เปิดอีกครั้ง → นักเรียนส่งได้ตามแถวเวลาเดิม
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2a100000-0000-4000-8000-000000000001');
select is(public.close_assignment('8a100000-0000-4000-8000-000000000001', null, gen_random_uuid()) -> 'intake', '"closed"', 'H1 ปิดรับทันที');
select pg_temp.as_user('2a100000-0000-4000-8000-000000000011');
select is(public.submission_status('8a100000-0000-4000-8000-000000000001') -> 'blocked', '"submission_closed"', 'ปิดแล้ว: ส่งไม่ได้');
select pg_temp.as_user('2a100000-0000-4000-8000-000000000001');
select is(public.reopen_assignment('8a100000-0000-4000-8000-000000000001', null, gen_random_uuid()) - 'assignment_id',
  '{"intake": "open", "close_at": null, "closed_at": null, "after_solution_closed_at": null, "changed": true}'::jsonb,
  'เปิดรับอีกครั้ง: ล้างสถานะปิด');
select pg_temp.as_user('2a100000-0000-4000-8000-000000000011');
select is(public.submission_status('8a100000-0000-4000-8000-000000000001') -> 'outcome', '"first_on_time"',
  'เปิดอีกครั้งก่อนกำหนด: ส่งครั้งแรกได้และนับทัน (แถว 2)');

-- H2: เลยกำหนดและเลยเวลาปิดที่ตั้งไว้ → เปิดอีกครั้งพร้อมเวลาปิดใหม่ → ส่งได้แบบสาย (แถว 3)
select is(public.submission_status('8a100000-0000-4000-8000-000000000002') -> 'blocked', '"submission_closed"', 'H2 เลยเวลาปิดที่ตั้งไว้: ส่งไม่ได้');
select pg_temp.as_user('2a100000-0000-4000-8000-000000000001');
select throws_ok($$ select public.reopen_assignment('8a100000-0000-4000-8000-000000000002', clock_timestamp() - interval '1 minute', gen_random_uuid()) $$,
  'P0001', 'close_at_invalid', 'เวลาปิดใหม่ต้องอยู่ในอนาคต');
select throws_ok($$ select public.reopen_assignment('8a100000-0000-4000-8000-000000000002', '2026-09-30T13:00:00Z', gen_random_uuid()) $$,
  'P0001', 'close_at_invalid', 'เวลาปิดใหม่ในอดีต (ก่อนกำหนดส่งด้วย) ถูกปฏิเสธ');
select is(public.reopen_assignment('8a100000-0000-4000-8000-000000000002', '2099-01-01T13:00:00Z', gen_random_uuid()) -> 'close_at',
  '"2099-01-01T13:00:00+00:00"', 'เปิดอีกครั้งพร้อมตั้งเวลาปิดใหม่');
select pg_temp.as_user('2a100000-0000-4000-8000-000000000011');
select is(public.submission_status('8a100000-0000-4000-8000-000000000002') -> 'outcome', '"first_late"',
  'เปิดอีกครั้งหลังกำหนด: ส่งครั้งแรกได้แบบสาย (แถว 3)');

-- ยกเลิกเวลาปิดที่ตั้งไว้ขณะยังเปิดรับ / ค่าเท่าเดิมไม่เปลี่ยน
select pg_temp.as_user('2a100000-0000-4000-8000-000000000001');
select is(public.reopen_assignment('8a100000-0000-4000-8000-000000000002', null, gen_random_uuid()) -> 'close_at', 'null'::jsonb,
  'ยกเลิกเวลาปิดที่ตั้งไว้ (รับสายจนกว่าครูปิด)');
select is(public.reopen_assignment('8a100000-0000-4000-8000-000000000002', null, gen_random_uuid()) -> 'changed', 'false'::jsonb,
  'เปิดอยู่แล้วค่าเท่าเดิม: ไม่เปลี่ยนอะไร');

-- ---------------------------------------------------------------------------
-- ข: หลังเผยแพร่เฉลยเปิดอีกไม่ได้
-- ---------------------------------------------------------------------------
select is(public.close_assignment('8a100000-0000-4000-8000-000000000003', null, gen_random_uuid()) -> 'intake', '"closed"', 'H3 ปิดรับ');
select is(public.save_solution('8a100000-0000-4000-8000-000000000003', 'เฉลย', null, 0, gen_random_uuid()) -> 'version', '1'::jsonb, 'บันทึกเฉลย');
select is(public.publish_solution('8a100000-0000-4000-8000-000000000003', 1, gen_random_uuid()) -> 'intake', '"after_solution"', 'เผยแพร่เฉลย');
select throws_ok($$ select public.reopen_assignment('8a100000-0000-4000-8000-000000000003', null, gen_random_uuid()) $$,
  'P0001', 'solution_published', 'เผยแพร่เฉลยแล้ว: เปิดรับอีกครั้งไม่ได้');
set local role postgres;
select throws_ok($$ update public.assignments set closed_at = null where post_id = '8a100000-0000-4000-8000-000000000003' $$,
  'P0001', 'immutable_field', 'ตัวกันระดับตาราง: หลังเผยแพร่เฉลยล้าง closed_at ไม่ได้');
set local role authenticated;

-- สิทธิ์
select pg_temp.as_user('2a100000-0000-4000-8000-000000000002');
select throws_ok($$ select public.reopen_assignment('8a100000-0000-4000-8000-000000000001', null, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นเปิดรับไม่ได้');

select * from finish();
rollback;
