-- ทดสอบ 0006_teachers_read: ครู/ผู้ดูแลอ่านรายชื่อครูได้ นักเรียนและ anon อ่านไม่ได้ — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(6);

select policies_are('public', 'teachers', array['teachers_select'], 'teachers มีเฉพาะ policy อ่าน');
select ok(not has_table_privilege('authenticated', 'public.teachers', 'INSERT, UPDATE, DELETE'),
  'authenticated เขียนตาราง teachers ไม่ได้');

insert into public.teachers (id, display_name) values ('13000000-0000-4000-8000-000000000001', 'ครูอ่านชื่อ (ทดสอบ)');
insert into public.accounts (id, auth_user_id, provider, provider_subject, role, teacher_id) values
  ('33000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', 'google', 't-id-1', 'teacher', '13000000-0000-4000-8000-000000000001'),
  ('33000000-0000-4000-8000-000000000002', '23000000-0000-4000-8000-000000000002', 'google', 't-id-2', 'admin', null),
  ('33000000-0000-4000-8000-000000000003', '23000000-0000-4000-8000-000000000003', 'google', 't-id-3', 'student', null);

set local role authenticated;
set local request.jwt.claims to '{"sub": "23000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select ok((select count(*) from public.teachers t where t.id = '13000000-0000-4000-8000-000000000001') = 1, 'ครูอ่านชื่อครูได้');
set local request.jwt.claims to '{"sub": "23000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select ok((select count(*) from public.teachers t where t.id = '13000000-0000-4000-8000-000000000001') = 1,
  'ผู้ดูแลอ่านรายชื่อครูได้ (เลือกครูเจ้าของห้อง)');
set local request.jwt.claims to '{"sub": "23000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is((select count(*) from public.teachers), 0::bigint, 'นักเรียนอ่านตาราง teachers ไม่ได้');
set local role anon;
select throws_ok('select * from public.teachers', '42501', null, 'anon อ่านตาราง teachers ไม่ได้');

set local role postgres;
select * from finish();
rollback;
