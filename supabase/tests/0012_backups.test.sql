-- ทดสอบ 0012_backups: ฟังก์ชันสำรองเรียกได้เฉพาะ postgres (ก) เริ่มรอบ/ธง/รอบค้าง (ข) manifest (ค) RLS (ง)
-- และการปิด trigger ชั่วคราวด้วย session_replication_role สำหรับขั้นกู้ version_id (จ)
-- ทั้งไฟล์รันแบบ REPEATABLE READ เหมือน session A ของ backup.sh (backup_record_manifest บังคับ — กรณี READ COMMITTED
-- อยู่ใน 0012_backups_snapshot.test.sql) — ข้อมูลสมมติทั้งหมด (อีเมล @example.com) และ rollback ตอนจบ
begin isolation level repeatable read;
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

select plan(54);

-- เริ่มจากสภาพว่าง (บน kemi-dev อาจมีรอบจริงค้าง — ย้อนกลับตอนจบ)
delete from private.maintenance_locks where name = 'backup';
update public.backup_runs set status = 'failed', finished_at = clock_timestamp() where kind = 'backup' and status = 'running';
create temp table runs (label text primary key, id uuid) on commit drop;

-- ---------------------------------------------------------------------------
-- โครงสร้างและสิทธิ์ (ก, ง)
-- ---------------------------------------------------------------------------
select has_table('public', 'backup_runs', 'มี public.backup_runs');
select has_table('private', 'backup_manifests', 'มี private.backup_manifests (ไม่อยู่ใน schema ที่ Data API เปิด)');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.backup_runs'::regclass, 'private.backup_manifests'::regclass)),
  'ทั้ง 2 ตารางเปิด RLS');
select policies_are('public', 'backup_runs', array['backup_runs_select'], 'backup_runs มีเฉพาะ policy อ่าน');
select is_empty(
  $$ select format('%s %s %s', v.r, v.t, p)
       from (values ('anon', 'public.backup_runs'), ('authenticated', 'public.backup_runs'),
                    ('anon', 'private.backup_manifests'), ('authenticated', 'private.backup_manifests'),
                    ('service_role', 'private.backup_manifests')) v(r, t),
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege(v.r, v.t, p)
     union all
     select format('%s %s SELECT', r, t)
       from (values ('anon', 'public.backup_runs'), ('anon', 'private.backup_manifests'),
                    ('authenticated', 'private.backup_manifests'), ('service_role', 'private.backup_manifests')) v(r, t)
      where has_table_privilege(r, t, 'SELECT') $$,
  'GRANT SELECT เฉพาะ backup_runs ให้ authenticated — manifest ไม่มีใครอ่าน/เขียนผ่าน API');
select ok(has_table_privilege('authenticated', 'public.backup_runs', 'SELECT'), 'authenticated มี SELECT บน backup_runs (คัดด้วย RLS)');
select is_empty(
  $$ select c.conname from pg_constraint c
      where c.conrelid = 'private.backup_manifests'::regclass and c.contype = 'f'
        and c.confrelid = 'public.assets'::regclass $$,
  'manifest ไม่ FK ไป assets (asset ถูกลบได้แต่ manifest ยังต้องใช้ 7 วัน)');
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.backup_start()', 'private.backup_running_run(uuid)', 'private.backup_record_manifest(uuid)',
                         'private.backup_finish(uuid,boolean,text,integer,bigint,integer,text)', 'private.backup_release_lock()',
                         'private.backup_record_restore_test(boolean,text,integer,text)', 'private.backup_prune_manifests()']) f,
            unnest(array['public', 'anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE')
     union all
     select format('postgres ขาด %s', f)
       from unnest(array['private.backup_start()', 'private.backup_record_manifest(uuid)', 'private.backup_release_lock()']) f
      where not has_function_privilege('postgres', f, 'EXECUTE') $$,
  'ฟังก์ชันสำรองเรียกได้เฉพาะ postgres (anon/authenticated/service_role/PUBLIC ไม่ได้)');
select ok(
  has_function_privilege('authenticated', 'private.is_admin()', 'EXECUTE')
  and not has_function_privilege('anon', 'private.is_admin()', 'EXECUTE'),
  'is_admin: authenticated เรียกได้ (ใช้ใน policy) anon ไม่ได้');

-- ---------------------------------------------------------------------------
-- ข: เริ่มรอบ = ธง 2 ชม. + รอบ running ใน transaction เดียว; รอบซ้อน; รอบค้าง
-- ---------------------------------------------------------------------------
insert into runs values ('r1', private.backup_start());
select is((select status from public.backup_runs where id = (select id from runs where label = 'r1')), 'running',
  'เริ่มรอบ: สร้าง backup_runs สถานะ running');
select is((select expires_at - acquired_at from private.maintenance_locks where name = 'backup'), interval '2 hours',
  'เริ่มรอบ: ตั้งธงหยุดงานลบไฟล์หมดอายุใน 2 ชั่วโมง');
select throws_ok($$ select private.backup_start() $$, 'P0001', 'backup_in_progress',
  'มีรอบ running ที่ธงยังไม่หมดอายุ → backup_in_progress');
update private.maintenance_locks
   set acquired_at = clock_timestamp() - interval '3 hours', expires_at = clock_timestamp() - interval '1 hour'
 where name = 'backup';
insert into runs values ('r2', private.backup_start());
select results_eq(
  $$ select status, finished_at is not null, detail like 'หยุดกลางทาง%' from public.backup_runs where id = (select id from runs where label = 'r1') $$,
  $$ values ('failed', true, true) $$,
  'รอบ running ที่ธงหมดอายุแล้ว (Actions ตายกลางทาง) ถูกปิดเป็น failed ตอนเริ่มรอบใหม่');
select ok((select expires_at > clock_timestamp() + interval '119 minutes' from private.maintenance_locks where name = 'backup'),
  'รอบใหม่ตั้งธงใหม่');
select is((select count(*)::integer from public.backup_runs where kind = 'backup' and status = 'running'), 1,
  'มีรอบ running ได้ทีละรอบ');

-- ---------------------------------------------------------------------------
-- ค: manifest จาก assets สถานะ ready ใน snapshot เดียวกับ dump
-- ---------------------------------------------------------------------------
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role) values
  ('3d000000-0000-4000-8000-000000000001', '2d000000-0000-4000-8000-000000000001', 'google', 'bk-1', 'admin12@example.com', 'admin');
insert into public.teachers (id, display_name) values ('1d000000-0000-4000-8000-000000000001', 'ครูทดสอบสำรอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3d000000-0000-4000-8000-000000000002', '2d000000-0000-4000-8000-000000000002', 'google', 'bk-2', 'teacher12@example.com', 'teacher', '1d000000-0000-4000-8000-000000000001'),
  ('3d000000-0000-4000-8000-000000000003', '2d000000-0000-4000-8000-000000000003', 'google', 'bk-3', 'student12@example.com', 'student', null);
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ad000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'charm', 'staging/t12/1', 'sv-1', 'files/t12/1.png', 'image/png', 111, '1.png'),
  ('ad000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'charm', 'staging/t12/2', 'sv-2', 'files/t12/2.png', 'image/png', 222, '2.png'),
  ('ad000000-0000-4000-8000-000000000003', '3d000000-0000-4000-8000-000000000001', 'charm', 'staging/t12/3', 'sv-3', 'files/t12/3.png', 'image/png', 333, '3.png'),
  ('ad000000-0000-4000-8000-000000000004', '3d000000-0000-4000-8000-000000000001', 'charm', 'staging/t12/4', 'sv-4', 'files/t12/4.png', 'image/png', 444, '4.png'),
  ('ad000000-0000-4000-8000-000000000005', '3d000000-0000-4000-8000-000000000001', 'charm', 'staging/t12/5', 'sv-5', 'files/t12/5.png', 'image/png', 555, '5.png');
update public.assets set status = 'ready', version_id = 'v-' || right(id::text, 1), checksum = 'etag-' || right(id::text, 1), ready_at = clock_timestamp()
 where id in ('ad000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000002',
              'ad000000-0000-4000-8000-000000000003', 'ad000000-0000-4000-8000-000000000005');
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = 'ad000000-0000-4000-8000-000000000005';
-- 1–3 ready · 4 copying · 5 deleting

create temp table rec on commit drop as select private.backup_record_manifest((select id from runs where label = 'r2')) as res;
select is((select res from rec),
  (select jsonb_build_object('file_count', count(*)::integer, 'total_bytes', coalesce(sum(size_bytes), 0)::bigint)
     from public.assets where status = 'ready'),
  'บันทึก manifest: ทุก asset สถานะ ready คืนจำนวนและขนาดรวม');
select set_eq(
  $$ select final_key from private.backup_manifests
      where run_id = (select id from runs where label = 'r2') and final_key like 'files/t12/%' $$,
  array['files/t12/1.png', 'files/t12/2.png', 'files/t12/3.png'],
  'manifest มีเฉพาะไฟล์ ready (ไม่รวม copying ที่ยังไม่เสร็จ และ deleting ที่กำลังลบ)');
select results_eq(
  $$ select version_id, size_bytes, checksum from private.backup_manifests
      where run_id = (select id from runs where label = 'r2') and final_key = 'files/t12/2.png' $$,
  $$ values ('v-2', 222::bigint, 'etag-2') $$,
  'manifest เก็บ version_id ขนาด และ checksum ของไฟล์');
select throws_ok($$ select private.backup_record_manifest((select id from runs where label = 'r2')) $$,
  'P0001', 'manifest_recorded', 'บันทึก manifest ของรอบเดิมซ้ำไม่ได้');
select throws_ok($$ select private.backup_record_manifest('00000000-0000-4000-8000-000000000000') $$,
  'P0001', 'backup_not_running', 'รอบที่ไม่มีอยู่บันทึก manifest ไม่ได้');
select throws_ok($$ select private.backup_record_manifest((select id from runs where label = 'r1')) $$,
  'P0001', 'backup_not_running', 'รอบที่ปิดแล้ว (failed) บันทึก manifest ไม่ได้');
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = 'ad000000-0000-4000-8000-000000000003';
delete from public.assets where id = 'ad000000-0000-4000-8000-000000000003';
select ok(exists (select 1 from private.backup_manifests
                   where run_id = (select id from runs where label = 'r2') and final_key = 'files/t12/3.png'),
  'ลบ asset ออกจากระบบแล้ว แถว manifest ยังอยู่');

-- จบรอบ
select throws_ok(
  $$ select private.backup_finish((select id from runs where label = 'r2'), true, 'runs/2026-10-04T0230', 1, 1, 0, null) $$,
  'P0001', 'manifest_mismatch', 'จบรอบสำเร็จ: จำนวน/ขนาดที่ตรวจได้ต้องตรงกับ manifest');
select throws_ok(
  $$ select private.backup_finish((select id from runs where label = 'r2'), true, null,
       ((select res from rec) ->> 'file_count')::integer, ((select res from rec) ->> 'total_bytes')::bigint, 0, null) $$,
  '23514', null, 'จบรอบสำเร็จต้องมีชื่อจุดกู้คืน (dump_name)');
select lives_ok(
  $$ select private.backup_finish((select id from runs where label = 'r2'), true, 'runs/2026-10-04T0230',
       ((select res from rec) ->> 'file_count')::integer, ((select res from rec) ->> 'total_bytes')::bigint, 2,
       'ตรวจครบ: cryptcheck ไฟล์ใหม่ 2 ไฟล์ผ่าน') $$,
  'จบรอบสำเร็จพร้อมจำนวน ขนาด ไฟล์ใหม่ และผลตรวจ');
select results_eq(
  $$ select status, finished_at is not null, dump_name, new_file_count, detail
       from public.backup_runs where id = (select id from runs where label = 'r2') $$,
  $$ values ('succeeded', true, 'runs/2026-10-04T0230', 2, 'ตรวจครบ: cryptcheck ไฟล์ใหม่ 2 ไฟล์ผ่าน') $$,
  'บันทึกผลรอบสำเร็จครบ');
select throws_ok($$ select private.backup_finish((select id from runs where label = 'r2'), false) $$,
  'P0001', 'backup_not_running', 'จบรอบที่จบแล้วซ้ำไม่ได้');
select throws_ok($$ select private.backup_record_manifest((select id from runs where label = 'r2')) $$,
  'P0001', 'backup_not_running', 'รอบที่จบแล้วบันทึก manifest เพิ่มไม่ได้');
select ok(exists (select 1 from private.maintenance_locks where name = 'backup'),
  'จบรอบแล้วธงยังอยู่จนกว่าจะเรียกปลดล็อก');
select is(private.backup_release_lock(), true, 'ปลดล็อกหลังรอบสำเร็จ');
select ok(not exists (select 1 from private.maintenance_locks where name = 'backup'), 'ธงหายแล้ว (งานลบไฟล์ทำต่อได้)');
select is(private.backup_release_lock(), false, 'ปลดล็อกซ้ำได้ (ไม่มีธงแล้ว)');

-- รอบล้มเหลว: บันทึกสาเหตุแล้วปลดล็อกได้เหมือนกัน
insert into runs values ('r3', private.backup_start());
select lives_ok($$ select private.backup_finish((select id from runs where label = 'r3'), false, null, null, null, null, 'rclone copy ล้มเหลว') $$,
  'จบรอบแบบล้มเหลวพร้อมสาเหตุ');
select results_eq(
  $$ select status, finished_at is not null, detail from public.backup_runs where id = (select id from runs where label = 'r3') $$,
  $$ values ('failed', true, 'rclone copy ล้มเหลว') $$,
  'บันทึกรอบล้มเหลว');
select is(private.backup_release_lock(), true, 'ปลดล็อกหลังรอบล้มเหลว');

-- ผลทดสอบกู้คืน
insert into runs values ('t1', private.backup_record_restore_test(true, 'runs/2026-10-04T0230', 50, 'ไฟล์ตัวอย่าง 50 ไฟล์ checksum ตรง'));
select results_eq(
  $$ select kind, status, finished_at = started_at, dump_name, file_count from public.backup_runs where id = (select id from runs where label = 't1') $$,
  $$ values ('restore_test', 'succeeded', true, 'runs/2026-10-04T0230', 50) $$,
  'บันทึกผลทดสอบกู้คืน (จุดกู้คืน จำนวนไฟล์ที่ตรวจ)');
select throws_ok($$ select private.backup_record_restore_test(false, 'runs/x', -1) $$,
  '23514', null, 'จำนวนไฟล์ที่ตรวจติดลบไม่ได้');

-- ล้าง manifest: รอบเก่ากว่า 8 วันและรอบที่ล้มเหลว (r4) ถูกล้าง รอบสำเร็จล่าสุด (r5) อยู่ต่อ
create temp table rec5 (res jsonb) on commit drop;
do $do$
declare
  v_r4 uuid;
  v_r5 uuid;
  v_res jsonb;
begin
  v_r4 := private.backup_start();
  insert into runs values ('r4', v_r4);
  perform private.backup_record_manifest(v_r4);
  perform private.backup_finish(v_r4, false, null, null, null, null, 'ตรวจไม่ครบ');
  perform private.backup_release_lock();
  v_r5 := private.backup_start();
  insert into runs values ('r5', v_r5);
  v_res := private.backup_record_manifest(v_r5);
  insert into rec5 values (v_res);
  perform private.backup_finish(v_r5, true, 'runs/2026-10-04T1430', (v_res ->> 'file_count')::integer,
                                (v_res ->> 'total_bytes')::bigint, 0, 'ตรวจครบ');
  perform private.backup_release_lock();
end
$do$;
update public.backup_runs set started_at = clock_timestamp() - interval '9 days', finished_at = clock_timestamp() - interval '9 days' + interval '5 minutes'
 where id = (select id from runs where label = 'r2');
create temp table expected_prune on commit drop as
  select count(*)::integer as n from private.backup_manifests
   where run_id in (select id from runs where label in ('r2', 'r4'));
select is(private.backup_prune_manifests(), (select n from expected_prune),
  'ล้าง manifest ของรอบที่เริ่มเกิน 8 วันและรอบที่ล้มเหลว');
select is_empty($$ select 1 from private.backup_manifests where run_id in (select id from runs where label in ('r2', 'r4')) $$,
  'manifest ของรอบเก่าและรอบล้มเหลวหมดแล้ว');
select is((select count(*)::integer from private.backup_manifests where run_id = (select id from runs where label = 'r5')),
  ((select res from rec5) ->> 'file_count')::integer, 'manifest ของรอบสำเร็จล่าสุดยังอยู่ครบ');
select ok(exists (select 1 from public.backup_runs where id = (select id from runs where label = 'r2')),
  'แถว backup_runs ของรอบเก่ายังอยู่เป็นประวัติ');

-- ---------------------------------------------------------------------------
-- ง: RLS — ผู้ดูแลอ่าน backup_runs ได้ ครูและนักเรียนไม่เห็น manifest ไม่มีใครอ่าน
-- ---------------------------------------------------------------------------
grant select on runs to authenticated;
set local role anon;
select throws_ok($$ select id from public.backup_runs $$, '42501', null, 'anon อ่าน backup_runs ไม่ได้');
set local role authenticated;
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is((select count(*)::integer from public.backup_runs where id in (select id from runs)), 6,
  'ผู้ดูแลเห็นรอบสำรองและผลทดสอบกู้คืน (แผงสำรองใน D01)');
select throws_ok($$ select final_key from private.backup_manifests $$, '42501', null, 'ผู้ดูแลก็อ่าน manifest ผ่าน API ไม่ได้');
select throws_ok($$ select private.backup_start() $$, '42501', null, 'ผู้ดูแลเรียกฟังก์ชันสำรองผ่าน API ไม่ได้');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is_empty($$ select id from public.backup_runs $$, 'ครูไม่เห็น backup_runs');
select throws_ok($$ insert into public.backup_runs (kind, status) values ('backup', 'running') $$, '42501', null,
  'ครูเขียน backup_runs ตรงไม่ได้');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is_empty($$ select id from public.backup_runs $$, 'นักเรียนไม่เห็น backup_runs');
select throws_ok($$ select private.backup_release_lock() $$, '42501', null, 'นักเรียนปลดธงไม่ได้');

-- ---------------------------------------------------------------------------
-- จ: ขั้นกู้ version_id (TECHNICAL_DESIGN ส่วน 12 ข้อ 3) — ปิด trigger เฉพาะช่วงคำสั่งอัปเดตแล้วเปิดกลับ
-- ---------------------------------------------------------------------------
set local role postgres;
select throws_ok($$ update public.assets set version_id = 'v-restored' where id = 'ad000000-0000-4000-8000-000000000001' $$,
  'P0001', 'immutable_field', 'ปกติ trigger กันการแก้ version_id ของไฟล์ ready');
set local session_replication_role = replica;
select is(current_setting('session_replication_role'), 'replica', 'postgres ตั้ง session_replication_role = replica ได้');
select lives_ok($$ update public.assets set version_id = 'v-restored' where id = 'ad000000-0000-4000-8000-000000000001' $$,
  'ระหว่าง replica อัปเดต version_id ที่กู้ใหม่ได้');
set local session_replication_role = origin;
select is((select version_id from public.assets where id = 'ad000000-0000-4000-8000-000000000001'), 'v-restored',
  'version_id เป็นค่าใหม่');
select throws_ok($$ update public.assets set version_id = 'v-again' where id = 'ad000000-0000-4000-8000-000000000001' $$,
  'P0001', 'immutable_field', 'ตั้งกลับเป็น origin แล้ว trigger กันเหมือนเดิม');

select * from finish();
rollback;
