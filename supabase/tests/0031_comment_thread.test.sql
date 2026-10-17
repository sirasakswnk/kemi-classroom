-- ทดสอบ 0031_comment_thread: อ่านช่องความคิดเห็นพร้อมชื่อผู้ส่ง/ของฉัน/สิทธิ์เขียน — นักเรียนเจ้าของ (รวมถูกเอาออก),
-- ครูเจ้าของห้อง, ผู้ดูแล, จบภาคเรียน — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(14);

-- ครู 1 ห้อง 1, ครู 2, ผู้ดูแล; N1 สมาชิก (บัญชี), N2 ถูกเอาออกแต่มีงานส่ง (บัญชี), N3 ไม่อยู่ห้อง
insert into public.terms (id, name, status) values ('4e100000-0000-4000-8000-000000000001', 'ภาคทดสอบเธรด', 'active');
insert into public.term_control (term_id) values ('4e100000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e100000-0000-4000-8000-000000000001', 'ครูเธรดหนึ่ง'), ('1e100000-0000-4000-8000-000000000002', 'ครูเธรดสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e100000-0000-4000-8000-000000000001', '2e100000-0000-4000-8000-000000000001', 'google', 'th-1', 't31a@example.com', 'teacher', '1e100000-0000-4000-8000-000000000001'),
  ('3e100000-0000-4000-8000-000000000002', '2e100000-0000-4000-8000-000000000002', 'google', 'th-2', 't31b@example.com', 'teacher', '1e100000-0000-4000-8000-000000000002'),
  ('3e100000-0000-4000-8000-000000000003', '2e100000-0000-4000-8000-000000000003', 'google', 'th-3', 'a31@example.com', 'admin', null),
  ('3e100000-0000-4000-8000-000000000011', '2e100000-0000-4000-8000-000000000011', 'google', 'th-11', 's31a@example.com', 'student', null),
  ('3e100000-0000-4000-8000-000000000012', '2e100000-0000-4000-8000-000000000012', 'google', 'th-12', 's31b@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e100000-0000-4000-8000-000000000001', '931000000000311', 'หนึ่ง เธรด', '3e100000-0000-4000-8000-000000000011'),
  ('6e100000-0000-4000-8000-000000000002', '931000000000312', 'สอง เธรด', '3e100000-0000-4000-8000-000000000012'),
  ('6e100000-0000-4000-8000-000000000003', '931000000000313', 'สาม เธรด', null);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e100000-0000-4000-8000-000000000001', '4e100000-0000-4000-8000-000000000001', '1e100000-0000-4000-8000-000000000001', 'เคมีเธรด 1', 'ZZZZ84');
insert into public.memberships (classroom_id, student_id) values
  ('7e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8e100000-0000-4000-8000-000000000001', '7e100000-0000-4000-8000-000000000001', 'homework', 'งานเธรด', '2026-09-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values ('8e100000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5e100000-0000-4000-8000-000000000002', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000002', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z');
insert into public.comments (id, assignment_id, student_id, author_account_id, body, created_at, retracted_at) values
  ('c3100000-0000-4000-8000-000000000001', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000011', 'ถามครูค่ะ', '2026-10-01T01:00:00Z', null),
  ('c3100000-0000-4000-8000-000000000002', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001', 'ครูตอบ', '2026-10-01T02:00:00Z', null),
  ('c3100000-0000-4000-8000-000000000003', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000011', null, '2026-10-01T03:00:00Z', '2026-10-01T04:00:00Z'),
  ('c3100000-0000-4000-8000-000000000004', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000003', 'ผู้ดูแลแทนครู', '2026-10-01T05:00:00Z', null),
  ('c3100000-0000-4000-8000-000000000005', '8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000002', '3e100000-0000-4000-8000-000000000001', 'ถึงสอง', '2026-10-01T06:00:00Z', null);

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.brief(p jsonb) returns jsonb language sql immutable as
  $$ select coalesce(jsonb_agg(jsonb_build_array(e -> 'author_role', e -> 'author_name', e -> 'mine', e -> 'body')), '[]')
       from jsonb_array_elements(p -> 'comments') e $$;
grant execute on function pg_temp.brief(jsonb) to authenticated;

set local role authenticated;

-- นักเรียน N1 (สมาชิก)
select pg_temp.as_user('2e100000-0000-4000-8000-000000000011');
select is(pg_temp.brief(public.comment_thread('8e100000-0000-4000-8000-000000000001')),
  '[["student", "หนึ่ง เธรด", true, "ถามครูค่ะ"], ["teacher", "ครูเธรดหนึ่ง", false, "ครูตอบ"], ["student", "หนึ่ง เธรด", true, null], ["admin", null, false, "ผู้ดูแลแทนครู"]]'::jsonb,
  'นักเรียนเห็นช่องตัวเอง เรียงเวลา พร้อมชื่อผู้ส่ง (ครู = ชื่อครู, ผู้ดูแล = null) ข้อความที่ยกเลิกไม่มีเนื้อความ');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001') -> 'can_write', 'true'::jsonb, 'สมาชิก + ภาคเรียนเปิด: เขียนได้');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001') -> 'student_id',
  '"6e100000-0000-4000-8000-000000000001"', 'ส่ง student_id ของตัวเองได้');
select throws_ok($$ select public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000002') $$,
  'P0001', 'forbidden', 'อ่านช่องของเพื่อนไม่ได้');
select throws_ok($$ select public.comment_thread('8e100000-0000-4000-8000-0000000000ff') $$,
  'P0001', 'forbidden', 'งานที่ไม่มี → forbidden');

-- N2 ถูกเอาออกแล้ว: อ่านได้ เขียนไม่ได้
select pg_temp.as_user('2e100000-0000-4000-8000-000000000012');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001') - 'assignment_id' - 'student_id',
  '{"can_write": false, "comments": [{"comment_id": "c3100000-0000-4000-8000-000000000005", "author_role": "teacher", "author_name": "ครูเธรดหนึ่ง", "mine": false, "body": "ถึงสอง", "created_at": "2026-10-01T06:00:00+00:00", "retracted_at": null}]}'::jsonb,
  'ถูกเอาออก: ยังอ่านช่องตัวเองได้ แต่ can_write = false');

-- ครูเจ้าของห้อง
select pg_temp.as_user('2e100000-0000-4000-8000-000000000001');
select is(jsonb_array_length(public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001') -> 'comments'), 4,
  'ครูอ่านช่องของนักเรียนคนนั้น');
select is((select jsonb_agg(e -> 'mine') from jsonb_array_elements(public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001') -> 'comments') e),
  '[false, true, false, false]'::jsonb, 'mine นับจากบัญชีผู้เรียก');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000002') -> 'can_write', 'true'::jsonb,
  'ครูเขียนถึงคนที่ถูกเอาออกแต่มีงานส่งได้');
select throws_ok($$ select public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000003') $$,
  'P0001', 'student_not_found', 'นักเรียนที่ไม่อยู่ในรายชื่อของงาน → student_not_found');
select throws_ok($$ select public.comment_thread('8e100000-0000-4000-8000-000000000001') $$,
  'P0001', 'student_not_found', 'ครูต้องระบุนักเรียน');

select pg_temp.as_user('2e100000-0000-4000-8000-000000000002');
select throws_ok($$ select public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001') $$,
  'P0001', 'forbidden', 'ครูห้องอื่นอ่านไม่ได้');

-- จบภาคเรียน: นักเรียนเขียนไม่ได้ ผู้ดูแลอ่านได้โดยไม่ต้องโหมดผู้ดูแล
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select pg_temp.as_user('2e100000-0000-4000-8000-000000000011');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001') -> 'can_write', 'false'::jsonb, 'K5: จบภาคเรียนแล้วนักเรียนเขียนไม่ได้');
select pg_temp.as_user('2e100000-0000-4000-8000-000000000003');
select is(public.comment_thread('8e100000-0000-4000-8000-000000000001', '6e100000-0000-4000-8000-000000000001') -> 'can_write', 'true'::jsonb,
  'ผู้ดูแลอ่านได้ (การเขียนตรวจโหมดผู้ดูแลที่ post_comment)');

select * from finish();
rollback;
