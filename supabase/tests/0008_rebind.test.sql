-- ทดสอบ 0008_rebind: รายชื่อ T05, ผูกกับบัญชีอื่น, ถอดการผูก, เพิกถอน session ของบัญชีเดิม
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 3330000x, อีเมล @example.com, ผู้ใช้ auth ปลอม) และ rollback ตอนจบ
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

select plan(34);

-- ---------------------------------------------------------------------------
-- A. สิทธิ์
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select f from unnest(array[
       'public.roster_overview(boolean)', 'public.rebind_preview(uuid,text,boolean)',
       'public.rebind_student(uuid,text,boolean)', 'public.unbind_student(uuid,boolean)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon เรียก RPC แก้การผูกไม่ได้');
select ok(
  (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE')) from unnest(array[
     'public.roster_overview(boolean)', 'public.rebind_preview(uuid,text,boolean)',
     'public.rebind_student(uuid,text,boolean)', 'public.unbind_student(uuid,boolean)']) f),
  'authenticated เรียกได้ (ตรวจครู/โหมดผู้ดูแลภายใน)');
select is_empty(
  $$ select f from unnest(array[
       'private.mask_email(text)', 'private.revoke_sessions(uuid)', 'private.lock_student(uuid)',
       'private.rebind_target(public.students,text)']) f
      where has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'authenticated เรียกฟังก์ชันช่วยภายในไม่ได้');
select is(private.mask_email('somchai@gmail.com'), 's•••••@gmail.com', 'อีเมลปิดบางส่วน');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name) values ('48000000-0000-4000-8000-000000000001', 'ภาคทดสอบแก้ผูก');
insert into public.term_control (term_id) values ('48000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';
insert into public.teachers (id, display_name) values ('18000000-0000-4000-8000-000000000001', 'ครูทดสอบแก้ผูก');
-- ผู้ใช้ auth: 01 บัญชีเดิม (ผูกนักเรียนหนึ่ง), 02 บัญชีใหม่ (ยังไม่ผูก)
insert into auth.users (id, email) values
  ('28000000-0000-4000-8000-000000000001', 'old8@example.com'),
  ('28000000-0000-4000-8000-000000000002', 'new8@example.com');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('38000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', 'google', 'rb-1', 'old8@example.com', 'student', null),
  ('38000000-0000-4000-8000-000000000002', '28000000-0000-4000-8000-000000000002', 'google', 'rb-2', 'new8@example.com', 'student', null),
  ('38000000-0000-4000-8000-000000000003', '28000000-0000-4000-8000-000000000003', 'google', 'rb-3', 'other8@example.com', 'student', null),
  ('38000000-0000-4000-8000-000000000004', '28000000-0000-4000-8000-000000000004', 'google', 'rb-4', 'teacher8@example.com', 'teacher', '18000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000005', '28000000-0000-4000-8000-000000000005', 'google', 'rb-5', 'admin8@example.com', 'admin', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('68000000-0000-4000-8000-000000000001', '33300001', 'หนึ่ง แก้ผูก', '38000000-0000-4000-8000-000000000001'),
  ('68000000-0000-4000-8000-000000000002', '33300002', 'สอง ผูกอยู่', '38000000-0000-4000-8000-000000000003');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('48000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', 'ม.5/1', 1),
  ('48000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000002', 'ม.5/1', 2);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('78000000-0000-4000-8000-000000000001', '48000000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000001', 'เคมีแก้ผูก ม.5/1', 'QQQQ38');
insert into public.memberships (classroom_id, student_id) values
  ('78000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001');
-- บัญชีเดิมล็อกอินอยู่ 2 เครื่อง (session + refresh token) และมี refresh token รุ่นเก่าที่ไม่มี session อีกหนึ่งอัน
insert into auth.sessions (id, user_id) values
  ('88000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001'),
  ('88000000-0000-4000-8000-000000000002', '28000000-0000-4000-8000-000000000001');
insert into auth.refresh_tokens (token, user_id, session_id, revoked) values
  ('rb-old-token-1', '28000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000001', false),
  ('rb-old-token-2', '28000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', false),
  ('rb-old-token-legacy', '28000000-0000-4000-8000-000000000001', null, false);

create temp table res (label text primary key, body jsonb not null);
grant select, insert on res to authenticated;

-- ---------------------------------------------------------------------------
-- B. T05 รายชื่อ
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000004", "role": "authenticated"}';
insert into res values ('overview', public.roster_overview());
set local role postgres;
select is(
  (select x - 'student_id' from res, jsonb_array_elements(res.body) x where res.label = 'overview' and x ->> 'student_code' = '33300001'),
  '{"display_name": "หนึ่ง แก้ผูก", "student_code": "33300001", "group_name": "ม.5/1", "roll_number": 1,
    "bound": true, "account_email": "o•••••@example.com", "classrooms": ["เคมีแก้ผูก ม.5/1"],
    "wallet_balance": 0, "wallet_version": 0}'::jsonb,
  'รายชื่อ T05: ห้อง เลขที่ บัญชี (อีเมลปิดบางส่วน) และชั้นเรียนที่เข้าแล้ว');
select ok((select body::text !~ 'old8@example\.com|other8@example\.com' from res where label = 'overview'),
  'รายชื่อ T05 ไม่มีอีเมลเต็มของนักเรียน');
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.roster_overview() $$, 'P0001', 'forbidden', 'นักเรียนเปิดรายชื่อ T05 ไม่ได้');

-- ---------------------------------------------------------------------------
-- C. หน้าทวนก่อนผูกกับบัญชีอื่น
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.rebind_preview('68000000-0000-4000-8000-000000000001', 'nobody8@example.com') $$,
  'P0001', 'account_not_found', 'บัญชีที่ยังไม่เคยเข้าสู่ระบบ: ไม่พบบัญชี');
select throws_ok($$ select public.rebind_preview('68000000-0000-4000-8000-000000000001', 'teacher8@example.com') $$,
  'P0001', 'account_not_student', 'บัญชีครู/ผู้ดูแลผูกกับนักเรียนไม่ได้');
select throws_ok($$ select public.rebind_preview('68000000-0000-4000-8000-000000000001', 'other8@example.com') $$,
  'P0001', 'account_bound_elsewhere', 'ผูกกับบัญชีที่ผูกนักเรียนคนอื่นอยู่ไม่ได้');
select throws_ok($$ select public.rebind_preview('68000000-0000-4000-8000-000000000001', 'old8@example.com') $$,
  'P0001', 'rebind_same_account', 'บัญชีเดิมของนักเรียนคนนี้');
select throws_ok($$ select public.rebind_preview('68000000-0000-4000-8000-000000000099', 'new8@example.com') $$,
  'P0001', 'student_not_found', 'นักเรียนที่ไม่มีอยู่');
select is(public.rebind_preview('68000000-0000-4000-8000-000000000001', '  NEW8@Example.com ') - 'student_id',
  '{"display_name": "หนึ่ง แก้ผูก", "old_email": "o•••••@example.com", "new_email": "new8@example.com"}'::jsonb,
  'หน้าทวน: ชื่อนักเรียน · บัญชีเดิม (ปิดบางส่วน) → บัญชีใหม่ (ไม่สนตัวพิมพ์/ช่องว่าง)');

-- ---------------------------------------------------------------------------
-- D. ใครเรียกได้
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.rebind_student('68000000-0000-4000-8000-000000000001', 'new8@example.com') $$,
  'P0001', 'forbidden', 'นักเรียนแก้การผูกไม่ได้');
select throws_ok($$ select public.unbind_student('68000000-0000-4000-8000-000000000001') $$,
  'P0001', 'forbidden', 'นักเรียนถอดการผูกไม่ได้');
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select throws_ok($$ select public.rebind_student('68000000-0000-4000-8000-000000000001', 'new8@example.com') $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลแก้การผูกไม่ได้');
set local role anon;
select throws_ok($$ select public.rebind_student('68000000-0000-4000-8000-000000000001', 'new8@example.com') $$,
  '42501', null, 'anon แก้การผูกไม่ได้');

-- ---------------------------------------------------------------------------
-- E. ผูกกับบัญชีอื่น
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select is(public.rebind_student('68000000-0000-4000-8000-000000000001', 'New8@example.com') - 'student_id',
  '{"display_name": "หนึ่ง แก้ผูก", "old_email": "o•••••@example.com", "new_email": "new8@example.com",
    "revoked_sessions": 2, "changed": true}'::jsonb,
  'ครูผูกกับบัญชีอื่นสำเร็จ และเพิกถอน 2 session ของบัญชีเดิม');
select is(public.rebind_student('68000000-0000-4000-8000-000000000001', 'new8@example.com') ->> 'changed', 'false',
  'เรียกซ้ำหลังสำเร็จได้ผลเดิมโดยไม่เปลี่ยนอะไร');

set local role postgres;
select is((select s.account_id from public.students s where s.id = '68000000-0000-4000-8000-000000000001'),
  '38000000-0000-4000-8000-000000000002'::uuid, 'นักเรียนผูกกับบัญชีใหม่แล้ว');
select is(
  (select count(*) from auth.sessions where user_id = '28000000-0000-4000-8000-000000000001')
  + (select count(*) from auth.refresh_tokens where user_id = '28000000-0000-4000-8000-000000000001'),
  0::bigint, 'บัญชีเดิมไม่มี session/refresh token เหลือ → refresh ไม่ได้');
select is((select count(*) from public.memberships where student_id = '68000000-0000-4000-8000-000000000001'),
  1::bigint, 'ไม่แตะ membership ของนักเรียน');

-- access token เก่าของบัญชีเดิม (ยังไม่หมดอายุ อ้าง session ที่ถูกลบแล้ว) ใช้สิทธิ์นักเรียนคนเดิมไม่ได้ทันที
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000001", "role": "authenticated", "session_id": "88000000-0000-4000-8000-000000000001"}';
select is(public.my_classrooms(), '[]'::jsonb, 'บัญชีเดิม: ไม่เห็นชั้นเรียนของนักเรียนคนเดิม');
select throws_ok($$ select public.classroom_view('78000000-0000-4000-8000-000000000001') $$, 'P0001', 'not_member',
  'บัญชีเดิม: เปิดหน้าห้องไม่ได้');
select throws_ok($$ select public.join_classroom('QQQQ38') $$, 'P0001', 'identity_required',
  'บัญชีเดิม: กลายเป็นบัญชีที่ยังไม่เลือกชื่อ');
select is((select count(*) from public.students), 0::bigint, 'บัญชีเดิม: อ่านแถวนักเรียนคนเดิมไม่ได้ (RLS)');

set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((select jsonb_agg(x ->> 'name') from jsonb_array_elements(public.my_classrooms()) x), '["เคมีแก้ผูก ม.5/1"]'::jsonb,
  'บัญชีใหม่เห็นชั้นเรียนเดิมของนักเรียน');
select is(public.classroom_view('78000000-0000-4000-8000-000000000001') #>> '{members,0,is_me}', 'true',
  'บัญชีใหม่เปิดหน้าห้องเดิมได้ในฐานะนักเรียนคนเดิม');

-- ---------------------------------------------------------------------------
-- F. ถอดการผูก (ผู้ดูแลในโหมดผู้ดูแล)
-- ---------------------------------------------------------------------------
set local role postgres;
insert into auth.sessions (id, user_id) values ('88000000-0000-4000-8000-000000000003', '28000000-0000-4000-8000-000000000002');
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.unbind_student('68000000-0000-4000-8000-000000000001', true) - 'student_id',
  '{"display_name": "หนึ่ง แก้ผูก", "old_email": "n•••••@example.com", "revoked_sessions": 1, "changed": true}'::jsonb,
  'ผู้ดูแลในโหมดผู้ดูแลถอดการผูกได้ และเพิกถอน session ของบัญชีนั้น');
select is(public.unbind_student('68000000-0000-4000-8000-000000000001', true) ->> 'changed', 'false',
  'ถอดซ้ำได้ผลเดิม');
set local role postgres;
select ok(
  (select s.account_id is null from public.students s where s.id = '68000000-0000-4000-8000-000000000001')
  and (select count(*) from auth.sessions where user_id = '28000000-0000-4000-8000-000000000002') = 0
  and (select count(*) from public.memberships where student_id = '68000000-0000-4000-8000-000000000001') = 1,
  'ถอดแล้ว: ไม่มีบัญชีผูก session ถูกลบ membership ยังอยู่');

-- หลังถอด นักเรียนเลือกชื่อของตัวเองใหม่ได้ผ่าน A02 แล้วเห็นชั้นเรียนเดิม
set local role authenticated;
set local request.jwt.claims to '{"sub": "28000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('search', public.search_roster('33300001'));
select is((select jsonb_array_length(body -> 'matches') from res where label = 'search'), 1,
  'หลังถอด: ค้นชื่อนี้เจอ (ยังไม่ผูก)');
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'search')) ->> 'status',
  'claimed', 'หลังถอด: เลือกชื่อของตัวเองได้');
select is(jsonb_array_length(public.my_classrooms()), 1, 'เลือกชื่อแล้วเห็นชั้นเรียนเดิม');

set local role postgres;
select * from finish();
rollback;
