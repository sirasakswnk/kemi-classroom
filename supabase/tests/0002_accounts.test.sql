-- ทดสอบ 0002_accounts: ensure_account(), allowlist, policy ที่เรียก private.current_account() โดยไม่มี USAGE
-- ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

-- ให้เรียก pgTAP ได้ขณะสลับเป็น anon/authenticated (0001 ถอน EXECUTE ของฟังก์ชันใหม่จาก PUBLIC) — ย้อนเมื่อ rollback
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

select plan(50);

-- ---------------------------------------------------------------------------
-- A. โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('public', 'accounts', 'มี public.accounts');
select has_table('public', 'teachers', 'มี public.teachers');
select has_table('private', 'teacher_allowlist', 'มี private.teacher_allowlist');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated ไม่มี USAGE บน private');
select ok(has_function_privilege('authenticated', 'private.current_account()', 'EXECUTE'),
  'authenticated มี EXECUTE บน private.current_account() (ให้ policy ใช้)');
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['anon', 'authenticated']) r,
            unnest(array['private.require_teacher(boolean)', 'private.require_admin()']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'anon/authenticated เรียก require_teacher/require_admin ไม่ได้'
);
select ok(not has_function_privilege('anon', 'public.ensure_account()', 'EXECUTE'), 'anon ไม่มี EXECUTE บน ensure_account()');
select ok(has_function_privilege('authenticated', 'public.ensure_account()', 'EXECUTE'), 'authenticated เรียก ensure_account() ได้');
select policies_are('public', 'accounts', array['accounts_select_own'], 'accounts มีเฉพาะ policy อ่านแถวตัวเอง');
select is_definer('private', 'current_account', '{}'::name[], 'current_account() เป็น SECURITY DEFINER');
select is_definer('public', 'ensure_account', '{}'::name[], 'ensure_account() เป็น SECURITY DEFINER');
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
        and p.proname <> 'rls_auto_enable'
        and not coalesce(p.proconfig @> array['search_path=""'], false) $$,
  'ทุกฟังก์ชันของเราใน public/private ตั้ง search_path = '''''
);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ---------------------------------------------------------------------------
create function pg_temp.mk_user(p_id uuid, p_provider text, p_subject text, p_email text,
                                p_verified boolean, p_meta jsonb default '{}'::jsonb)
returns void
language plpgsql
as $$
begin
  insert into auth.users (id, aud, role, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  values (p_id, 'authenticated', 'authenticated', p_meta,
          jsonb_build_object('provider', p_provider), now(), now());
  if p_provider is not null then
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (p_subject, p_id,
            jsonb_build_object('sub', p_subject, 'email', p_email, 'email_verified', p_verified),
            p_provider, now(), now(), now());
  end if;
end
$$;

insert into public.teachers (id, display_name) values
  ('10000000-0000-4000-8000-000000000001', 'ครูทดสอบหนึ่ง'),
  ('10000000-0000-4000-8000-000000000002', 'ครูทดสอบสอง');

insert into private.teacher_allowlist (teacher_id, email, provider_subject, revoked_at) values
  ('10000000-0000-4000-8000-000000000001', 't1@example.com', 'g-t1', null),
  ('10000000-0000-4000-8000-000000000001', 't1.school@example.com', null, null),
  ('10000000-0000-4000-8000-000000000002', 'revoked@example.com', null, clock_timestamp()),
  ('10000000-0000-4000-8000-000000000002', 't2@example.com', null, null),
  ('10000000-0000-4000-8000-000000000002', 'mail.teacher@example.com', null, null);

select pg_temp.mk_user('20000000-0000-4000-8000-000000000001', 'google', 'g-t1', 't2@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000002', 'google', 'g-new', 't1.school@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000003', 'google', 'g-late', 't1.school@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000004', 'google', 'g-unver', 't2@example.com', false);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000005', 'google', 'g-meta', 'student@example.com', true,
  jsonb_build_object('role', 'teacher', 'teacher_id', '10000000-0000-4000-8000-000000000001',
                     'email', 't2@example.com', 'email_verified', true, 'sub', 'g-t1', 'provider_id', 'g-t1'));
select pg_temp.mk_user('20000000-0000-4000-8000-000000000006', 'google', 'g-rev', 'revoked@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000007', 'email',
  '20000000-0000-4000-8000-000000000007', 'mail.teacher@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000008', 'google', 'g-admin', 'admin@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-000000000009', 'google', 'g-restore', 'restore@example.com', true);
select pg_temp.mk_user('20000000-0000-4000-8000-00000000000a', null, null, null, null);

-- บัญชีที่มีอยู่ก่อน: admin ตั้งโดยผู้พัฒนา และบัญชีที่กู้มา (auth_user_id = null)
insert into public.accounts (auth_user_id, provider, provider_subject, email, role) values
  ('20000000-0000-4000-8000-000000000008', 'google', 'g-admin', 'admin@example.com', 'admin');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email) values
  ('30000000-0000-4000-8000-000000000009', null, 'google', 'g-restore', 'restore@example.com');

-- ---------------------------------------------------------------------------
-- C. anon
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok('select public.ensure_account()', '42501', null, 'anon เรียก ensure_account() ไม่ได้');
select throws_ok('select * from public.accounts', '42501', null, 'anon อ่าน accounts ไม่ได้');
set local role postgres;

-- ---------------------------------------------------------------------------
-- D. ensure_account()
-- ---------------------------------------------------------------------------
set local role authenticated;

set local request.jwt.claims to '{"role": "authenticated"}';
select throws_ok('select public.ensure_account()', 'P0001', 'not_authenticated', 'ไม่มี sub ใน JWT ถูกปฏิเสธ');

-- provider_subject มาก่อนอีเมล: sub ตรง E(t1) แม้อีเมลตรงรายการ t2 ที่ยังไม่ตรึง
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.ensure_account() - 'account_id' - 'email',
  '{"role": "teacher", "teacher_id": "10000000-0000-4000-8000-000000000001"}'::jsonb,
  'จับคู่ allowlist ด้วย provider_subject ก่อนอีเมล');

-- อีเมลที่ Google ยืนยันแล้ว กับรายการที่ยังไม่ตรึง
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is(public.ensure_account() - 'account_id' - 'email',
  '{"role": "teacher", "teacher_id": "10000000-0000-4000-8000-000000000001"}'::jsonb,
  'จับคู่ด้วยอีเมลที่ยืนยันแล้วเมื่อไม่มี provider_subject ตรง');
set local role postgres;
select is((select provider_subject from private.teacher_allowlist where email = 't1.school@example.com'), 'g-new',
  'จับด้วยอีเมลแล้วตรึง provider_subject ไว้');
set local role authenticated;

-- รายการที่ตรึงแล้ว: บัญชี Google อื่นที่อีเมลเดียวกันไม่ได้เป็นครู
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.ensure_account() - 'account_id' - 'email',
  '{"role": "student", "teacher_id": null}'::jsonb,
  'รายการที่ตรึง provider_subject แล้ว ไม่จับด้วยอีเมลซ้ำ');

-- อีเมลที่ยังไม่ยืนยันไม่ใช้จับคู่
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select is(public.ensure_account() - 'account_id',
  '{"role": "student", "teacher_id": null, "email": null}'::jsonb,
  'อีเมลที่ไม่ยืนยันไม่ใช้จับคู่และไม่เก็บ');
set local role postgres;
select is((select provider_subject from private.teacher_allowlist where email = 't2@example.com'), null,
  'รายการ t2 ไม่ถูกตรึงโดยบัญชีที่จับด้วย subject หรืออีเมลที่ไม่ยืนยัน');
set local role authenticated;

-- user_metadata อ้างเป็นครูทุกทาง แต่ตัวตนจริงไม่อยู่ใน allowlist
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.ensure_account() - 'account_id' - 'email',
  '{"role": "student", "teacher_id": null}'::jsonb,
  'ไม่ใช้ user_metadata ตัดสินสิทธิ์');
set local role postgres;
select is((select role || ' ' || email from public.accounts where provider_subject = 'g-meta'),
  'student student@example.com',
  'บัญชีเก็บอีเมลจาก identity ไม่ใช่จาก user_metadata');
set local role authenticated;

set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is(public.ensure_account() ->> 'role', 'student', 'รายการ allowlist ที่เอาออกแล้วไม่มีผล');

set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok('select public.ensure_account()', 'P0001', 'provider_not_allowed', 'ไม่มีตัวตน Google ถูกปฏิเสธ');

-- provider email: ปิดอยู่ (ค่าเริ่มต้น) → ปฏิเสธ
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select throws_ok('select public.ensure_account()', 'P0001', 'provider_not_allowed',
  'provider email ถูกปฏิเสธเมื่อไม่มี allow_test_logins = on');
set local role postgres;
insert into private.settings (key, value) values ('allow_test_logins', 'on');
set local role authenticated;
select is(public.ensure_account() ->> 'role', 'student',
  'provider email ใช้ได้เมื่อ allow_test_logins = on และไม่จับ allowlist ด้วยอีเมล');
set local role postgres;
select is((select provider_subject from private.teacher_allowlist where email = 'mail.teacher@example.com'), null,
  'บัญชี provider email ไม่ตรึงรายการ allowlist ที่เป็นอีเมล');
insert into private.teacher_allowlist (teacher_id, provider_subject)
values ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000007');
set local role authenticated;
select is(public.ensure_account() - 'account_id' - 'email',
  '{"role": "teacher", "teacher_id": "10000000-0000-4000-8000-000000000002"}'::jsonb,
  'บัญชี provider email เป็นครูได้ด้วย provider_subject เท่านั้น');

-- admin ตั้งในฐานข้อมูลเท่านั้น ensure_account() ไม่ถอด
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000008", "role": "authenticated"}';
select is(public.ensure_account() ->> 'role', 'admin', 'ensure_account() คง role admin');

-- หลังกู้ข้อมูล: จับคู่ด้วย provider_subject แล้วอัปเดต auth_user_id
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000009", "role": "authenticated"}';
select is(public.ensure_account() ->> 'account_id', '30000000-0000-4000-8000-000000000009',
  'บัญชีที่กู้มา (auth_user_id = null) จับคู่ด้วย provider_subject');
set local role postgres;
select is((select auth_user_id from public.accounts where id = '30000000-0000-4000-8000-000000000009'),
  '20000000-0000-4000-8000-000000000009'::uuid, 'อัปเดต auth_user_id ของบัญชีที่กู้มา');

-- เรียกซ้ำได้ผลเดิม (อ่านบัญชีตัวเองผ่าน policy)
set local role authenticated;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is((public.ensure_account() ->> 'account_id')::uuid, (select id from public.accounts),
  'เรียกซ้ำได้บัญชีเดิม');
set local role postgres;
select is((select count(*)::int from public.accounts where provider_subject = 'g-t1'), 1, 'ไม่สร้างบัญชีซ้ำ');

-- เอาออกจาก allowlist แล้วเรียกครั้งถัดไปกลับเป็นนักเรียน (บัญชี provider email ที่เป็นครูด้วย subject)
update private.teacher_allowlist set revoked_at = clock_timestamp()
 where provider_subject = '20000000-0000-4000-8000-000000000007';
set local role authenticated;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is(public.ensure_account() ->> 'role', 'student', 'ถูกเอาออกจาก allowlist แล้วเป็นนักเรียน');
set local role postgres;
select is((select role || ' ' || coalesce(teacher_id::text, '-') from public.accounts
            where provider_subject = '20000000-0000-4000-8000-000000000007'),
  'student -', 'accounts อัปเดต role และล้าง teacher_id');

-- ---------------------------------------------------------------------------
-- E. policy ใช้ private.current_account() ได้โดยไม่มี USAGE บน private
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((select count(*)::int from public.accounts), 1, 'policy ทำงาน: เห็นบัญชีของตัวเองแถวเดียว');
select is((select auth_user_id from public.accounts), '20000000-0000-4000-8000-000000000002'::uuid,
  'แถวที่เห็นคือบัญชีของผู้เรียก');
select throws_ok('select private.current_account()', '42501', 'permission denied for schema private',
  'authenticated เรียก private.current_account() ตรงไม่ได้');
select throws_ok('select * from private.teacher_allowlist', '42501', null,
  'authenticated อ่าน private.teacher_allowlist ไม่ได้');
select throws_ok('select private.require_teacher()', '42501', null,
  'authenticated เรียก private.require_teacher() ตรงไม่ได้');
select throws_ok($$ update public.accounts set role = 'teacher' $$, '42501', null,
  'authenticated แก้ accounts ตรงไม่ได้ (เขียนผ่าน RPC เท่านั้น)');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select is((select count(*)::int from public.accounts), 0, 'ผู้ที่ยังไม่มีบัญชีไม่เห็นแถวใด');

-- ---------------------------------------------------------------------------
-- F. require_teacher / require_admin (เรียกภายใน RPC ในนาม postgres)
-- ---------------------------------------------------------------------------
set local role postgres;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select lives_ok('select private.require_teacher()', 'ครูผ่าน require_teacher()');
select throws_ok('select private.require_admin()', 'P0001', 'forbidden', 'ครูไม่ผ่าน require_admin()');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000008", "role": "authenticated"}';
select throws_ok('select private.require_teacher()', 'P0001', 'admin_mode_required',
  'admin ต้องส่ง p_admin_mode ถึงทำแทนครูได้');
select lives_ok('select private.require_teacher(true)', 'admin ในโหมดผู้ดูแลผ่าน require_teacher()');
select lives_ok('select private.require_admin()', 'admin ผ่าน require_admin()');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok('select private.require_teacher()', 'P0001', 'forbidden', 'นักเรียนไม่ผ่าน require_teacher()');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok('select private.require_teacher()', 'P0001', 'account_required', 'ยังไม่มีบัญชีไม่ผ่าน require_teacher()');

select * from finish();
rollback;
