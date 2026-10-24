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

select plan(11);

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
  ('public.join_classroom(text)'),
  ('public.my_classrooms()'),
  ('public.classroom_view(uuid)'),
  ('public.roster_overview(boolean)'),
  ('public.rebind_preview(uuid,text,boolean)'),
  ('public.rebind_student(uuid,text,boolean)'),
  ('public.unbind_student(uuid,boolean)'),
  ('public.admin_teachers()'),
  ('public.admin_add_teacher(text,uuid,text)'),
  ('public.admin_remove_teacher(uuid)'),
  -- 0010_posts
  ('private.post_access(uuid)'),                                    -- ใช้ใน RLS policy
  -- 0011_files
  ('private.can_read_solution(uuid)'),                              -- ใช้ใน RLS policy
  -- 0012_backups
  ('private.is_admin()'),                                           -- ใช้ใน RLS policy
  -- 0014_post_rpcs
  ('public.create_post(uuid,jsonb,uuid,boolean)'),
  -- 0015_post_update
  ('public.update_post(uuid,jsonb,integer,uuid,boolean)'),
  -- 0016_upload_batch
  ('public.create_upload_batch(text,uuid,uuid,jsonb,uuid,boolean)'),
  -- 0017_upload_complete (ยืนยันเจ้าของ batch ด้วย JWT ของผู้ใช้ — อ่านอย่างเดียว)
  ('public.upload_complete_target(uuid,integer)'),
  -- 0018_files_sign (คืนเฉพาะ id ที่เปิดได้ + เพดานครั้ง — ไม่คืน key/เวอร์ชัน)
  ('public.authorize_files(uuid[])'),
  -- 0020_submissions
  ('private.can_read_submission(uuid)'),                            -- ใช้ใน RLS policy
  ('public.submit_assignment(uuid,uuid[],integer,uuid)'),
  -- 0021_submission_status (อ่านสถานะงานของนักเรียน)
  ('public.submission_status(uuid)'),
  ('public.my_work(uuid)'),
  -- 0022_teacher_work (ครู/ผู้ดูแลอ่านยอดและรายชื่อสถานะการส่ง)
  ('public.teacher_work_summary(uuid)'),
  ('public.teacher_submission_list(uuid)'),
  -- 0023_jobs (ยอดพื้นที่ทุกบทบาท — นักเรียนเห็นแค่ระดับ; ตัวนับ B2 เฉพาะผู้ดูแล)
  ('public.storage_status()'),
  ('public.admin_b2_usage()'),
  -- 0025_grading (ครู/ผู้ดูแลในโหมดผู้ดูแลบันทึกผลตรวจ)
  ('public.grade_submission(uuid,integer,boolean,integer,text,integer,integer,uuid,boolean)'),
  -- 0027_feedback (เปิดสิทธิ์แก้ของครู + ความคิดเห็นส่วนตัวทั้งสองฝ่าย)
  ('public.open_revision_permission(uuid,uuid,boolean)'),
  ('public.post_comment(uuid,uuid,text,uuid,boolean)'),
  ('public.retract_comment(uuid,boolean)'),
  -- 0028_intake (ครู/ผู้ดูแล: ดูผลก่อนเปลี่ยนกำหนดส่ง, เปลี่ยนกำหนดส่ง, ปิดรับ)
  ('public.preview_due_change(uuid,timestamp with time zone)'),
  ('public.change_due(uuid,timestamp with time zone,uuid[],uuid[],uuid,boolean)'),
  ('public.close_assignment(uuid,timestamp with time zone,uuid,boolean)'),
  -- 0029_solutions (ครู/ผู้ดูแล: บันทึกและเผยแพร่เฉลย)
  ('public.save_solution(uuid,text,uuid[],integer,uuid,boolean)'),
  ('public.publish_solution(uuid,integer,uuid,boolean)'),
  -- 0030_reopen (ครู/ผู้ดูแล: เปิดรับอีกครั้ง / เปลี่ยนหรือยกเลิกเวลาปิดรับ)
  ('public.reopen_assignment(uuid,timestamp with time zone,uuid,boolean)'),
  -- 0031_comment_thread (อ่านช่องความคิดเห็นพร้อมชื่อผู้ส่งและสิทธิ์เขียนของผู้เรียก)
  ('public.comment_thread(uuid,uuid)'),
  -- 0032_grade_table (ครู/ผู้ดูแลอ่านตารางคะแนนของห้อง)
  ('public.teacher_grade_table(uuid)'),
  -- 0033_delete_post (ครู/ผู้ดูแล: ดูยอดก่อนลบ, ลบการบ้าน/ประกาศแบบ cascade)
  ('public.post_delete_preview(uuid)'),
  ('public.delete_post(uuid,jsonb,uuid,boolean)'),
  -- 0036_wallet_ops (นักเรียน: เอฟเฟกต์ได้รับโทเคน · ครู/ผู้ดูแล: ปรับยอดมือ)
  ('public.reward_effects()'),
  ('public.mark_reward_effect_seen(uuid[])'),
  ('public.wallet_adjust(uuid,integer,integer,uuid,boolean)'),
  -- 0037_draw (นักเรียน: อัตราสุ่มจริง, สุ่ม, เลือกชิ้นที่แสดงข้างชื่อ)
  ('public.get_draw_options()'),
  ('public.draw_charm(text,uuid)'),
  ('public.set_equipment(uuid)'),
  -- 0038_collection (นักเรียน: ตู้สะสมส่วนตัว)
  ('public.my_collection()'),
  -- 0040_charm_admin (ครู/ผู้ดูแล: T06 แคตตาล็อก อัตรา เพิ่ม/แก้เครื่องราง)
  ('public.charm_catalog(boolean)'),
  ('public.save_rarity_weights(jsonb,text,boolean)'),
  ('public.save_charm(jsonb,integer,uuid,boolean)'),
  -- 0041_terms (ครู/ผู้ดูแล: เริ่มภาคเรียนใหม่ / จบภาคเรียนโดยไม่เปิดเทอมใหม่)
  ('public.terms_start(text,uuid,uuid,boolean)'),
  ('public.terms_end(uuid,uuid,boolean)'),
  -- 0042_term_overview (ครู/ผู้ดูแล: ข้อมูลหน้า T07)
  ('public.term_overview(boolean)'),
  -- 0043_notifications (นักเรียน/ครู: กระดิ่งของตัวเอง)
  ('public.my_notifications(timestamptz,integer)'),
  ('public.unread_notification_count()'),
  ('public.mark_notifications_read(uuid[])'),
  -- 0050_storage_threshold (ผู้ดูแล: ผลเทียบยอดพื้นที่ล่าสุดใน D01)
  ('public.admin_storage_reconcile()'),
  -- 0051_admin_jobs (ผู้ดูแล: งานเบื้องหลังที่ล้มเหลว + ลองใหม่ใน D01)
  ('public.admin_failed_jobs()'),
  ('public.admin_retry_job(bigint)'),
  -- 0053_admin_term_alert (ผู้ดูแล: ภาคเรียนเปิดค้างเกิน 6 เดือน)
  ('public.admin_term_alert()'),
  -- 0054_retention (ครู/ผู้ดูแล: รายการไฟล์ภาคเรียนเก่าสำหรับ ZIP + บันทึกว่าดาวน์โหลดครบ)
  ('public.export_files_page(uuid,uuid,integer,boolean)'),
  ('public.export_mark_downloaded(uuid,text,text,integer,bigint,boolean)');

-- RPC ที่เรียกได้เฉพาะ service_role (Edge Function) เพราะเขียนข้อมูลที่ระบบเชื่อ — ผู้ใช้เรียกผ่าน PostgREST ตรง ๆ ไม่ได้
-- **RPC ใหม่แบบนี้ต้องเพิ่มในรายการนี้ใน commit เดียวกับ migration**
create temp table expected_service_only (fn text primary key);
insert into expected_service_only values
  -- 0001_base (keep-alive ของ GitHub Actions)
  ('public.ping()'),
  -- 0017_upload_complete
  ('public.upload_complete_begin(uuid,uuid,integer,text,bigint,text,integer)'),
  ('public.upload_complete_finish(uuid,text,text)'),
  ('public.upload_complete_abort(uuid)'),
  ('public.record_b2_usage(text,integer,bigint,bigint)'),
  -- 0018_files_sign (ข้อมูลลงลายเซ็น + ตรวจและนับงบเปิดดูรายวัน)
  ('public.files_sign_begin(uuid[])'),
  -- 0023_jobs (ตัวทำงานเบื้องหลัง process-jobs)
  ('public.jobs_claim(integer)'),
  ('public.jobs_complete(bigint,text)'),
  ('public.jobs_fail(bigint,text)'),
  ('public.delete_asset_begin(bigint)'),
  ('public.delete_asset_finish(bigint)'),
  ('public.copying_stale(integer)'),
  ('public.sweep_copying_finish(uuid,text)'),
  ('public.jobs_maintenance()'),
  -- 0047_due_reminder_run (process-jobs: งานเตือน 24 ชม.)
  ('public.due_reminder_run(bigint)'),
  -- 0049_storage_reconcile (process-jobs: เทียบยอดพื้นที่ B2 รายวัน)
  ('public.storage_reconcile_start(bigint)'),
  ('public.storage_reconcile_step(bigint,jsonb,boolean)');

-- ฟังก์ชันของงานสำรอง/กู้คืน: เรียกได้เฉพาะ postgres ผ่าน psql (ops/backup.sh, ops/restore-test.sh) — ไม่ใช่ RPC
create temp table postgres_only (fn text primary key);
insert into postgres_only values
  ('private.backup_start()'),
  ('private.backup_running_run(uuid)'),
  ('private.backup_record_manifest(uuid)'),
  ('private.backup_finish(uuid,boolean,text,integer,bigint,integer,text)'),
  ('private.backup_release_lock()'),
  ('private.backup_record_restore_test(boolean,text,integer,text)'),
  -- 0013_backup_manifest (backup_prune_manifests ถูกแทนด้วยการล้างสองขั้น)
  ('private.backup_run_file_list(uuid)'),
  ('private.backup_new_files(uuid)'),
  ('private.backup_prune_eligible(uuid)'),
  ('private.backup_prune_candidates()'),
  ('private.backup_prune_confirm(text[])');

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
-- service_role (กุญแจของ Edge Function / ping) ไม่ต้องเรียกฟังก์ชันใน private — งานสำรองต่อด้วย postgres
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace = 'private'::regnamespace
        and has_function_privilege('service_role', p.oid, 'EXECUTE') $$,
  'service_role เรียกฟังก์ชันใน private ไม่ได้ (รวมฟังก์ชันสำรอง)'
);
select is_empty(
  $$ select format('%s %s', r, o.fn)
       from postgres_only o
       cross join unnest(array['public', 'anon', 'authenticated', 'service_role']) r
      where to_regprocedure(o.fn) is null
         or has_function_privilege(r, to_regprocedure(o.fn), 'EXECUTE')
         or not has_function_privilege('postgres', to_regprocedure(o.fn), 'EXECUTE') $$,
  'ฟังก์ชันสำรองมีอยู่จริงและเรียกได้เฉพาะ postgres'
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

select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and has_function_privilege('service_role', p.oid, 'EXECUTE')
        and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and not exists (select 1 from expected_service_only e where to_regprocedure(e.fn) = p.oid) $$,
  'ฟังก์ชันใน public ที่ service_role เรียกได้แต่ผู้ใช้เรียกไม่ได้ อยู่ในรายการ service_role ทั้งหมด'
);
select is_empty(
  $$ select format('%s %s', r, e.fn)
       from expected_service_only e
       cross join unnest(array['public', 'anon', 'authenticated']) r
      where to_regprocedure(e.fn) is null
         or has_function_privilege(r, to_regprocedure(e.fn), 'EXECUTE')
         or not has_function_privilege('service_role', to_regprocedure(e.fn), 'EXECUTE') $$,
  'RPC ของ service_role มีอยู่จริง service_role เรียกได้ และ PUBLIC/anon/authenticated เรียกไม่ได้'
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
