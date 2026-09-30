-- ทดสอบ 0001_base: schema private, default privileges, ตารางกลาง, ping()
-- รูปแบบทุกไฟล์: begin → ติดตั้ง pgtap ใน transaction → ทดสอบ → rollback (ไม่เหลือร่องรอยบนฐานข้อมูล)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(33);

-- ---------------------------------------------------------------------------
-- schema private
-- ---------------------------------------------------------------------------
select has_schema('private');
select is(
  (select pg_get_userbyid(nspowner)::text from pg_namespace where nspname = 'private'),
  'postgres',
  'private เป็นของ postgres'
);
select is_empty(
  $$ select format('%s %s', r, p)
       from unnest(array['public', 'anon', 'authenticated']) r,
            unnest(array['USAGE', 'CREATE']) p
      where has_schema_privilege(r, 'private', p) $$,
  'PUBLIC/anon/authenticated ไม่มี USAGE/CREATE บน private'
);

-- ---------------------------------------------------------------------------
-- pgcrypto อยู่ใน extensions และเรียกแบบชื่อเต็มได้ (ฟังก์ชันที่ตั้ง search_path = '')
-- ---------------------------------------------------------------------------
select is(
  (select extnamespace::regnamespace::text from pg_extension where extname = 'pgcrypto'),
  'extensions',
  'pgcrypto อยู่ใน schema extensions'
);
select is(length(extensions.gen_random_bytes(16)), 16, 'เรียก extensions.gen_random_bytes() แบบชื่อเต็มได้');

-- ---------------------------------------------------------------------------
-- ตารางกลาง
-- ---------------------------------------------------------------------------
select has_table('private', 'settings', 'มี private.settings');
select has_table('private', 'operation_receipts', 'มี private.operation_receipts');
select has_table('private', 'rate_limits', 'มี private.rate_limits');
select has_table('private', 'jobs', 'มี private.jobs');
select has_table('private', 'maintenance_locks', 'มี private.maintenance_locks');

-- ---------------------------------------------------------------------------
-- สิทธิ์ของทุกตาราง/sequence/ฟังก์ชันที่มีอยู่ใน public และ private
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select c.oid::regclass::text
       from pg_class c
      where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace)
        and c.relkind in ('r', 'p')
        and not c.relrowsecurity $$,
  'ทุกตารางใน public/private เปิด RLS'
);
select is_empty(
  $$ select c.oid::regclass::text
       from pg_class c
      where c.relnamespace = 'private'::regnamespace
        and c.relowner <> 'postgres'::regrole $$,
  'ทุก relation ใน private เป็นของ postgres'
);
select is_empty(
  $$ select format('%s %s', c.oid::regclass, p)
       from pg_class c,
            unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE',
                          'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p
      where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace)
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and has_table_privilege('anon', c.oid, p) $$,
  'anon ไม่มีสิทธิ์ใดบนตารางใน public/private'
);
select is_empty(
  $$ select format('%s %s', c.oid::regclass, p)
       from pg_class c,
            unnest(array['INSERT', 'UPDATE', 'DELETE',
                          'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p
      where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace)
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and has_table_privilege('authenticated', c.oid, p) $$,
  'authenticated ไม่มีสิทธิ์เขียน/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN บนตารางใน public/private'
);
select is_empty(
  $$ select c.oid::regclass::text
       from pg_class c
      where c.relnamespace = 'private'::regnamespace
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and has_table_privilege('authenticated', c.oid, 'SELECT') $$,
  'authenticated อ่านตารางใน private ไม่ได้'
);
select is_empty(
  $$ select format('%s %s %s', r, c.oid::regclass, p)
       from pg_class c,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['USAGE', 'SELECT', 'UPDATE']) p
      where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace)
        and c.relkind = 'S'
        and has_sequence_privilege(r, c.oid, p) $$,
  'anon/authenticated ไม่มีสิทธิ์บน sequence ใน public/private'
);
select is_empty(
  $$ select format('%s %s', r, p.oid::regprocedure)
       from pg_proc p,
            unnest(array['public', 'anon']) r
      where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
        and has_function_privilege(r, p.oid, 'EXECUTE') $$,
  'PUBLIC/anon เรียกฟังก์ชันใดใน public/private ไม่ได้'
);
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
        and p.proowner <> 'postgres'::regrole $$,
  'ทุกฟังก์ชันใน public/private เป็นของ postgres'
);
select case
  when to_regprocedure('public.rls_auto_enable()') is null
    then skip('ไม่มี public.rls_auto_enable() (Supabase ในเครื่องไม่มี automatic RLS)', 1)
  else is_empty(
    $$ select r
         from unnest(array['public', 'anon', 'authenticated']) r
        where has_function_privilege(r, 'public.rls_auto_enable()', 'EXECUTE') $$,
    'PUBLIC/anon/authenticated เรียก public.rls_auto_enable() ไม่ได้'
  )
end;

-- ---------------------------------------------------------------------------
-- ping()
-- ---------------------------------------------------------------------------
select has_function('public', 'ping', '{}'::name[], 'มี public.ping()');
select is(public.ping(), 'pong', 'ping() ตอบ pong');
select ok(has_function_privilege('service_role', 'public.ping()', 'EXECUTE'), 'service_role เรียก ping() ได้');
select ok(not has_function_privilege('authenticated', 'public.ping()', 'EXECUTE'), 'authenticated เรียก ping() ไม่ได้');

-- ---------------------------------------------------------------------------
-- ข้อบังคับของตาราง
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into private.settings (key, value) values ('Bad-Key', 'x') $$,
  '23514', null, 'settings.key ต้องเป็นตัวพิมพ์เล็ก/ตัวเลข/_'
);
select throws_ok(
  $$ insert into private.jobs (kind, status) values ('probe', 'bogus') $$,
  '23514', null, 'jobs.status รับเฉพาะ pending/running/done/failed'
);
select lives_ok(
  $$ insert into private.jobs (kind, dedupe_key) values ('probe', 'k1') $$,
  'เพิ่มงานพร้อม dedupe_key ได้'
);
select throws_ok(
  $$ insert into private.jobs (kind, dedupe_key) values ('probe', 'k1') $$,
  '23505', null, 'งานชนิดเดียวกัน dedupe_key ซ้ำไม่ได้'
);
select throws_ok(
  $$ insert into private.maintenance_locks (name, expires_at) values ('backup', clock_timestamp() - interval '1 minute') $$,
  '23514', null, 'maintenance_locks ต้องหมดอายุหลังเวลาตั้งธง'
);
with r as (
  insert into private.operation_receipts (account_id, request_key, operation, result)
  values (gen_random_uuid(), gen_random_uuid(), 'probe', '{}'::jsonb)
  returning expires_at - created_at as ttl
)
select ok(
  ttl between interval '23:59:59' and interval '24:00:01',
  'operation_receipts หมดอายุ 24 ชม. โดยค่าเริ่มต้น'
) from r;

-- ---------------------------------------------------------------------------
-- default privileges: วัตถุที่ postgres สร้างใหม่ต้องไม่ให้สิทธิ์ anon/authenticated/PUBLIC เลย
-- ---------------------------------------------------------------------------
set local role postgres;
create table public.p106_probe_t (id int);
create table private.p106_probe_t (id int);
create sequence public.p106_probe_s;
create sequence private.p106_probe_s;
create function public.p106_probe_f() returns int language sql as 'select 1';
create function private.p106_probe_f() returns int language sql as 'select 1';

select is_empty(
  $$ select format('%s %s %s', r, c.oid::regclass, p)
       from pg_class c,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE',
                          'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p
      where c.relname = 'p106_probe_t'
        and has_table_privilege(r, c.oid, p) $$,
  'ตารางใหม่ใน public/private: anon/authenticated ไม่ได้สิทธิ์ใดเลย (รวม TRUNCATE/REFERENCES/TRIGGER)'
);
select is_empty(
  $$ select format('%s %s %s', r, c.oid::regclass, p)
       from pg_class c,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['USAGE', 'SELECT', 'UPDATE']) p
      where c.relname = 'p106_probe_s'
        and has_sequence_privilege(r, c.oid, p) $$,
  'sequence ใหม่ใน public/private: anon/authenticated ไม่ได้สิทธิ์'
);
select is_empty(
  $$ select format('%s %s', r, p.oid::regprocedure)
       from pg_proc p,
            unnest(array['public', 'anon', 'authenticated']) r
      where p.proname = 'p106_probe_f'
        and has_function_privilege(r, p.oid, 'EXECUTE') $$,
  'ฟังก์ชันใหม่ใน public/private: PUBLIC/anon/authenticated เรียกไม่ได้'
);
select case
  when to_regprocedure('public.rls_auto_enable()') is null
    then skip('ไม่มี automatic RLS ในฐานข้อมูลนี้', 1)
  else ok(
    (select relrowsecurity from pg_class where oid = 'public.p106_probe_t'::regclass),
    'automatic RLS ยังเปิด RLS ให้ตารางใหม่ใน public หลังถอน EXECUTE'
  )
end;

select * from finish();
rollback;
