-- ทดสอบ 0050_storage_threshold: แจ้งครูเมื่อพื้นที่ถึง 90% / เต็ม ครั้งเดียวต่อระดับ + ผลเทียบล่าสุดของ D01
-- ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
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
    execute format('grant execute on function %s to anon, authenticated, service_role', f);
  end loop;
end
$$;

select plan(27);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน · ผู้ดูแล 1 · เพดานที่ใช้ได้ 1,000,000,000 ไบต์ — คุมยอดด้วยค่าชดเชย (0049)
-- เทสต์นับแจ้งเตือนทั้งตาราง — ล้างของเดิมใน dev ก่อน (rollback ตอนจบคืนครบ)
-- ---------------------------------------------------------------------------
delete from public.notifications;
delete from public.storage_reconciliations;
insert into public.teachers (id, display_name) values
  ('15000000-0000-4000-8000-000000000001', 'ครูทดสอบพื้นที่หนึ่ง'),
  ('15000000-0000-4000-8000-000000000002', 'ครูทดสอบพื้นที่สอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('35000000-0000-4000-8000-000000000001', '25000000-0000-4000-8000-000000000001', 'google', 'st-1',
   'teacher50@example.com', 'teacher', '15000000-0000-4000-8000-000000000001'),
  ('35000000-0000-4000-8000-000000000003', '25000000-0000-4000-8000-000000000003', 'google', 'st-3',
   'admin50@example.com', 'admin', null);
update public.storage_settings
   set quota_bytes = 1050000000, hard_stop_margin_bytes = 50000000, teacher_warn_pct = 90, admin_warn_pct = 80,
       storage_offset_bytes = 0, notified_level = 0;

-- ตั้งยอดที่ใช้คิดโควตาเป็น p ไบต์ (ผ่านค่าชดเชย = ยอดที่มากกว่าจากผลเทียบ B2)
create function pg_temp.use(p bigint) returns void language plpgsql as $$
begin
  update public.storage_settings set storage_offset_bytes = 0;
  update public.storage_settings set storage_offset_bytes = greatest(p - private.storage_used_bytes(), 0);
end $$;
create function pg_temp.sent(p_level integer) returns integer language sql stable as
  $$ select count(*)::integer from public.notifications n
      where n.kind = 'storage_threshold' and n.level = p_level and n.read_at is null $$;
create function pg_temp.total() returns integer language sql stable as
  $$ select count(*)::integer from public.notifications $$;
create temp table teachers_n as select count(*)::integer as n from public.teachers;

-- ---------------------------------------------------------------------------
-- 1. ระดับ: เปอร์เซ็นต์คิดจาก quota − margin และยอดรวมค่าชดเชย
-- ---------------------------------------------------------------------------
select pg_temp.use(899999999);
select is(private.storage_threshold_check() ->> 'level', '0', 'ต่ำกว่า 90% ของ quota − margin → ระดับ 0');
select is(pg_temp.total(), 0, 'ยังไม่ถึงเกณฑ์ครู → ไม่แจ้ง (80% แจ้งผู้ดูแลในหน้า D01 เท่านั้น ไม่มีกระดิ่ง)');
select pg_temp.use(900000000);
select is(private.storage_threshold_check(),
          jsonb_build_object('level', 90, 'notified_before', 0, 'notified_after', 90, 'sent', (select n from teachers_n)),
  'ถึง 90% (นับค่าชดเชยจากผลเทียบ B2 = ยอดที่มากกว่า) → แจ้งครูทุกคน');
select is(pg_temp.sent(90), (select n from teachers_n), 'ครูแต่ละคนได้ 1 แถว');
select ok((select bool_and(n.recipient_teacher_id is not null and n.post_id is null and n.recipient_student_id is null)
             from public.notifications n where n.kind = 'storage_threshold'),
  'ผู้รับเป็นครู ไม่มีนักเรียน/โพสต์');
select is((select notified_level from public.storage_settings), 90, 'จำระดับที่แจ้งแล้ว');

-- ---------------------------------------------------------------------------
-- 2. ครั้งเดียวต่อระดับ
-- ---------------------------------------------------------------------------
update public.notifications set read_at = clock_timestamp() where kind = 'storage_threshold';
select is(private.storage_threshold_check() ->> 'sent', '0', 'ตรวจซ้ำที่ระดับเดิม → ไม่แจ้ง');
select pg_temp.use(950000000);
select is(private.storage_threshold_check() ->> 'sent', '0', 'ยังอยู่ในช่วง 90% → ไม่แจ้งซ้ำ');
select is(pg_temp.sent(90), 0, 'แถวเดิมยังอ่านแล้ว');

-- ---------------------------------------------------------------------------
-- 3. เต็ม (100% ของ quota − margin)
-- ---------------------------------------------------------------------------
select pg_temp.use(1000000000);
select is(private.storage_threshold_check() ->> 'level', '100', 'ยอด = เพดานที่ใช้ได้ → เต็ม');
select is(pg_temp.sent(100), (select n from teachers_n), 'แจ้ง “เต็ม” ครูทุกคน');
select is(pg_temp.total(), 2 * (select n from teachers_n), 'แถว 90% เดิมยังอยู่ + แถวเต็มใหม่');
select is(private.storage_threshold_check() ->> 'sent', '0', 'เต็มต่อเนื่อง → ไม่แจ้งซ้ำ');

-- ลดลงจากเต็มเหลือช่วง 90% → ไม่แจ้ง 90% ซ้ำ (เคยแจ้งแล้วและยังไม่ลดต่ำกว่า 90%)
update public.notifications set read_at = clock_timestamp() where kind = 'storage_threshold';
select pg_temp.use(950000000);
select is(private.storage_threshold_check(),
          '{"level": 90, "notified_before": 100, "notified_after": 90, "sent": 0}'::jsonb,
  'ลดจากเต็มมาอยู่ช่วง 90% → ลดระดับที่แจ้งแล้ว แต่ไม่แจ้ง 90% ซ้ำ');
select pg_temp.use(1000000000);
select is(private.storage_threshold_check() ->> 'sent', (select n from teachers_n)::text,
  'กลับมาเต็มอีกครั้ง → แจ้ง “เต็ม” ได้อีก');
select is(pg_temp.total(), 2 * (select n from teachers_n), 'แจ้งซ้ำใช้แถวเดิม (dedupe ต่อระดับต่อครู)');

-- ---------------------------------------------------------------------------
-- 4. ลดต่ำกว่าเกณฑ์ (ครูลบไฟล์เทอมเก่า) แล้วขึ้นใหม่ → แจ้งได้อีกครั้ง
-- ---------------------------------------------------------------------------
update public.notifications set read_at = clock_timestamp(), updated_at = clock_timestamp() - interval '1 day'
 where kind = 'storage_threshold';
select pg_temp.use(500000000);
select is(private.storage_threshold_check(),
          '{"level": 0, "notified_before": 100, "notified_after": 0, "sent": 0}'::jsonb,
  'ลดต่ำกว่า 90% → ล้างระดับที่แจ้งแล้ว ไม่แจ้งอะไร');
select is(pg_temp.sent(90) + pg_temp.sent(100), 0, 'ตอนลดลงไม่มีแจ้งเตือนใหม่');
select pg_temp.use(920000000);
select is(private.storage_threshold_check() ->> 'sent', (select n from teachers_n)::text,
  'ขึ้นถึง 90% อีกครั้ง → แจ้งได้อีก');
select ok((select bool_and(n.read_at is null and n.updated_at > clock_timestamp() - interval '1 minute')
             from public.notifications n where n.kind = 'storage_threshold' and n.level = 90),
  'แถว 90% เดิมกลับเป็นยังไม่อ่านและขึ้นบนสุดของกระดิ่ง');
select is(pg_temp.sent(100), 0, 'แถว “เต็ม” ไม่ถูกแตะ');

-- กระโดดจากต่ำกว่า 90% ไปเต็มเลย → แจ้งเฉพาะ “เต็ม”
update public.notifications set read_at = clock_timestamp() where kind = 'storage_threshold';
select pg_temp.use(100000000);
select private.storage_threshold_check();
select pg_temp.use(1000000000);
select private.storage_threshold_check();
select ok(pg_temp.sent(100) = (select n from teachers_n) and pg_temp.sent(90) = 0,
  'จากต่ำกว่า 90% ไปเต็มทันที → แจ้งเฉพาะ “เต็ม”');

-- ---------------------------------------------------------------------------
-- 5. cron · สิทธิ์ · ผลเทียบล่าสุดของ D01
-- ---------------------------------------------------------------------------
select is((select schedule from cron.job where jobname = 'kemi-storage-threshold'), '*/5 * * * *',
  'cron ตรวจเกณฑ์ทุก 5 นาที');
select ok(not has_function_privilege('authenticated', 'private.storage_threshold_check()', 'EXECUTE')
          and not has_function_privilege('service_role', 'private.storage_threshold_check()', 'EXECUTE'),
  'ตรวจเกณฑ์เรียกได้เฉพาะ postgres (cron)');

insert into public.storage_reconciliations (job_id, started_at, finished_at, b2_bytes, b2_versions, breakdown,
  db_assets_bytes, db_reserved_bytes, diff_bytes, offset_before_bytes, offset_after_bytes, exceeds_threshold, requests, runs)
values
  (null, clock_timestamp() - interval '2 days', clock_timestamp() - interval '2 days', 10, 1, '{}', 10, 0, 0, 0, 0, false, 1, 1),
  (null, clock_timestamp() - interval '1 hour', clock_timestamp() - interval '1 hour', 300000000, 9, '{}', 90000000, 10000000, 200000000, 0, 200000000, true, 1, 1);

set local role authenticated;
set local request.jwt.claims to '{"sub": "25000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok('select public.admin_storage_reconcile()', 'P0001', 'forbidden', 'ครูอ่านผลเทียบไม่ได้');
set local request.jwt.claims to '{"sub": "25000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.admin_storage_reconcile() - 'finished_at',
          '{"b2_bytes": 300000000, "db_bytes": 100000000, "diff_bytes": 200000000, "offset_bytes": 200000000, "exceeds_threshold": true}'::jsonb,
  'ผู้ดูแลได้ผลเทียบล่าสุด (ธงเกินเกณฑ์)');
set local role postgres;
delete from public.storage_reconciliations;
set local role authenticated;
select is(public.admin_storage_reconcile(), null, 'ยังไม่เคยเทียบ → null');

set local role postgres;
select * from finish();
rollback;
