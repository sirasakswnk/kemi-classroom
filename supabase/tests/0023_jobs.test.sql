-- ทดสอบ 0023_jobs: สิทธิ์ (service_role เท่านั้น), ดึงงาน/ลองใหม่/failed, delete_asset (maintenance lock, asset ที่ยังผูก),
-- sweeper copying, งานประจำ (batch หมดอายุ, กติกาเลือก asset กำพร้า, ล้างข้อมูลเก่า), storage_status/admin_b2_usage
-- สองตัวทำงานพร้อมกัน (SKIP LOCKED) ทดสอบจริงด้วยสองการเชื่อมต่อแยกไว้ในโน้ต P3-10 — ไฟล์นี้ตรวจเชิงโครงสร้าง
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

select plan(57);

-- ---------------------------------------------------------------------------
-- ก: สิทธิ์
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['public.jobs_claim(integer)', 'public.jobs_complete(bigint,text)', 'public.jobs_fail(bigint,text)',
                         'public.delete_asset_begin(bigint)', 'public.delete_asset_finish(bigint)',
                         'public.copying_stale(integer)', 'public.sweep_copying_finish(uuid,text)',
                         'public.jobs_maintenance()']) f,
            unnest(array['anon', 'authenticated']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'RPC ของตัวทำงานเบื้องหลังผู้ใช้เรียกไม่ได้');
select ok(has_function_privilege('service_role', 'public.jobs_claim(integer)', 'EXECUTE')
          and has_function_privilege('service_role', 'public.delete_asset_finish(bigint)', 'EXECUTE')
          and has_function_privilege('service_role', 'public.jobs_maintenance()', 'EXECUTE'),
  'service_role เรียกได้');
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.jobs_limits()', 'private.jobs_running(bigint)', 'private.jobs_defer(bigint,timestamp with time zone,text)',
                         'private.enqueue_delete_asset(public.assets,text)', 'private.jobs_has_work()']) f,
            unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยใน private ใช้ภายในเท่านั้น');
select ok((select position('for update skip locked' in pg_get_functiondef('public.jobs_claim(integer)'::regprocedure)) > 0),
  'jobs_claim ใช้ FOR UPDATE SKIP LOCKED (สองการเชื่อมต่อพร้อมกันทดสอบจริงแยกไว้)');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ---------------------------------------------------------------------------
delete from private.jobs;
delete from private.maintenance_locks;
insert into public.teachers (id, display_name) values ('1b100000-0000-4000-8000-000000000001', 'ครูงานเบื้องหลัง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3b100000-0000-4000-8000-000000000001', '2b100000-0000-4000-8000-000000000001', 'google', 'jb-1', 't23@example.com', 'teacher', '1b100000-0000-4000-8000-000000000001'),
  ('3b100000-0000-4000-8000-000000000002', '2b100000-0000-4000-8000-000000000002', 'google', 'jb-2', 'a23@example.com', 'admin', null),
  ('3b100000-0000-4000-8000-000000000003', '2b100000-0000-4000-8000-000000000003', 'google', 'jb-3', 's23@example.com', 'student', null);
insert into public.terms (id, name, status) values ('4b100000-0000-4000-8000-000000000001', 'ภาคทดสอบงานเบื้องหลัง', 'active');
insert into public.term_control (term_id) values ('4b100000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7b100000-0000-4000-8000-000000000001', '4b100000-0000-4000-8000-000000000001', '1b100000-0000-4000-8000-000000000001', 'ห้องงานเบื้องหลัง', 'ZZZZ72');
insert into public.posts (id, classroom_id, kind, title, body) values
  ('8b100000-0000-4000-8000-000000000001', '7b100000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ', 'x');

-- batch: b1 เปิดและยังไม่หมดอายุ · b2 เปิดแต่หมดอายุ 1 ชม. · b3 หมดอายุ 25 ชม. · b4 consumed หมดอายุ 25 ชม.
create function pg_temp.b(n integer) returns uuid language sql immutable as
  $$ select ('9b100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.f(n integer) returns uuid language sql immutable as
  $$ select ('bb100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, files, reserved_bytes, status, created_at, expires_at) values
  (pg_temp.b(1), '3b100000-0000-4000-8000-000000000001', 'post', '7b100000-0000-4000-8000-000000000001', '[{}]', 100, 'open', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour'),
  (pg_temp.b(2), '3b100000-0000-4000-8000-000000000001', 'post', '7b100000-0000-4000-8000-000000000001', '[{}]', 100, 'open', clock_timestamp() - interval '3 hours', clock_timestamp() - interval '1 hour'),
  (pg_temp.b(3), '3b100000-0000-4000-8000-000000000001', 'post', '7b100000-0000-4000-8000-000000000001', '[{}]', 100, 'open', clock_timestamp() - interval '27 hours', clock_timestamp() - interval '25 hours'),
  (pg_temp.b(4), '3b100000-0000-4000-8000-000000000001', 'post', '7b100000-0000-4000-8000-000000000001', '[{}]', 100, 'consumed', clock_timestamp() - interval '27 hours', clock_timestamp() - interval '25 hours');
-- asset: 1 ใน b1 · 2 ใน b2 · 3 ใน b3 (กำพร้า) · 4 ใน b4 ผูกกับโพสต์ · 5 ไม่มี batch พร้อมใช้ 25 ชม.ก่อน (กำพร้า)
--        6 ไม่มี batch พร้อมใช้ 1 ชม.ก่อน · 7 deleting พร้อมลบ · 8 deleting แต่ผูกอยู่ไม่ได้ (ทดสอบด้วยแถว ready ที่ใส่งานผิด)
--        9 copying ค้าง 20 นาที · 10 copying ค้าง 20 นาที (ไม่มีไฟล์ปลายทาง) · 11 copying เพิ่งเริ่ม
insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name, created_at)
select pg_temp.f(n), '3b100000-0000-4000-8000-000000000001', 'post',
       case n when 1 then pg_temp.b(1) when 2 then pg_temp.b(2) when 3 then pg_temp.b(3) when 4 then pg_temp.b(4) end,
       'staging/t23/' || n, 'sv' || n, 'files/t23/' || n || '.pdf', 'application/pdf', 1000 * n, 'f' || n || '.pdf',
       clock_timestamp() - case when n in (9, 10) then interval '20 minutes' else interval '1 minute' end
  from generate_series(1, 11) n;
update public.assets set status = 'ready', version_id = 'v' || substr(staging_key, 13), checksum = 'e',
       ready_at = clock_timestamp() - case when id = pg_temp.f(5) then interval '25 hours' else interval '1 hour' end
 where id in (select pg_temp.f(n) from generate_series(1, 8) n);
insert into public.attachments (asset_id, post_id, position) values (pg_temp.f(4), '8b100000-0000-4000-8000-000000000001', 1);
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = pg_temp.f(7);

-- ---------------------------------------------------------------------------
-- ข: ดึงงาน / ลองใหม่ / failed
-- ---------------------------------------------------------------------------
insert into private.jobs (id, kind, payload, dedupe_key, status, run_at, attempts, locked_at) overriding system value values
  (101, 'noop', '{}', 'due', 'pending', clock_timestamp() - interval '1 minute', 0, null),
  (102, 'noop', '{}', 'future', 'pending', clock_timestamp() + interval '1 hour', 0, null),
  (103, 'noop', '{}', 'stale', 'running', clock_timestamp() - interval '1 hour', 1, clock_timestamp() - interval '11 minutes'),
  (104, 'noop', '{}', 'fresh', 'running', clock_timestamp() - interval '1 hour', 1, clock_timestamp() - interval '1 minute'),
  (105, 'noop', '{}', 'done', 'done', clock_timestamp() - interval '1 hour', 1, null);
select ok(private.jobs_has_work(), 'มีงานถึงเวลา → jobs_has_work');
select is((select jsonb_agg(e -> 'id' order by e -> 'id') from jsonb_array_elements(public.jobs_claim(10)) e),
  '[101, 103]'::jsonb, 'ดึงเฉพาะ pending ที่ถึงเวลา และ running ที่ค้างเกิน 10 นาที');
select is((select jsonb_agg(jsonb_build_array(id, status, attempts) order by id) from private.jobs where id in (101, 103)),
  '[[101, "running", 1], [103, "running", 2]]'::jsonb, 'งานที่ดึงเป็น running และนับครั้ง');
select is(public.jobs_claim(10), '[]'::jsonb, 'ดึงซ้ำทันทีไม่ได้งานเดิม (running ที่ยังสด / pending อนาคต)');
select is(public.jobs_complete(101, null), true, 'ปิดงาน running ได้');
select is(public.jobs_complete(101, null), false, 'ปิดซ้ำไม่มีผล (ไม่ได้ running แล้ว)');
select is(public.jobs_fail(103, 'b2_500'), 'pending', 'ล้มครั้งที่ 2 → กลับ pending');
select ok((select run_at between clock_timestamp() + interval '115 seconds' and clock_timestamp() + interval '125 seconds'
             from private.jobs where id = 103), 'เว้นช่วง 60 × 2^(2−1) = 120 วินาที');
select is((select last_error from private.jobs where id = 103), 'b2_500', 'เก็บข้อผิดพลาดล่าสุด');
update private.jobs set status = 'running', attempts = 6, locked_at = clock_timestamp() where id = 103;
select is(public.jobs_fail(103, 'b2_500'), 'failed', 'ครบ 6 ครั้ง → failed');
select is(public.jobs_fail(103, 'x'), null, 'งานที่ไม่ได้ running ไม่เปลี่ยน');
update private.jobs set status = 'running', attempts = 10, locked_at = clock_timestamp(), run_at = clock_timestamp() where id = 104;
update private.jobs set attempts = 3 where id = 104;
select is(public.jobs_fail(104, 'x'), 'pending', 'ล้มครั้งที่ 3 → pending');
select ok((select run_at > clock_timestamp() + interval '235 seconds' from private.jobs where id = 104), 'เว้นช่วง 240 วินาที');
update private.jobs set status = 'running', attempts = 5, locked_at = clock_timestamp() where id = 104;
select ok(public.jobs_fail(104, 'x') = 'pending'
          and (select run_at <= clock_timestamp() + interval '16 minutes 5 seconds' from private.jobs where id = 104),
  'ครั้งที่ 5 เว้น 16 นาที (ยังไม่ถึงเพดาน 6 ชม.)');

-- ---------------------------------------------------------------------------
-- ค: delete_asset
-- ---------------------------------------------------------------------------
delete from private.jobs;
insert into private.jobs (id, kind, payload, dedupe_key, status, attempts, locked_at) overriding system value values
  (201, 'delete_asset', jsonb_build_object('asset_id', pg_temp.f(7), 'final_key', 'อย่าใช้', 'version_id', 'อย่าใช้'), 'a7', 'running', 1, clock_timestamp()),
  (202, 'delete_asset', jsonb_build_object('asset_id', pg_temp.f(4)), 'a4', 'running', 1, clock_timestamp()),
  (203, 'delete_asset', jsonb_build_object('asset_id', 'bb100000-0000-4000-8000-0000000000ff'), 'aff', 'running', 1, clock_timestamp()),
  (204, 'delete_asset', jsonb_build_object('asset_id', pg_temp.f(6)), 'a6', 'running', 1, clock_timestamp()),
  (205, 'delete_asset', jsonb_build_object('asset_id', pg_temp.f(7)), 'a7b', 'pending', 0, null);
-- ธงสำรองอยู่ → เลื่อนรอบ ไม่นับครั้ง
insert into private.maintenance_locks (name, reason, expires_at) values ('backup', 'test', clock_timestamp() + interval '30 minutes');
select is(public.delete_asset_begin(201) ->> 'action', 'defer', 'มีธง maintenance_locks → defer');
select ok((select status = 'pending' and attempts = 0 and run_at >= clock_timestamp() + interval '29 minutes'
                  and last_error = 'maintenance_lock' from private.jobs where id = 201),
  'เลื่อนไปหลังธงหมดอายุ และไม่นับเป็นการลอง');
delete from private.maintenance_locks;
update private.jobs set status = 'running', attempts = 1, locked_at = clock_timestamp() where id = 201;
select is(public.delete_asset_begin(201),
  jsonb_build_object('action', 'delete', 'asset_id', pg_temp.f(7), 'final_key', 'files/t23/7.pdf', 'version_id', 'v7'),
  'ไม่มีธง: ลบตาม key/เวอร์ชันในแถว asset (ไม่เชื่อ payload)');
select is(public.delete_asset_begin(202) ->> 'note', 'asset_kept', 'asset ที่ยังผูกอยู่ (ไม่ใช่ deleting) → ปิดงานโดยไม่ลบ');
select is((select status from public.assets where id = pg_temp.f(4)), 'ready', 'asset ที่ผูกอยู่ยังอยู่ครบ');
select is(public.delete_asset_begin(204) ->> 'note', 'asset_kept', 'asset ready ไม่มีแถวผูกแต่ยังไม่อยู่ในคิวลบ → ไม่ลบ');
select is(public.delete_asset_begin(203) ->> 'note', 'asset_gone', 'asset ไม่มีแล้ว → ปิดงาน (idempotent)');
select is((select string_agg(id || ':' || status, ',' order by id) from private.jobs where id in (202, 203, 204)),
  '202:done,203:done,204:done', 'งานที่ไม่ต้องลบปิดเป็น done');
create temp table used0 on commit drop as select private.storage_used_bytes() as b;
select is(public.delete_asset_finish(201), true, 'B2 ลบสำเร็จ → finish');
select is((select count(*)::integer from public.assets where id = pg_temp.f(7)), 0, 'ลบแถว asset แล้ว');
select is(private.storage_used_bytes(), (select b from used0) - 7000, 'ยอดพื้นที่ลดลงเท่าขนาดไฟล์');
select is((select status from private.jobs where id = 201), 'done', 'งานเป็น done');
select is(public.delete_asset_begin(205) ->> 'action', 'skip', 'งานที่ยังไม่ได้ดึง (ไม่ running) → skip');
select is(public.delete_asset_finish(205), false, 'finish งานที่ไม่ running ไม่มีผล');

-- ---------------------------------------------------------------------------
-- ง: sweeper copying
-- ---------------------------------------------------------------------------
select is((select jsonb_agg(e ->> 'asset_id' order by e ->> 'asset_id') from jsonb_array_elements(public.copying_stale(10)) e),
  jsonb_build_array(pg_temp.f(9)::text, pg_temp.f(10)::text), 'รายการ copying ที่ค้างเกิน 15 นาทีเท่านั้น');
select is(public.sweep_copying_finish(pg_temp.f(9), 'vdest9'), 'queued', 'ปลายทางมีไฟล์ → queued');
select ok((select status = 'deleting' and version_id = 'vdest9' and delete_requested_at is not null
             from public.assets where id = pg_temp.f(9)), 'บันทึกเวอร์ชันปลายทางแล้วเข้าคิวลบ (ไม่เป็น ready)');
select is((select payload ->> 'reason' from private.jobs where kind = 'delete_asset' and dedupe_key = pg_temp.f(9)::text),
  'stale_copying', 'มีงาน delete_asset ของไฟล์นั้น');
select is(public.sweep_copying_finish(pg_temp.f(10), null), 'removed', 'ปลายทางไม่มีไฟล์ → ลบแถว');
select is((select count(*)::integer from public.assets where id = pg_temp.f(10)), 0, 'แถว copying ถูกลบ');
select is(public.sweep_copying_finish(pg_temp.f(11), 'v'), 'skip', 'copying ที่เพิ่งเริ่มไม่แตะ');
select is(public.sweep_copying_finish(pg_temp.f(9), 'v'), 'skip', 'เรียกซ้ำไม่มีผล');

-- ---------------------------------------------------------------------------
-- จ: งานประจำ
-- ---------------------------------------------------------------------------
insert into public.b2_daily_usage (day, source, class_b_requests) values
  ((clock_timestamp() at time zone 'UTC')::date - 31, 'view', 5),
  ((clock_timestamp() at time zone 'UTC')::date - 29, 'view', 5);
insert into private.jobs (kind, payload, dedupe_key, status, updated_at) values
  ('noop', '{}', 'old-done', 'done', clock_timestamp() - interval '31 days'),
  ('noop', '{}', 'old-failed', 'failed', clock_timestamp() - interval '31 days');
insert into private.operation_receipts (account_id, request_key, operation, result, expires_at) values
  ('3b100000-0000-4000-8000-000000000001', gen_random_uuid(), 'x', '{}', clock_timestamp() - interval '1 minute');
create temp table m on commit drop as select public.jobs_maintenance() as r;
select is((select r ->> 'orphans_queued' from m), '2', 'เลือก asset กำพร้า 2 ไฟล์');
select is((select jsonb_agg(id order by id) from public.assets where status = 'deleting' and id in (select pg_temp.f(n) from generate_series(1, 6) n)),
  jsonb_build_array(pg_temp.f(3), pg_temp.f(5)),
  'กำพร้า = ไม่มีแถวผูก + batch หมดอายุเกิน 24 ชม. (3) หรือไม่มี batch และพร้อมใช้เกิน 24 ชม. (5)');
select is((select string_agg(status, ',' order by id) from public.assets where id in (pg_temp.f(1), pg_temp.f(2), pg_temp.f(4), pg_temp.f(6))),
  'ready,ready,ready,ready', 'ไม่เลือก: batch ยังเปิด (1), batch เพิ่งหมดอายุ (2), ผูกอยู่ (4), เพิ่งพร้อมใช้ (6)');
select is((select count(*)::integer from private.jobs where kind = 'delete_asset' and payload ->> 'reason' = 'orphan'), 2,
  'กำพร้าเข้าคิว delete_asset พร้อม version_id');
select is((select payload ->> 'version_id' from private.jobs where dedupe_key = pg_temp.f(3)::text), 'v3', 'งานมี version_id');
select is((select string_agg(status, ',' order by id) from public.upload_batches where id in (pg_temp.b(1), pg_temp.b(2), pg_temp.b(3), pg_temp.b(4))),
  'open,expired,expired,consumed', 'batch เปิดที่เลยเวลา → expired (consumed ไม่แตะ)');
select is((select r ->> 'usage_deleted' from m), '1', 'ล้าง b2_daily_usage ที่เก่ากว่า 30 วัน');
select is((select count(*)::integer from public.b2_daily_usage where day = (clock_timestamp() at time zone 'UTC')::date - 29), 1, 'ยังเก็บ 29 วัน');
select is((select string_agg(dedupe_key, ',' order by dedupe_key) from private.jobs where dedupe_key like 'old-%'), 'old-failed',
  'ล้างงาน done เก่า เก็บ failed ไว้');
select is((select r ->> 'receipts_deleted' from m), '1', 'ล้างใบรับคำขอที่หมดอายุ');
select is((public.jobs_maintenance() ->> 'orphans_queued'), '0', 'เรียกซ้ำไม่เข้าคิวซ้ำ');

-- ---------------------------------------------------------------------------
-- ฉ: storage_status / admin_b2_usage
-- ---------------------------------------------------------------------------
update public.storage_settings set quota_bytes = 1000000, hard_stop_margin_bytes = 1000, admin_warn_pct = 1, teacher_warn_pct = 2;
set local role authenticated;
set local request.jwt.claims to '{"sub": "2b100000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.storage_status(), '{"level": "ok"}'::jsonb, 'นักเรียนเห็นแค่ระดับ');
select throws_ok($$ select public.admin_b2_usage() $$, 'P0001', 'forbidden', 'นักเรียนอ่านตัวนับ B2 ไม่ได้');
set local request.jwt.claims to '{"sub": "2b100000-0000-4000-8000-000000000001", "role": "authenticated"}';
select ok((select s ->> 'level' in ('admin_warn', 'teacher_warn', 'ok') and (s ->> 'limit_bytes')::bigint = 999000
                  and s ? 'by_purpose' and s ? 'deleting_bytes'
             from public.storage_status() s), 'ครูเห็นยอดละเอียดและเพดาน = quota − margin');
select throws_ok($$ select public.admin_b2_usage() $$, 'P0001', 'forbidden', 'ครูอ่านตัวนับ B2 ไม่ได้');
set local role postgres;
update public.storage_settings set quota_bytes = 2000, hard_stop_margin_bytes = 0;
set local role authenticated;
set local request.jwt.claims to '{"sub": "2b100000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.storage_status(), '{"level": "full"}'::jsonb, 'ใช้เกินเพดาน → นักเรียนเห็น full');
set local request.jwt.claims to '{"sub": "2b100000-0000-4000-8000-000000000002", "role": "authenticated"}';
select ok((select u ? 'sources' and u ? 'view_budget_bytes' and (u -> 'jobs' ->> 'failed')::integer >= 1
             from public.admin_b2_usage() u), 'ผู้ดูแลอ่านตัวนับวันนี้ + งบเปิดดู + ยอดงาน failed');

select * from finish();
rollback;
