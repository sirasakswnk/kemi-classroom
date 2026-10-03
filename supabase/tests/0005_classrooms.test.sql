-- ทดสอบ 0005_classrooms: สร้างห้อง/รหัส, RLS ตาม membership, lookup/join, ปิด-เปิดการเข้าห้อง,
-- เพดานรหัสผิด, เอานักเรียนออกแล้วเข้าใหม่ — ข้อมูลสมมติทั้งหมด (เลขประจำตัว 5550000x) และ rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

-- ให้เรียก pgTAP ได้ขณะสลับเป็น anon/authenticated (ย้อนเมื่อ rollback)
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

select plan(72);

-- ---------------------------------------------------------------------------
-- A. โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('public', 'classrooms', 'มี public.classrooms');
select has_table('public', 'memberships', 'มี public.memberships');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.classrooms'::regclass, 'public.memberships'::regclass)),
  'classrooms และ memberships เปิด RLS');
select policies_are('public', 'classrooms', array['classrooms_select'], 'classrooms มีเฉพาะ policy อ่าน');
select policies_are('public', 'memberships', array['memberships_select'], 'memberships มีเฉพาะ policy อ่าน');
select is_empty(
  $$ select f from unnest(array[
       'public.create_classroom(text,text,uuid,uuid,boolean)', 'public.set_join_enabled(uuid,boolean,boolean)',
       'public.remove_member(uuid,uuid,boolean)', 'public.lookup_classroom(text)', 'public.join_classroom(text)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon เรียก RPC ของห้องไม่ได้');
select ok(
  (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE')) from unnest(array[
     'public.create_classroom(text,text,uuid,uuid,boolean)', 'public.set_join_enabled(uuid,boolean,boolean)',
     'public.remove_member(uuid,uuid,boolean)', 'public.lookup_classroom(text)', 'public.join_classroom(text)']) f),
  'authenticated เรียก RPC ของห้องได้ (ตรวจสิทธิ์ภายใน)');
select is_empty(
  $$ select f from unnest(array[
       'private.new_join_code()', 'private.normalize_join_code(text)',
       'private.rate_limit_check(uuid,text,integer,interval)', 'private.require_classroom_teacher(uuid,boolean)',
       'private.require_bound_student()', 'private.require_member(uuid)', 'private.classroom_card(uuid)',
       'private.find_classroom_for_join(text,uuid,uuid,boolean)']) f
      where has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'authenticated เรียกฟังก์ชันช่วยภายในไม่ได้');
select is((select count(*) from pg_constraint c where c.confrelid = 'public.memberships'::regclass), 0::bigint,
  'ไม่มีตารางใดอ้าง memberships: เอานักเรียนออกแล้วข้อมูลอื่นไม่ถูกลบตาม');
select ok(
  not has_table_privilege('authenticated', 'public.classrooms', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('authenticated', 'public.memberships', 'INSERT, UPDATE, DELETE'),
  'authenticated เขียนตารางห้อง/สมาชิกตรงไม่ได้');

-- ---------------------------------------------------------------------------
-- B. รหัสห้อง
-- ---------------------------------------------------------------------------
select is((select count(*) from generate_series(1, 300) g where private.new_join_code() !~ '^[A-HJKMNP-Z2-9]{6}$'),
  0::bigint, 'รหัส 6 ตัวจาก A–Z และ 2–9 ไม่มี I L O 0 1');
select ok((select count(distinct c) from (select private.new_join_code() c from generate_series(1, 300)) x) >= 299,
  'รหัสสุ่มไม่ซ้ำกันในทางปฏิบัติ');
select is((select count(distinct ch) from (select regexp_split_to_table(private.new_join_code(), '') ch
                                             from generate_series(1, 2000)) x), 31::bigint,
  'ใช้ครบทั้ง 31 ตัวอักษร');
select ok(
  (select p.prosrc ~ 'extensions\.gen_random_bytes' and p.prosrc !~* '\mrandom\s*\('
     from pg_proc p where p.oid = 'private.new_join_code()'::regprocedure),
  'สุ่มด้วย extensions.gen_random_bytes ไม่ใช้ random()');
select is(private.normalize_join_code(E' k7m-2qx\t'), 'K7M2QX', 'รหัสไม่สนตัวพิมพ์เล็กใหญ่ ตัดช่องว่างและขีด');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name) values ('42000000-0000-4000-8000-000000000001', 'ภาคเรียนทดสอบห้อง');
insert into public.term_control (term_id) values ('42000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';

insert into public.teachers (id, display_name) values
  ('12000000-0000-4000-8000-000000000001', 'ครูหนึ่ง (ทดสอบ)'),
  ('12000000-0000-4000-8000-000000000002', 'ครูสอง (ทดสอบ)');
-- 1, 2 ครู · 3 ผู้ดูแล · 4 นักเรียนยังไม่ผูกชื่อ · 5, 6, 7, 8 นักเรียนที่ผูกแล้ว
insert into public.accounts (id, auth_user_id, provider, provider_subject, role, teacher_id) values
  ('32000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'google', 'c-id-1', 'teacher', '12000000-0000-4000-8000-000000000001'),
  ('32000000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000002', 'google', 'c-id-2', 'teacher', '12000000-0000-4000-8000-000000000002'),
  ('32000000-0000-4000-8000-000000000003', '22000000-0000-4000-8000-000000000003', 'google', 'c-id-3', 'admin', null),
  ('32000000-0000-4000-8000-000000000004', '22000000-0000-4000-8000-000000000004', 'google', 'c-id-4', 'student', null),
  ('32000000-0000-4000-8000-000000000005', '22000000-0000-4000-8000-000000000005', 'google', 'c-id-5', 'student', null),
  ('32000000-0000-4000-8000-000000000006', '22000000-0000-4000-8000-000000000006', 'google', 'c-id-6', 'student', null),
  ('32000000-0000-4000-8000-000000000007', '22000000-0000-4000-8000-000000000007', 'google', 'c-id-7', 'student', null),
  ('32000000-0000-4000-8000-000000000008', '22000000-0000-4000-8000-000000000008', 'google', 'c-id-8', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('62000000-0000-4000-8000-000000000001', '55500001', 'หนึ่ง ทดสอบห้อง', '32000000-0000-4000-8000-000000000005'),
  ('62000000-0000-4000-8000-000000000002', '55500002', 'สอง ทดสอบห้อง', '32000000-0000-4000-8000-000000000006'),
  ('62000000-0000-4000-8000-000000000003', '55500003', 'สาม ทดสอบห้อง', '32000000-0000-4000-8000-000000000007'),
  ('62000000-0000-4000-8000-000000000004', '55500004', 'สี่ ทดสอบห้อง', '32000000-0000-4000-8000-000000000008');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('42000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', 'ม.5/2', 1);

create temp table res (label text primary key, body jsonb not null);
grant select, insert on res to authenticated;

-- ---------------------------------------------------------------------------
-- C. สร้างห้อง
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select public.create_classroom('ห้อง', null, gen_random_uuid()) $$, '42501', null, 'anon สร้างห้องไม่ได้');
set local role authenticated;
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select throws_ok($$ select public.create_classroom('ห้อง', null, gen_random_uuid()) $$, 'P0001', 'forbidden', 'นักเรียนสร้างห้องไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.create_classroom('ห้อง', null, gen_random_uuid()) $$, 'P0001', 'admin_mode_required',
  'ผู้ดูแลนอกโหมดผู้ดูแลสร้างห้องไม่ได้');
select throws_ok($$ select public.create_classroom('ห้อง', null, gen_random_uuid(), null, true) $$, 'P0001', 'teacher_required',
  'ผู้ดูแลในโหมดผู้ดูแลต้องระบุครูเจ้าของห้อง');
insert into res values ('b', public.create_classroom('เคมี ม.5/9 (ผู้ดูแลสร้าง)', null,
  '52000000-0000-4000-8000-000000000009', '12000000-0000-4000-8000-000000000002', true));

set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('a', public.create_classroom(' เคมี ม.5/1 ', 'ห้องทดสอบ', '52000000-0000-4000-8000-000000000001'));
select ok(
  (select body ->> 'join_code' ~ '^[A-HJKMNP-Z2-9]{6}$' and body ->> 'name' = 'เคมี ม.5/1'
          and (body ->> 'join_enabled')::boolean and body #>> '{term,name}' = 'ภาคเรียนทดสอบห้อง'
     from res where label = 'a'),
  'ครูสร้างห้องในภาคเรียนปัจจุบัน ได้รหัส 6 ตัวและเปิดรับสมาชิก');
select is(public.create_classroom(' เคมี ม.5/1 ', 'ห้องทดสอบ', '52000000-0000-4000-8000-000000000001'),
  (select body from res where label = 'a'), 'ส่งซ้ำด้วย request key เดิมได้ผลเดิม');
select throws_ok($$ select public.create_classroom('ชื่ออื่น', null, '52000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่เนื้อหาต่างถูกปฏิเสธ');
select throws_ok($$ select public.create_classroom('   ', null, gen_random_uuid()) $$, 'P0001', 'name_invalid',
  'ชื่อห้องว่างถูกปฏิเสธ');

set local role postgres;
select results_eq(
  $$ select c.name, c.teacher_id::text from public.classrooms c
      where c.teacher_id in ('12000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000002')
      order by c.name $$,
  $$ values ('เคมี ม.5/1', '12000000-0000-4000-8000-000000000001'),
            ('เคมี ม.5/9 (ผู้ดูแลสร้าง)', '12000000-0000-4000-8000-000000000002') $$,
  'ห้องที่ผู้ดูแลสร้างเป็นของครูที่ระบุ และส่งซ้ำไม่เกิดห้องซ้ำ');

-- ---------------------------------------------------------------------------
-- D. RLS: ครูเห็นห้องตัวเอง คนนอกห้องอ่านไม่ได้
-- ---------------------------------------------------------------------------
create temp view test_rooms as select (body ->> 'classroom_id')::uuid as id from res where label in ('a', 'b');
grant select on test_rooms to authenticated;
set local role authenticated;
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select results_eq($$ select c.name from public.classrooms c where c.id in (select id from test_rooms) $$,
  $$ values ('เคมี ม.5/1') $$, 'ครูเห็นเฉพาะห้องของตัวเอง');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select results_eq($$ select c.name from public.classrooms c where c.id in (select id from test_rooms) $$,
  $$ values ('เคมี ม.5/9 (ผู้ดูแลสร้าง)') $$, 'ครูอีกคนไม่เห็นห้องที่ไม่ใช่ของตัวเอง');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is((select count(*) from public.classrooms c where c.id in (select id from test_rooms)), 2::bigint, 'ผู้ดูแลเห็นทุกห้อง');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is((select count(*) from public.classrooms c where c.id in (select id from test_rooms)), 0::bigint,
  'นักเรียนนอกห้องอ่านห้องไม่ได้');

-- ---------------------------------------------------------------------------
-- E. lookup / join
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) $$,
  'P0001', 'identity_required', 'ยังไม่ผูกชื่อหาห้องไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.join_classroom((select body ->> 'join_code' from res where label = 'a')) $$,
  'P0001', 'forbidden', 'ครูเข้าห้องแบบนักเรียนไม่ได้');

set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.lookup_classroom((select ' ' || lower(body ->> 'join_code') || ' ' from res where label = 'a')) #- '{classroom,id}',
  '{"status": "found", "classroom": {"name": "เคมี ม.5/1", "teacher_name": "ครูหนึ่ง (ทดสอบ)", "member_count": 0}}'::jsonb,
  'หาห้องด้วยรหัสตัวพิมพ์เล็ก: คืนชื่อห้อง ชื่อครู จำนวนสมาชิก (ไม่มีรหัส)');
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) #>> '{status}', 'joined',
  'นักเรียนที่ผูกชื่อแล้วเข้าห้องได้');
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) #- '{classroom,id}',
  '{"status": "member", "classroom": {"name": "เคมี ม.5/1", "teacher_name": "ครูหนึ่ง (ทดสอบ)", "member_count": 1}}'::jsonb,
  'กดเข้าซ้ำได้ผลเดิม (อยู่ในห้องแล้ว)');
select results_eq($$ select c.name from public.classrooms c where c.id in (select id from test_rooms) $$,
  $$ values ('เคมี ม.5/1') $$, 'สมาชิกอ่านห้องของตัวเองได้');
select is(public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'member',
  'หาห้องที่อยู่แล้วบอกว่าอยู่ในห้องนี้แล้ว');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'joined',
  'ใครมีรหัสก็เข้าได้ (ไม่ตรวจห้องตามรายชื่อ)');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is((select count(*) from public.memberships m where m.classroom_id in (select id from test_rooms)), 1::bigint,
  'นักเรียนเห็นเฉพาะ membership ของตัวเอง');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is((select count(*) from public.memberships m where m.classroom_id in (select id from test_rooms)), 2::bigint,
  'ครูเจ้าของห้องเห็นสมาชิกทั้งหมด');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((select count(*) from public.memberships m where m.classroom_id in (select id from test_rooms)), 0::bigint,
  'ครูอีกคนไม่เห็นสมาชิกของห้องที่ไม่ใช่ของตัวเอง');

set local role postgres;
select is((select count(*) from public.memberships m
            where m.student_id = '62000000-0000-4000-8000-000000000001'), 1::bigint, 'เข้าซ้ำไม่เกิดสมาชิกซ้ำ');

-- ---------------------------------------------------------------------------
-- F. ปิด/เปิดการเข้าห้อง
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.set_join_enabled((select id from test_rooms limit 0) , false) $$, 'P0001', 'forbidden',
  'ปิดห้องที่ไม่มีอยู่ไม่ได้');
select throws_ok($$ select public.set_join_enabled((select (body ->> 'classroom_id')::uuid from res where label = 'a'), false) $$,
  'P0001', 'forbidden', 'ครูอีกคนปิดการเข้าห้องที่ไม่ใช่ของตัวเองไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.set_join_enabled((select (body ->> 'classroom_id')::uuid from res where label = 'a'), false) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลปิดการเข้าห้องไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.set_join_enabled((select (body ->> 'classroom_id')::uuid from res where label = 'a'), false)
            - 'classroom_id',
  jsonb_build_object('join_enabled', false, 'join_code', (select body ->> 'join_code' from res where label = 'a')),
  'ครูปิดการเข้าห้อง');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is(
  array[public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')),
        public.join_classroom((select body ->> 'join_code' from res where label = 'a'))],
  array['{"status": "closed"}'::jsonb, '{"status": "closed"}'::jsonb],
  'ห้องปิด: หาและเข้าไม่ได้ (ไม่บอกชื่อห้อง)');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select ok(
  public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status' = 'member'
  and (select count(*) from public.classrooms c where c.id in (select id from test_rooms)) = 1,
  'ห้องปิด: สมาชิกเดิมยังอยู่และอ่านห้องได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.set_join_enabled((select (body ->> 'classroom_id')::uuid from res where label = 'a'), true) ->> 'join_code',
  (select body ->> 'join_code' from res where label = 'a'), 'เปิดการเข้าห้องอีกครั้งใช้รหัสเดิม');
select is(public.set_join_enabled((select (body ->> 'classroom_id')::uuid from res where label = 'a'), true) ->> 'join_enabled',
  'true', 'เปิดซ้ำได้ผลเดิม');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'joined',
  'เปิดแล้วเข้าได้ด้วยรหัสเดิม');

-- ---------------------------------------------------------------------------
-- G. เพดานใส่รหัสผิด (บัญชี 8): 10 ครั้งต่อ 10 นาที ใช้ตัวนับร่วม lookup/join
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000008", "role": "authenticated"}';
select is((select count(*) from generate_series(1, 3) g
            where public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status' = 'found'),
  3::bigint, 'หารหัสที่ถูกหลายครั้งได้');
set local role postgres;
select is((select count(*) from private.rate_limits r where r.account_id = '32000000-0000-4000-8000-000000000008'),
  0::bigint, 'รหัสที่ถูกไม่นับเป็นครั้งที่ผิด');
set local role authenticated;
select is(
  (select array_agg((public.lookup_classroom('ZZZZZ' || g) ->> 'remaining')::integer order by g) from generate_series(2, 6) g),
  array[9, 8, 7, 6, 5], 'หารหัสผิด: นับและบอกจำนวนครั้งที่เหลือ');
select is(
  (select array_agg((public.join_classroom(g) ->> 'remaining')::integer order by g)
     from unnest(array['QQQQQ2', 'qqqqq3', '', 'I0L1O0', 'TOOLONGCODE']) g),
  array[4, 3, 2, 1, 0], 'เข้าด้วยรหัสผิด (รวมรูปแบบผิด) ใช้ตัวนับเดียวกัน');
select throws_ok($$ select public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) $$,
  'P0001', 'rate_limited', 'ครบเพดานแล้วหาไม่ได้แม้รหัสถูก');
select throws_ok($$ select public.join_classroom((select body ->> 'join_code' from res where label = 'a')) $$,
  'P0001', 'rate_limited', 'ครบเพดานแล้วเข้าไม่ได้แม้รหัสถูก');
set local role postgres;
update private.rate_limits r set window_start = r.window_start - interval '10 minutes'
 where r.account_id = '32000000-0000-4000-8000-000000000008';
set local role authenticated;
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'joined',
  'พ้น 10 นาทีแล้วเข้าได้');

-- ---------------------------------------------------------------------------
-- H. เอานักเรียนออก แล้วเข้าใหม่
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.remove_member((select (body ->> 'classroom_id')::uuid from res where label = 'a'),
                                                '62000000-0000-4000-8000-000000000001') $$,
  'P0001', 'forbidden', 'ครูอีกคนเอานักเรียนออกจากห้องที่ไม่ใช่ของตัวเองไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select throws_ok($$ select public.remove_member((select (body ->> 'classroom_id')::uuid from res where label = 'a'),
                                                '62000000-0000-4000-8000-000000000001') $$,
  'P0001', 'forbidden', 'นักเรียนเอาคนอื่นออกไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.remove_member((select (body ->> 'classroom_id')::uuid from res where label = 'a'),
                               '62000000-0000-4000-8000-000000000001') ->> 'removed', 'true', 'ครูเอานักเรียนออก');
select is(public.remove_member((select (body ->> 'classroom_id')::uuid from res where label = 'a'),
                               '62000000-0000-4000-8000-000000000001') ->> 'removed', 'false', 'เอาออกซ้ำได้ผลเดิม');

set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is((select count(*) from public.classrooms c where c.id in (select id from test_rooms)), 0::bigint,
  'เอาออกแล้วอ่านห้องไม่ได้ทันที');
select is((select count(*) from public.memberships m where m.classroom_id in (select id from test_rooms)), 0::bigint,
  'เอาออกแล้วไม่เห็น membership ของห้องนั้น');
set local role postgres;
select throws_ok($$ select private.require_member((select (body ->> 'classroom_id')::uuid from res where label = 'a')) $$,
  'P0001', 'not_member', 'RPC ของห้องปฏิเสธด้วย not_member หลังถูกเอาออก');
select ok(
  (select s.account_id = '32000000-0000-4000-8000-000000000005' from public.students s
    where s.id = '62000000-0000-4000-8000-000000000001')
  and (select count(*) from public.roster_entries e where e.student_id = '62000000-0000-4000-8000-000000000001') = 1,
  'เอาออกแล้วการผูกชื่อและรายชื่อเดิมยังอยู่');
set local role authenticated;
select is(public.join_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'joined',
  'เข้าใหม่ด้วยรหัสเดิมได้');
select ok(
  (select count(*) from public.classrooms c where c.id in (select id from test_rooms)) = 1
  and (select m.student_id from public.memberships m where m.classroom_id in (select id from test_rooms))
      = '62000000-0000-4000-8000-000000000001',
  'เข้าใหม่แล้วกลับมาอ่านห้องได้ด้วยนักเรียนคนเดิม (งานที่ผูกกับนักเรียนจึงเห็นเหมือนเดิม)');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.remove_member((select (body ->> 'classroom_id')::uuid from res where label = 'a'),
                               '62000000-0000-4000-8000-000000000002', true) ->> 'removed', 'true',
  'ผู้ดูแลในโหมดผู้ดูแลเอานักเรียนออกได้');

-- ---------------------------------------------------------------------------
-- I. ภาคเรียนจบแล้ว
-- ---------------------------------------------------------------------------
set local role postgres;
update public.term_control set status = 'ended' where singleton;
set local role authenticated;
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select throws_ok($$ select public.join_classroom((select body ->> 'join_code' from res where label = 'a')) $$,
  'P0001', 'term_ended', 'ภาคเรียนจบแล้วเข้าห้องใหม่ไม่ได้');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.lookup_classroom((select body ->> 'join_code' from res where label = 'a')) ->> 'status', 'member',
  'ภาคเรียนจบแล้วสมาชิกเดิมยังเป็นสมาชิก');
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.create_classroom('ห้องหลังจบเทอม', null, gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ภาคเรียนจบแล้วสร้างห้องไม่ได้');
set local role postgres;
update public.term_control set status = 'active' where singleton;

-- ---------------------------------------------------------------------------
-- J. รหัสชน: สุ่มใหม่จนได้รหัสที่ไม่ซ้ำ (แทนตัวสุ่มชั่วคราว ย้อนเมื่อ rollback)
-- ---------------------------------------------------------------------------
create temp sequence codes_seq;
do $do$
begin
  execute format(
    $f$create or replace function private.new_join_code() returns text language sql volatile set search_path = ''
       as $b$ select case when nextval('pg_temp.codes_seq') = 1 then %L else 'ZZZZ22' end $b$ $f$,
    (select body ->> 'join_code' from res where label = 'a'));
end
$do$;
set local role authenticated;
set local request.jwt.claims to '{"sub": "22000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.create_classroom('ห้องรหัสชน', null, gen_random_uuid()) ->> 'join_code', 'ZZZZ22',
  'รหัสชนกับห้องเดิม → สุ่มใหม่');
select throws_ok($$ select public.create_classroom('ห้องรหัสหมด', null, gen_random_uuid()) $$,
  'P0001', 'join_code_exhausted', 'สุ่มชนซ้ำ 20 รอบแล้วหยุด (ไม่วนไม่จบ)');

set local role postgres;
select * from finish();
rollback;
