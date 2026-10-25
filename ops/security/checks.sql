-- P7-04: ตรวจความปลอดภัยของฐานข้อมูล (TECHNICAL_BUILD_PLAN ส่วน 11) — SELECT คำสั่งเดียว อ่านอย่างเดียว รันกับ dev และ prod ได้
-- ใช้ผ่าน ops/security-check.mjs ซึ่งแทนตัวยึดตำแหน่งใน values ของ exp_auth / exp_service / pg_only ด้วยรายการจาก
-- supabase/tests/function_privileges.test.sql (รายการเดียวกับ pgTAP — ไม่ต้องดูแลสองที่)
-- ผล: หนึ่งแถวต่อข้อ (check, ok, n, detail) — ok = ไม่มีรายการที่ผิด, detail = 20 รายการแรกที่ผิด
with
exp_auth(fn) as (values /*AUTH*/),
exp_service(fn) as (values /*SERVICE*/),
pg_only(fn) as (values /*PGONLY*/),
fns as (
  select p.oid,
         p.oid::regprocedure::text as fn,
         p.pronamespace::regnamespace::text as nsp,
         p.proname,
         p.prosecdef,
         p.proconfig,
         p.prosrc
    from pg_catalog.pg_proc p
   where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
),
rels as (
  select c.oid, n.nspname || '.' || c.relname as rel, c.relkind, c.relrowsecurity, c.reloptions
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm', 'f')
),
checks(ord, name, bad) as (
  -- 1. RLS ทุกตาราง (public และ private)
  select 1, 'rls_enabled',
         array(select rel from rels where relkind in ('r', 'p') and not relrowsecurity order by 1)
  -- 2. anon / PUBLIC เรียกฟังก์ชันใน public/private ไม่ได้
  union all select 2, 'anon_execute',
         array(select fn from fns where has_function_privilege('anon', oid, 'EXECUTE') order by 1)
  union all select 3, 'public_execute',
         array(select fn from fns where has_function_privilege('public', oid, 'EXECUTE') order by 1)
  -- 3. SECURITY DEFINER ตั้ง search_path (ของเราต้องเป็น '')
  union all select 4, 'secdef_search_path',
         array(select fn from fns
                where prosecdef
                  and not exists (select 1 from unnest(coalesce(proconfig, '{}')) c where c like 'search_path=%')
                order by 1)
  union all select 5, 'secdef_search_path_empty',
         array(select fn from fns
                where prosecdef and proname <> 'rls_auto_enable'
                  and not coalesce(proconfig @> array['search_path=""'], false)
                order by 1)
  -- 4. authenticated เรียกได้ตรงรายการที่ตั้งใจไว้ (ไม่เกิน ไม่ขาด)
  union all select 6, 'authenticated_unexpected',
         array(select f.fn from fns f
                where has_function_privilege('authenticated', f.oid, 'EXECUTE')
                  and not exists (select 1 from exp_auth e where to_regprocedure(e.fn) = f.oid)
                order by 1)
  union all select 7, 'authenticated_missing',
         array(select e.fn from exp_auth e
                where to_regprocedure(e.fn) is null
                   or not has_function_privilege('authenticated', to_regprocedure(e.fn), 'EXECUTE')
                order by 1)
  -- 5. RPC ของ service_role อยู่ในรายการ และผู้ใช้เรียกไม่ได้
  union all select 8, 'service_only_unexpected',
         array(select f.fn from fns f
                where f.nsp = 'public'
                  and has_function_privilege('service_role', f.oid, 'EXECUTE')
                  and not has_function_privilege('authenticated', f.oid, 'EXECUTE')
                  and not exists (select 1 from exp_service e where to_regprocedure(e.fn) = f.oid)
                order by 1)
  union all select 9, 'service_only_wrong',
         array(select e.fn from exp_service e
                where to_regprocedure(e.fn) is null
                   or not has_function_privilege('service_role', to_regprocedure(e.fn), 'EXECUTE')
                   or has_function_privilege('authenticated', to_regprocedure(e.fn), 'EXECUTE')
                   or has_function_privilege('anon', to_regprocedure(e.fn), 'EXECUTE')
                   or has_function_privilege('public', to_regprocedure(e.fn), 'EXECUTE')
                order by 1)
  union all select 10, 'private_service_role',
         array(select fn from fns where nsp = 'private' and has_function_privilege('service_role', oid, 'EXECUTE') order by 1)
  union all select 11, 'postgres_only',
         array(select o.fn from pg_only o
                where to_regprocedure(o.fn) is null
                   or has_function_privilege('authenticated', to_regprocedure(o.fn), 'EXECUTE')
                   or has_function_privilege('anon', to_regprocedure(o.fn), 'EXECUTE')
                   or has_function_privilege('public', to_regprocedure(o.fn), 'EXECUTE')
                   or has_function_privilege('service_role', to_regprocedure(o.fn), 'EXECUTE')
                order by 1)
  -- 6. ไม่ตัดสินสิทธิ์จาก metadata ของ Supabase Auth (ทั้งในฟังก์ชันและ policy)
  union all select 12, 'auth_metadata',
         array(select fn from fns where prosrc ~* '(user_metadata|raw_user_meta_data|app_metadata|raw_app_meta_data)'
               union all
               select 'policy ' || schemaname || '.' || tablename || '.' || policyname
                 from pg_catalog.pg_policies
                where schemaname in ('public', 'private')
                  and coalesce(qual, '') || coalesce(with_check, '') ~* '(user_metadata|raw_user_meta_data|app_metadata)'
               order by 1)
  -- 7. ไม่มี policy ให้ anon / PUBLIC
  union all select 13, 'policy_anon_public',
         array(select schemaname || '.' || tablename || '.' || policyname
                 from pg_catalog.pg_policies
                where schemaname in ('public', 'private') and roles && array['anon', 'public']::name[]
                order by 1)
  -- 8. สิทธิ์ตาราง: anon ไม่มีเลย, authenticated เขียนตรงไม่ได้ (เขียนผ่าน RPC เท่านั้น)
  union all select 14, 'table_privs_anon',
         array(select rel || ':' || priv from rels
                cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) priv
                where has_table_privilege('anon', oid, priv) order by 1)
  union all select 15, 'table_write_authenticated',
         array(select rel || ':' || priv from rels
                cross join unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) priv
                where has_table_privilege('authenticated', oid, priv) order by 1)
  -- view ที่ผู้ใช้อ่านได้ต้องเป็น security_invoker (ไม่งั้นข้าม RLS ด้วยสิทธิ์เจ้าของ)
  union all select 16, 'views_bypass_rls',
         array(select rel from rels
                where relkind in ('v', 'm')
                  and (has_table_privilege('authenticated', oid, 'SELECT') or has_table_privilege('anon', oid, 'SELECT'))
                  and not coalesce(reloptions @> array['security_invoker=true'], false)
                order by 1)
  union all select 17, 'schema_private_usage',
         array(select r from unnest(array['anon', 'authenticated', 'public']) r
                where has_schema_privilege(r, 'private', 'USAGE'))
  -- 9. Supabase Storage ไม่ใช้ — ต้องไม่มี bucket สาธารณะ (ไฟล์อยู่ B2 แบบ private)
  union all select 18, 'storage_public_buckets',
         array(select id from storage.buckets where public order by 1)
  -- 10. allow_test_logins (dev เปิดได้ตามแบบ · prod ต้องไม่มี) — แสดงค่าเสมอ ผู้เรียกตัดสินตามสภาพแวดล้อม
  union all select 19, 'allow_test_logins_on',
         array(select key || '=' || value from private.settings where key = 'allow_test_logins' and value = 'on')
)
select ord, name as check, cardinality(bad) = 0 as ok, cardinality(bad) as n,
       array_to_string(bad[1:20], ', ') as detail
  from checks
 order by ord
