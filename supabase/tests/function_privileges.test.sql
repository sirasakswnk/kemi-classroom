-- รายชื่อฟังก์ชันที่แต่ละบทบาทเรียกได้ — TECHNICAL_BUILD_PLAN ส่วน 11
--
-- ทุกฟังก์ชันใน schema ของเรา (public, private) ทุก overload เทียบด้วย signature เต็ม (regprocedure)
-- สิทธิ์นับจาก has_function_privilege() จึงรวมสิทธิ์ที่ได้ผ่าน PUBLIC และการเป็นสมาชิก role
--
-- **ทุก RPC หรือฟังก์ชันใหม่ที่ GRANT ให้ authenticated ต้องเพิ่ม signature ในรายการข้างล่างใน commit เดียวกัน**
-- (CLAUDE.md ส่วน 6) — ฟังก์ชันที่เรียกได้แต่ไม่อยู่ในรายการ = เทสต์ล้ม
--
-- ไม่ตรวจ schema ที่ Supabase ดูแล (auth, extensions, storage, graphql, graphql_public, realtime, vault,
-- pgbouncer, supabase_functions, supabase_migrations, net, cron ฯลฯ) เพราะ:
--   - เราไม่สร้างหรือแก้ฟังก์ชันใน schema เหล่านั้น สิทธิ์เป็นไปตามการออกแบบของ Supabase และเปลี่ยนตามรุ่น
--   - บางตัวต้องให้ทุกบทบาทเรียกได้จึงจะทำงาน เช่น auth.uid() ที่ policy และ RPC ของเราใช้
--   - Data API เปิดเฉพาะ schema public (private ไม่เปิด แต่ EXECUTE ยังมีผลกับ RLS policy จึงตรวจ private ด้วย)
--   - pgTAP ที่ไฟล์ทดสอบติดตั้งชั่วคราวอยู่ใน extensions จึงไม่ปนในการตรวจนี้
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(7);

-- รายการที่ตั้งใจให้ authenticated เรียกได้ (เรียงตาม migration)
create temp table expected_authenticated (fn text primary key);
insert into expected_authenticated values
  -- 0002_accounts
  ('public.ensure_account()'),
  ('private.current_account()'),                                    -- ใช้ใน RLS policy
  -- 0003_roster
  ('private.is_teacher_or_admin()'),                                -- ใช้ใน RLS policy
  ('public.preview_roster_import(text,jsonb,boolean)'),
  ('public.commit_roster_import(text,jsonb,uuid,boolean)'),
  ('public.search_roster(text)'),
  ('public.claim_identity(uuid)'),
  ('private.current_student()'),
  ('private.is_member(uuid)'),
  ('private.can_teach_classroom(uuid)'),
  ('public.create_classroom(text,text,uuid,uuid,boolean)'),
  ('public.set_join_enabled(uuid,boolean,boolean)'),
  ('public.remove_member(uuid,uuid,boolean)'),
  ('public.lookup_classroom(text)'),
  ('public.join_classroom(text)');

-- ฟังก์ชันจริงทุกตัวใน public/private ที่บทบาทนั้นเรียกได้
-- เทียบด้วย OID (regprocedure) จึงแยก overload และไม่ขึ้นกับ search_path; fn ใช้แสดงผลแบบมีชื่อ schema
create temp view callable as
select r.role,
       p.oid,
       p.pronamespace::regnamespace::text || '.' || p.proname
         || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' as fn
  from pg_proc p
  cross join (values ('anon'), ('authenticated'), ('public')) r(role)
 where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
   and has_function_privilege(r.role, p.oid, 'EXECUTE');

select is_empty(
  $$ select fn from callable where role = 'anon' $$,
  'anon เรียกฟังก์ชันใน public/private ไม่ได้เลย'
);
select is_empty(
  $$ select fn from callable where role = 'public' $$,
  'PUBLIC ไม่มีสิทธิ์เรียกฟังก์ชันใน public/private'
);
select is_empty(
  $$ select c.fn from callable c
      where c.role = 'authenticated'
        and not exists (select 1 from expected_authenticated e where to_regprocedure(e.fn)::oid = c.oid) $$,
  'authenticated เรียกได้เฉพาะฟังก์ชันในรายการ (ไม่มีตัวเกิน รวมทุก overload)'
);
select is_empty(
  $$ select e.fn from expected_authenticated e
      where not exists (select 1 from callable c
                         where c.role = 'authenticated' and c.oid = to_regprocedure(e.fn)::oid) $$,
  'ทุกฟังก์ชันในรายการมีอยู่จริงและ authenticated ยังเรียกได้'
);
select is_empty(
  $$ select fn from expected_authenticated where to_regprocedure(fn) is null $$,
  'ทุกชื่อในรายการเป็น signature ที่มีอยู่จริง'
);

-- SECURITY DEFINER ทุกตัวต้องตั้ง search_path (กันการแทรกวัตถุใน schema ที่ค้นหา)
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
        and p.prosecdef
        and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%') $$,
  'ทุก SECURITY DEFINER ใน public/private ตั้ง search_path แล้ว'
);
-- ของเราเองต้องเป็น search_path ว่าง ('') ตาม CLAUDE.md ส่วน 5 (ยกเว้นฟังก์ชันของ Supabase)
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
        and p.prosecdef
        and p.proname <> 'rls_auto_enable'
        and not coalesce(p.proconfig @> array['search_path=""'], false) $$,
  'SECURITY DEFINER ของเราใช้ search_path = '''''
);

select * from finish();
rollback;
