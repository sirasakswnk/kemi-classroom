-- ทดสอบ 0013_backup_manifest: manifest ไฟล์ละแถว (ข) รายการของรอบชั่วคราว (ค) รอบแรก/ล่าสุดขยับเฉพาะรอบสำเร็จ (ง)
-- ฟังก์ชันรายการไฟล์ของรอบ / ไฟล์ใหม่ / ล้างสองขั้น (จ) — รันแบบ REPEATABLE READ เหมือน session A ของ backup.sh
-- ข้อมูลสมมติทั้งหมด (key ใต้ files/t13/, อีเมล @example.com) และ rollback ตอนจบ
begin isolation level repeatable read;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(43);

-- เริ่มจากสภาพว่าง: ปิดรอบค้าง และพักรอบสำเร็จจริงบน kemi-dev (ถ้ามี) ไว้ใน transaction นี้ ให้ "รอบสำเร็จล่าสุด" เป็นของเทสต์
delete from private.maintenance_locks where name = 'backup';
update public.backup_runs set status = 'failed', finished_at = coalesce(finished_at, clock_timestamp())
 where kind = 'backup' and status in ('running', 'succeeded');
create temp table runs (label text primary key, id uuid) on commit drop;
create temp table rec (label text primary key, res jsonb) on commit drop;

-- ---------------------------------------------------------------------------
-- ข: โครงสร้าง
-- ---------------------------------------------------------------------------
select has_table('private', 'backup_manifests', 'มี private.backup_manifests (ไฟล์ละแถว)');
select has_table('private', 'backup_run_files', 'มี private.backup_run_files (รายการของรอบที่กำลังทำ)');
select columns_are('private', 'backup_manifests',
  array['final_key', 'version_id', 'size_bytes', 'checksum', 'first_run_id', 'last_run_id', 'prune_requested_at'],
  'manifest เก็บ final_key, version_id, ขนาด, checksum, รอบสำเร็จแรก/ล่าสุด (ไม่มี run_id ต่อแถว)');
select col_is_pk('private', 'backup_manifests', 'final_key', 'final_key ไม่ซ้ำ (ไฟล์ละแถว)');
select columns_are('private', 'backup_run_files', array['run_id', 'final_key', 'version_id', 'size_bytes', 'checksum'],
  'รายการของรอบ: ไฟล์ของรอบที่กำลังทำ');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('private.backup_manifests'::regclass, 'private.backup_run_files'::regclass)),
  'ทั้งสองตารางเปิด RLS');
select is_empty(
  $$ select c.conrelid::regclass::text from pg_constraint c
      where c.conrelid in ('private.backup_manifests'::regclass, 'private.backup_run_files'::regclass)
        and c.contype = 'f' and c.confrelid = 'public.assets'::regclass $$,
  'ไม่มี FK ไป assets (asset ถูกลบได้แต่สำเนาใน Drive ยังต้องเก็บ)');
select fk_ok('private', 'backup_manifests', 'first_run_id', 'public', 'backup_runs', 'id', 'รอบสำเร็จแรกอ้าง backup_runs');
select fk_ok('private', 'backup_manifests', 'last_run_id', 'public', 'backup_runs', 'id', 'รอบสำเร็จล่าสุดอ้าง backup_runs');
select is_empty(
  $$ select format('%s %s %s', r, t, p)
       from unnest(array['private.backup_manifests', 'private.backup_run_files']) t,
            unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege(r, t, p) $$,
  'ไม่มีบทบาทใดอ่าน/เขียนสองตารางนี้ผ่าน API');
select ok(to_regprocedure('private.backup_prune_manifests()') is null, 'ฟังก์ชันล้างแบบเดิมถูกแทนด้วยการล้างสองขั้น');

-- ข้อมูลสมมติ: ไฟล์ A B C พร้อมใช้
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role) values
  ('3e000000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'google', 'bm-1', 'admin13@example.com', 'admin');
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ae000000-0000-4000-8000-00000000000a', '3e000000-0000-4000-8000-000000000001', 'charm', 'staging/t13/a', 'sv-a', 'files/t13/a.png', 'image/png', 100, 'a.png'),
  ('ae000000-0000-4000-8000-00000000000b', '3e000000-0000-4000-8000-000000000001', 'charm', 'staging/t13/b', 'sv-b', 'files/t13/b.png', 'image/png', 200, 'b.png'),
  ('ae000000-0000-4000-8000-00000000000c', '3e000000-0000-4000-8000-000000000001', 'charm', 'staging/t13/c', 'sv-c', 'files/t13/c.png', 'image/png', 300, 'c.png');
update public.assets set status = 'ready', version_id = 'v-' || right(id::text, 1), checksum = 'etag-' || right(id::text, 1), ready_at = clock_timestamp()
 where final_key like 'files/t13/%';

create function pg_temp.fixture_rows() returns table (final_key text, first_label text, last_label text) language sql as $$
  select m.final_key, f.label, l.label
    from private.backup_manifests m
    left join runs f on f.id = m.first_run_id
    left join runs l on l.id = m.last_run_id
   where m.final_key like 'files/t13/%'
$$;
create function pg_temp.run_id(p_label text) returns uuid language sql as $$ select id from runs where label = p_label $$;

-- ---------------------------------------------------------------------------
-- รอบ r1 สำเร็จ: ทุกไฟล์เป็นไฟล์ใหม่ แล้วเข้า manifest ตอนจบรอบเท่านั้น
-- ---------------------------------------------------------------------------
insert into runs values ('r1', private.backup_start());
insert into rec values ('r1', private.backup_record_manifest(pg_temp.run_id('r1')));
select set_eq($$ select final_key from private.backup_run_file_list(pg_temp.run_id('r1')) where final_key like 'files/t13/%' $$,
  array['files/t13/a.png', 'files/t13/b.png', 'files/t13/c.png'], 'รายการไฟล์ของรอบ (เขียนเป็นไฟล์ manifest ขึ้น Drive)');
select results_eq(
  $$ select version_id, size_bytes, checksum from private.backup_run_file_list(pg_temp.run_id('r1')) where final_key = 'files/t13/b.png' $$,
  $$ values ('v-b', 200::bigint, 'etag-b') $$, 'รายการของรอบมี version_id ขนาด checksum');
select set_eq($$ select final_key from private.backup_new_files(pg_temp.run_id('r1')) where final_key like 'files/t13/%' $$,
  array['files/t13/a.png', 'files/t13/b.png', 'files/t13/c.png'], 'ยังไม่เคยมีรอบสำเร็จ: ทุกไฟล์เป็นไฟล์ใหม่ (ส่งให้ rclone copy)');
select is_empty($$ select final_key from pg_temp.fixture_rows() $$, 'ก่อนจบรอบ manifest ยังไม่มีไฟล์ของรอบนี้');
select lives_ok($$ select private.backup_finish(pg_temp.run_id('r1'), true, 'runs/r1', ((select res from rec where label = 'r1') ->> 'file_count')::integer,
                     ((select res from rec where label = 'r1') ->> 'total_bytes')::bigint, 3, 'ตรวจครบ') $$, 'จบรอบ r1 สำเร็จ');
select results_eq($$ select final_key, first_label, last_label from pg_temp.fixture_rows() order by final_key $$,
  $$ values ('files/t13/a.png', 'r1', 'r1'), ('files/t13/b.png', 'r1', 'r1'), ('files/t13/c.png', 'r1', 'r1') $$,
  'จบรอบสำเร็จ: ไฟล์ละแถว รอบแรก = รอบล่าสุด = r1');
select is_empty($$ select 1 from private.backup_run_files where run_id = pg_temp.run_id('r1') $$,
  'จบรอบสำเร็จแล้วรายการชั่วคราวของรอบถูกล้าง');
do $$ begin perform private.backup_release_lock(); end $$;

-- ---------------------------------------------------------------------------
-- รอบ r2 ล้มเหลว: เพิ่มไฟล์ D, C ถูกลบจากระบบ — manifest ต้องไม่ขยับ
-- ---------------------------------------------------------------------------
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ae000000-0000-4000-8000-00000000000d', '3e000000-0000-4000-8000-000000000001', 'charm', 'staging/t13/d', 'sv-d', 'files/t13/d.png', 'image/png', 400, 'd.png');
update public.assets set status = 'ready', version_id = 'v-d', checksum = 'etag-d', ready_at = clock_timestamp() where final_key = 'files/t13/d.png';
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where final_key = 'files/t13/c.png';
delete from public.assets where final_key = 'files/t13/c.png';
insert into runs values ('r2', private.backup_start());
insert into rec values ('r2', private.backup_record_manifest(pg_temp.run_id('r2')));
select set_eq($$ select final_key from private.backup_new_files(pg_temp.run_id('r2')) where final_key like 'files/t13/%' $$,
  array['files/t13/d.png'], 'ไฟล์ใหม่ = อยู่ในรอบนี้แต่ไม่เคยอยู่ในรอบสำเร็จใด (D)');
select lives_ok($$ select private.backup_finish(pg_temp.run_id('r2'), false, null, null, null, null, 'rclone ล้มเหลว') $$, 'จบรอบ r2 แบบล้มเหลว');
select results_eq($$ select final_key, first_label, last_label from pg_temp.fixture_rows() order by final_key $$,
  $$ values ('files/t13/a.png', 'r1', 'r1'), ('files/t13/b.png', 'r1', 'r1'), ('files/t13/c.png', 'r1', 'r1') $$,
  'รอบที่ล้มเหลวไม่ขยับรอบล่าสุด และไม่ทำให้ D ดูเหมือนสำรองแล้ว');
select is_empty($$ select 1 from private.backup_run_files where run_id = pg_temp.run_id('r2') $$,
  'จบรอบแบบล้มเหลวก็ล้างรายการชั่วคราว');
do $$ begin perform private.backup_release_lock(); end $$;

-- ---------------------------------------------------------------------------
-- รอบ r3 ค้าง → ถูกปิดตอนเริ่ม r4; r4 สำเร็จ
-- ---------------------------------------------------------------------------
insert into runs values ('r3', private.backup_start());
insert into rec values ('r3', private.backup_record_manifest(pg_temp.run_id('r3')));
select set_eq($$ select final_key from private.backup_new_files(pg_temp.run_id('r3')) where final_key like 'files/t13/%' $$,
  array['files/t13/d.png'], 'D ยังเป็นไฟล์ใหม่ (เคยอยู่แค่ในรอบที่ล้มเหลว)');
update private.maintenance_locks
   set acquired_at = clock_timestamp() - interval '3 hours', expires_at = clock_timestamp() - interval '1 hour'
 where name = 'backup';
insert into runs values ('r4', private.backup_start());
select is((select status from public.backup_runs where id = pg_temp.run_id('r3')), 'failed', 'รอบค้าง r3 ถูกปิดเป็น failed');
select is_empty($$ select 1 from private.backup_run_files where run_id = pg_temp.run_id('r3') $$,
  'รอบค้างที่ถูกปิดตอนเริ่มรอบใหม่: รายการชั่วคราวถูกล้าง');
select throws_ok($$ select * from private.backup_new_files(pg_temp.run_id('r3')) $$, 'P0001', 'backup_not_running',
  'ขอรายการไฟล์ของรอบที่ปิดแล้วไม่ได้');
insert into rec values ('r4', private.backup_record_manifest(pg_temp.run_id('r4')));
select throws_ok($$ select private.backup_finish(pg_temp.run_id('r4'), true, 'runs/r4', 1, 1, 0, null) $$,
  'P0001', 'manifest_mismatch', 'จบรอบสำเร็จยังเทียบยอดกับรายการของรอบ');
select lives_ok($$ select private.backup_finish(pg_temp.run_id('r4'), true, 'runs/r4', ((select res from rec where label = 'r4') ->> 'file_count')::integer,
                     ((select res from rec where label = 'r4') ->> 'total_bytes')::bigint, 1, 'ตรวจครบ') $$, 'จบรอบ r4 สำเร็จ');
select results_eq($$ select final_key, first_label, last_label from pg_temp.fixture_rows() order by final_key $$,
  $$ values ('files/t13/a.png', 'r1', 'r4'), ('files/t13/b.png', 'r1', 'r4'), ('files/t13/c.png', 'r1', 'r1'), ('files/t13/d.png', 'r4', 'r4') $$,
  'รอบสำเร็จ: ไฟล์เดิมเลื่อนรอบล่าสุด ไฟล์ใหม่ได้รอบแรก ไฟล์ที่ถูกลบจากระบบ (C) ยังอยู่ด้วยรอบล่าสุดเดิม');
do $$ begin perform private.backup_release_lock(); end $$;

-- ---------------------------------------------------------------------------
-- จ: ล้างสองขั้น — ขอรายการ → สคริปต์ลบจาก Drive → ยืนยันแล้วจึงลบแถว
-- ---------------------------------------------------------------------------
update public.backup_runs set started_at = clock_timestamp() - interval '10 days', finished_at = clock_timestamp() - interval '10 days' + interval '5 minutes'
 where id = pg_temp.run_id('r1');
select is(private.backup_prune_confirm(array['files/t13/c.png']), 0, 'ยืนยันลบแถวที่ยังไม่ได้ขอรายการไม่ได้ (ต้องลบจาก Drive ก่อน)');
select set_eq($$ select final_key from private.backup_prune_candidates() where final_key like 'files/t13/%' $$,
  array['files/t13/c.png'], 'ขั้นแรก: ไฟล์ที่รอบสำเร็จล่าสุดที่เห็นเก่ากว่า 8 วัน (C) — ไฟล์ที่ยังอยู่ในรอบล่าสุดไม่ถูกเสนอ');
select ok((select prune_requested_at is not null from private.backup_manifests where final_key = 'files/t13/c.png'),
  'ขั้นแรกทำเครื่องหมายแถวที่ส่งให้ไปลบจาก Drive');
select is(private.backup_prune_confirm(array['files/t13/c.png', 'files/t13/a.png', 'files/t13/none.png']), 1,
  'ขั้นสอง: ลบเฉพาะแถวที่ขอไว้และยังล้างได้ (A ยังอ้างอยู่ ไม่ถูกลบ)');
select set_eq($$ select final_key from pg_temp.fixture_rows() $$,
  array['files/t13/a.png', 'files/t13/b.png', 'files/t13/d.png'], 'หลังยืนยัน: C หายไป ไฟล์อื่นอยู่ครบ');
-- คำขอที่ค้างอยู่แต่ไม่เข้าเงื่อนไขแล้ว (เช่นคำขอเก่าหรือทำเครื่องหมายผิด) ขั้นสองต้องตรวจซ้ำ
update private.backup_manifests set prune_requested_at = clock_timestamp() where final_key = 'files/t13/a.png';
select is(private.backup_prune_confirm(array['files/t13/a.png']), 0,
  'ขั้นสองตรวจเงื่อนไขซ้ำ: แถวที่มีคำขอแต่ยังอยู่ในจุดกู้คืนไม่ถูกลบ');

-- จุดกู้คืนสุดท้ายต้องไม่ถูกล้าง แม้เก่ากว่า 8 วัน (สำรองล้มเหลวติดกันนาน)
update public.backup_runs set started_at = clock_timestamp() - interval '9 days', finished_at = clock_timestamp() - interval '9 days' + interval '5 minutes'
 where id = pg_temp.run_id('r4');
select is_empty($$ select final_key from private.backup_prune_candidates() where final_key like 'files/t13/%' $$,
  'ไฟล์ของรอบสำเร็จล่าสุดของระบบไม่ถูกเสนอให้ล้าง แม้รอบนั้นเก่ากว่า 8 วัน');
select is(private.backup_prune_confirm(array['files/t13/a.png', 'files/t13/b.png', 'files/t13/d.png']), 0,
  'ยืนยันลบไฟล์ของจุดกู้คืนสุดท้ายไม่ได้');

-- มีรอบสำเร็จใหม่ (r5) ที่เห็นเฉพาะ A → B และ D ไม่มีจุดกู้คืนใน 8 วันอ้างแล้ว
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where final_key in ('files/t13/b.png', 'files/t13/d.png');
delete from public.assets where final_key in ('files/t13/b.png', 'files/t13/d.png');
insert into runs values ('r5', private.backup_start());
insert into rec values ('r5', private.backup_record_manifest(pg_temp.run_id('r5')));
select lives_ok($$ select private.backup_finish(pg_temp.run_id('r5'), true, 'runs/r5', ((select res from rec where label = 'r5') ->> 'file_count')::integer,
                     ((select res from rec where label = 'r5') ->> 'total_bytes')::bigint, 0, 'ตรวจครบ') $$, 'จบรอบ r5 สำเร็จ');
select is((select prune_requested_at from private.backup_manifests where final_key = 'files/t13/a.png'), null::timestamptz,
  'ไฟล์ที่รอบสำเร็จใหม่เห็นอีกถูกยกเลิกคำขอล้าง');
do $$ begin perform private.backup_release_lock(); end $$;
select set_eq($$ select final_key from private.backup_prune_candidates() where final_key like 'files/t13/%' $$,
  array['files/t13/b.png', 'files/t13/d.png'], 'มีจุดกู้คืนใหม่แล้ว: ไฟล์ที่รอบล่าสุดของมันเก่ากว่า 8 วันถูกเสนอให้ล้าง');
select is(private.backup_prune_confirm(array['files/t13/b.png', 'files/t13/d.png']), 2, 'ยืนยันลบ B และ D');
select results_eq($$ select final_key, first_label, last_label from pg_temp.fixture_rows() $$,
  $$ values ('files/t13/a.png', 'r1', 'r5') $$, 'เหลือ A ที่ยังอยู่ในจุดกู้คืนล่าสุด');

-- ฉ: ยืนยันว่าไม่มีรายการชั่วคราวค้างหลังทุกรอบจบ
select is_empty($$ select 1 from private.backup_run_files where run_id in (select id from runs) $$,
  'ไม่มีรายการชั่วคราวค้างหลังทุกรอบจบ');

select * from finish();
rollback;
