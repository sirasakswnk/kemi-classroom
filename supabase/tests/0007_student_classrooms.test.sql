-- ทดสอบ 0007_student_classrooms: ห้องของฉัน (S01/S06) และหัวห้อง + สมาชิก (S02) ฝั่งนักเรียน
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 4440000x, อีเมล @example.com) และ rollback ตอนจบ
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

select is_empty(
  $$ select f from unnest(array['public.my_classrooms()', 'public.classroom_view(uuid)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon ไม่มี EXECUTE บน my_classrooms/classroom_view');
select ok(
  has_function_privilege('authenticated', 'public.my_classrooms()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.classroom_view(uuid)', 'EXECUTE'),
  'authenticated เรียกได้ (ตรวจนักเรียน/สมาชิกภายใน)');

-- ข้อมูลสมมติ: ภาคเรียนปัจจุบัน + ภาคเก่า, ครู, นักเรียน 3 คน (สมาชิก 2), บัญชียังไม่ผูก
insert into public.terms (id, name, status) values
  ('47000000-0000-4000-8000-000000000001', 'ภาคทดสอบปัจจุบัน', 'active'),
  ('47000000-0000-4000-8000-000000000002', 'ภาคทดสอบเก่า', 'superseded');
insert into public.term_control (term_id) values ('47000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';
insert into public.teachers (id, display_name) values ('17000000-0000-4000-8000-000000000001', 'ครูทดสอบห้องนักเรียน');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('37000000-0000-4000-8000-000000000001', '27000000-0000-4000-8000-000000000001', 'google', 'sc-1', 'teacher7@example.com', 'teacher', '17000000-0000-4000-8000-000000000001'),
  ('37000000-0000-4000-8000-000000000002', '27000000-0000-4000-8000-000000000002', 'google', 'sc-2', 'one7@example.com', 'student', null),
  ('37000000-0000-4000-8000-000000000003', '27000000-0000-4000-8000-000000000003', 'google', 'sc-3', 'two7@example.com', 'student', null),
  ('37000000-0000-4000-8000-000000000004', '27000000-0000-4000-8000-000000000004', 'google', 'sc-4', 'three7@example.com', 'student', null),
  ('37000000-0000-4000-8000-000000000005', '27000000-0000-4000-8000-000000000005', 'google', 'sc-5', 'unbound7@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('67000000-0000-4000-8000-000000000001', '44400001', 'หนึ่ง ห้องนักเรียน', '37000000-0000-4000-8000-000000000002'),
  ('67000000-0000-4000-8000-000000000002', '44400002', 'สอง ห้องนักเรียน', '37000000-0000-4000-8000-000000000003'),
  ('67000000-0000-4000-8000-000000000003', '44400003', 'สาม ไม่อยู่ห้อง', '37000000-0000-4000-8000-000000000004');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('47000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000001', 'ม.5/1', 7),
  ('47000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000002', 'ม.5/2', 3);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('77000000-0000-4000-8000-000000000001', '47000000-0000-4000-8000-000000000001', '17000000-0000-4000-8000-000000000001', 'เคมีทดสอบ ม.5/1', 'QQQQ27'),
  ('77000000-0000-4000-8000-000000000002', '47000000-0000-4000-8000-000000000002', '17000000-0000-4000-8000-000000000001', 'เคมีภาคเก่า', 'QQQQ28');
insert into public.memberships (classroom_id, student_id) values
  ('77000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000001'),
  ('77000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000002'),
  ('77000000-0000-4000-8000-000000000002', '67000000-0000-4000-8000-000000000001');

set local role anon;
select throws_ok($$ select public.my_classrooms() $$, '42501', null, 'anon เรียก my_classrooms ไม่ได้');

-- ห้องของฉัน
set local role authenticated;
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is(
  (select jsonb_agg(x - 'id' - 'joined_at') from jsonb_array_elements(public.my_classrooms()) x),
  '[{"name": "เคมีทดสอบ ม.5/1", "description": null, "teacher_name": "ครูทดสอบห้องนักเรียน", "member_count": 2}]'::jsonb,
  'ห้องของฉัน: เฉพาะภาคเรียนปัจจุบัน พร้อมชื่อครูและจำนวนสมาชิก');
select is(
  (select array_agg(k order by k) from jsonb_array_elements(public.my_classrooms()) x, jsonb_object_keys(x) k),
  array['description', 'id', 'joined_at', 'member_count', 'name', 'teacher_name'],
  'ห้องของฉัน: ไม่มีรหัสห้องหรือข้อมูลอื่นเกิน');
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.my_classrooms(), '[]'::jsonb, 'ยังไม่ผูกชื่อ: ไม่มีห้อง');
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.my_classrooms() $$, 'P0001', 'forbidden', 'ครูเรียก my_classrooms ไม่ได้');
select throws_ok($$ select public.classroom_view('77000000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden',
  'ครูเรียก classroom_view ไม่ได้ (ใช้หน้าครู)');

-- หัวห้อง + สมาชิก
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is(public.classroom_view('77000000-0000-4000-8000-000000000001') - 'id',
  '{"name": "เคมีทดสอบ ม.5/1", "description": null, "teacher_name": "ครูทดสอบห้องนักเรียน",
    "term_name": "ภาคทดสอบปัจจุบัน", "member_count": 2,
    "members": [{"display_name": "สอง ห้องนักเรียน", "roll_number": 3, "is_me": false},
                {"display_name": "หนึ่ง ห้องนักเรียน", "roll_number": 7, "is_me": true}]}'::jsonb,
  'สมาชิกเห็นชื่อและเลขที่ของเพื่อน เรียงตามเลขที่ บอกว่าแถวไหนคือตัวเอง');
select ok(
  (select public.classroom_view('77000000-0000-4000-8000-000000000001')::text !~ '4440000|@example\.com|ม\.5/2|QQQQ27'),
  'ไม่มีเลขประจำตัว อีเมล ห้องตามรายชื่อของคนอื่น หรือรหัสห้อง');
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.classroom_view('77000000-0000-4000-8000-000000000001') $$, 'P0001', 'not_member',
  'คนนอกห้องเปิดหัวห้องไม่ได้');
select throws_ok($$ select public.classroom_view('77000000-0000-4000-8000-000000000099') $$, 'P0001', 'not_member',
  'ห้องที่ไม่มีอยู่ได้ not_member (ไม่บอกว่ามีห้องนี้หรือไม่)');

-- เอาออกแล้วเข้าใหม่
set local role postgres;
delete from public.memberships
 where classroom_id = '77000000-0000-4000-8000-000000000001' and student_id = '67000000-0000-4000-8000-000000000002';
set local role authenticated;
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.classroom_view('77000000-0000-4000-8000-000000000001') $$, 'P0001', 'not_member',
  'ถูกเอาออกแล้วเปิดหัวห้องไม่ได้ทันที');
select is(public.my_classrooms(), '[]'::jsonb, 'ถูกเอาออกแล้วห้องหายจากห้องของฉัน');
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((public.classroom_view('77000000-0000-4000-8000-000000000001') ->> 'member_count')::integer, 1,
  'เพื่อนที่ยังอยู่เห็นจำนวนสมาชิกลดลง');
set local role postgres;
insert into public.memberships (classroom_id, student_id)
values ('77000000-0000-4000-8000-000000000001', '67000000-0000-4000-8000-000000000002');
set local role authenticated;
set local request.jwt.claims to '{"sub": "27000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.classroom_view('77000000-0000-4000-8000-000000000001') #>> '{members,0,is_me}', 'true',
  'เข้าใหม่แล้วเปิดหัวห้องได้อีก');
select is(jsonb_array_length(public.my_classrooms()), 1, 'เข้าใหม่แล้วห้องกลับมาในห้องของฉัน');

set local role postgres;
select * from finish();
rollback;
