-- ทดสอบ 0012_backups ส่วนที่ต้องรันแบบ READ COMMITTED: บันทึก manifest นอก snapshot ที่ export ให้ pg_dump ไม่ได้
-- (ไฟล์หลัก 0012_backups.test.sql รันแบบ REPEATABLE READ) — rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(2);

delete from private.maintenance_locks where name = 'backup';
update public.backup_runs set status = 'failed', finished_at = clock_timestamp() where kind = 'backup' and status = 'running';
create temp table runs on commit drop as select private.backup_start() as id;

select is(current_setting('transaction_isolation'), 'read committed', 'ไฟล์นี้รันแบบ READ COMMITTED');
select throws_ok($$ select private.backup_record_manifest((select id from runs)) $$, 'P0001', 'snapshot_required',
  'บันทึก manifest นอก REPEATABLE READ ไม่ได้ (manifest ต้องมาจาก snapshot เดียวกับ dump)');

select * from finish();
rollback;
