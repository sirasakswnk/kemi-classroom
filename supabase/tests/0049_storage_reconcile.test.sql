-- ทดสอบ 0049_storage_reconcile: เทียบยอดพื้นที่ B2 รายวัน (process-jobs, service_role)
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

select plan(43);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 1 คน ไฟล์ 2 ไฟล์ (100 + 200 ไบต์) · งานอื่นในคิวไม่เกี่ยว (ใส่งานเองทีละงาน)
-- ---------------------------------------------------------------------------
insert into public.teachers (id, display_name) values ('14900000-0000-4000-8000-000000000001', 'ครูทดสอบเทียบยอด');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('34900000-0000-4000-8000-000000000001', '24900000-0000-4000-8000-000000000001', 'google', 'rc-1',
   'teacher49@example.com', 'teacher', '14900000-0000-4000-8000-000000000001');
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, version_id, content_type, size_bytes, file_name) values
  ('a4900000-0000-4000-8000-000000000001', '34900000-0000-4000-8000-000000000001', 'post', 'staging/t49/a1', 'sv-a1', 'files/t49/a1.pdf', 'v-a1', 'application/pdf', 100, 'a1.pdf'),
  ('a4900000-0000-4000-8000-000000000002', '34900000-0000-4000-8000-000000000001', 'post', 'staging/t49/a2', 'sv-a2', 'files/t49/a2.pdf', 'v-a2', 'application/pdf', 200, 'a2.pdf');
delete from private.jobs where kind = 'storage_reconcile';
delete from public.b2_daily_usage where source = 'reconcile';
update public.storage_settings set storage_offset_bytes = 0, reconciled_at = null,
  reconcile_run_max_requests = 20, reconcile_daily_budget_requests = 500;

create temp table base as select private.storage_used_bytes() as used;
grant select on base to service_role;

-- ---------------------------------------------------------------------------
-- 1. ค่าชดเชยบวกเข้ายอดที่ใช้คิดโควตา · cron · สิทธิ์
-- ---------------------------------------------------------------------------
update public.storage_settings set storage_offset_bytes = 1234;
select is(private.storage_used_bytes(), (select used from base) + 1234, 'storage_used_bytes รวมค่าชดเชย');
update public.storage_settings set storage_offset_bytes = 0;
select throws_ok($$ update public.storage_settings set storage_offset_bytes = -1 $$, '23514', null,
  'ค่าชดเชยติดลบไม่ได้ (ใช้ยอดที่มากกว่า)');
select is((select schedule from cron.job where jobname = 'kemi-storage-reconcile'), '30 21 * * *',
  'cron วันละครั้ง 21:30 UTC = 04:30 น. ไทย');
select ok(has_function_privilege('service_role', 'public.storage_reconcile_step(bigint,jsonb,boolean)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'public.storage_reconcile_step(bigint,jsonb,boolean)', 'EXECUTE')
          and not has_function_privilege('authenticated', 'public.storage_reconcile_start(bigint)', 'EXECUTE'),
  'start/step เรียกได้เฉพาะ service_role');

-- ---------------------------------------------------------------------------
-- 2. สร้างงานรายวัน: ไม่ซ้อนงานที่ค้าง
-- ---------------------------------------------------------------------------
select isnt(private.storage_reconcile_enqueue(), null, 'สร้างงานเทียบของวันนี้');
select is(private.storage_reconcile_enqueue(), null, 'มีงานค้างอยู่ → ไม่สร้างซ้ำ');
select is((select count(*)::integer from private.jobs where kind = 'storage_reconcile'), 1, 'มีงานเดียว');

-- ตัวทำงานถืองานอยู่ (แทน jobs_claim ที่อาจดึงงานอื่นในคิวมาด้วย)
update private.jobs set status = 'running', locked_at = clock_timestamp(), attempts = 1
 where kind = 'storage_reconcile';
create temp table j as select id from private.jobs where kind = 'storage_reconcile';
grant select on j to service_role;

-- ---------------------------------------------------------------------------
-- 3. เริ่ม → ขอหน้าแรก · หน้าถัดไปในรอบเดียวกัน
-- ---------------------------------------------------------------------------
set local role service_role;
select is((select public.storage_reconcile_start(id) from j) - 'key_marker' - 'version_id_marker',
          '{"action":"list","allow":20}'::jsonb, 'เริ่ม: ขอได้ min(เพดานต่อรอบ 20, งบวันนี้ 500)');
select is((select public.storage_reconcile_step(id, '{"ok":true,"truncated":true,"next_key_marker":"files/t49/a2.pdf","next_version_id_marker":"v-old","delete_markers":1,
  "versions":[{"k":"files/t49/a1.pdf","v":"v-a1","s":100,"l":true},
              {"k":"files/t49/a2.pdf","v":"v-a2","s":200,"l":true},
              {"k":"files/t49/a2.pdf","v":"v-old","s":50,"l":false}]}'::jsonb, true) from j),
          '{"action":"list","key_marker":"files/t49/a2.pdf","version_id_marker":"v-old"}'::jsonb,
  'หน้ายังไม่หมด + ยังขอต่อได้ → ขอหน้าถัดไปจาก cursor');
reset role;
select is((select class_c_requests from public.b2_daily_usage
            where source = 'reconcile' and day = (clock_timestamp() at time zone 'UTC')::date), 1::bigint,
  'นับคำขอ Class C ต่อหน้า (source reconcile)');
select is((select payload -> 'tally' -> 'bytes' from private.jobs where id = (select id from j)), '350'::jsonb,
  'รวมทุกเวอร์ชัน รวมเวอร์ชันที่ถูกซ่อน');
select is((select (payload -> 'tally' ->> 'noncurrent_bytes')::bigint from private.jobs where id = (select id from j)), 50::bigint,
  'แยกยอดเวอร์ชันที่ไม่ใช่ล่าสุด');
select is((select (payload -> 'tally' ->> 'unknown_versions')::integer from private.jobs where id = (select id from j)), 1,
  'files/ ที่ไม่มี asset ตรง key+version = 1 (เวอร์ชันเก่า)');
select is((select status from private.jobs where id = (select id from j)), 'running', 'ยังถืองานอยู่');

-- ---------------------------------------------------------------------------
-- 4. ครบเพดานต่อรอบ → พักไว้รอบหน้า (cursor อยู่ใน payload, ไม่นับเป็นการล้ม)
-- ---------------------------------------------------------------------------
set local role service_role;
select is((select public.storage_reconcile_step(id, '{"ok":true,"truncated":true,"next_key_marker":"staging/x","next_version_id_marker":"sv-9","delete_markers":0,
  "versions":[{"k":"staging/b1/f1","v":"sv-1","s":1000,"l":true}]}'::jsonb, false) from j),
          '{"action":"later"}'::jsonb, 'ขอต่อไม่ได้ในรอบนี้ → later');
reset role;
select ok((select status = 'pending' and attempts = 0 and run_at <= clock_timestamp() and locked_at is null
             and payload ->> 'key_marker' = 'staging/x' and (payload ->> 'requests')::integer = 2
             and (payload -> 'tally' ->> 'staging_bytes')::bigint = 1000
             from private.jobs where id = (select id from j)),
  'พักไว้: pending ทำต่อได้ทันทีรอบหน้า, attempts = 0, cursor + ยอดคงอยู่');
select is(private.storage_reconcile_enqueue(), null, 'งานที่พักไว้ยังค้าง → cron วันถัดไปไม่สร้างซ้อน');

-- รอบใหม่: ตัวทำงานดึงงานอีกครั้ง → เริ่มจาก cursor เดิม
update private.jobs set status = 'running', locked_at = clock_timestamp(), attempts = 1 where id = (select id from j);
set local role service_role;
select is((select public.storage_reconcile_start(id) from j),
          '{"action":"list","allow":20,"key_marker":"staging/x","version_id_marker":"sv-9"}'::jsonb,
  'รอบใหม่ทำต่อจาก cursor');
reset role;
select is((select (payload ->> 'runs')::integer from private.jobs where id = (select id from j)), 2, 'นับจำนวนรอบ');

-- ---------------------------------------------------------------------------
-- 5. ข้อผิดพลาดของ B2 · เพดานรายวันของ B2 · ข้อมูลผิดรูป
-- ---------------------------------------------------------------------------
set local role service_role;
select is((select public.storage_reconcile_step(id, '{"ok":false,"error":"b2_500"}'::jsonb, true) from j),
          '{"action":"failed"}'::jsonb, 'B2 ล้ม → failed (jobs_fail)');
reset role;
select ok((select status = 'pending' and last_error = 'b2_500' and run_at > clock_timestamp()
             and payload ->> 'key_marker' = 'staging/x' and (payload ->> 'requests')::integer = 3
             from private.jobs where id = (select id from j)),
  'ล้ม: ลองใหม่ตามรอบ ยอดและ cursor คงอยู่ คำขอที่ล้มก็นับ');

update private.jobs set status = 'running', locked_at = clock_timestamp(), attempts = 1 where id = (select id from j);
set local role service_role;
select is((select public.storage_reconcile_step(id, '{"ok":false,"error":"b2_403","cap":true}'::jsonb, true) from j),
          '{"action":"paused","reason":"b2_cap"}'::jsonb, 'B2 ตอบเกินเพดาน → พักถึงวันใหม่');
reset role;
select ok((select status = 'pending' and attempts = 0 and run_at = private.b2_next_day()
             from private.jobs where id = (select id from j)),
  'พักถึง 00:10 UTC ของวันถัดไป (หลังเพดาน B2 ขึ้นวันใหม่) ไม่นับเป็นการล้ม');

update private.jobs set status = 'running', locked_at = clock_timestamp(), attempts = 1 where id = (select id from j);
set local role service_role;
select throws_ok($$ select public.storage_reconcile_step((select id from j), '{"ok":true,"versions":[{"k":"files/x","v":"v","s":-1,"l":true}]}'::jsonb, true) $$,
  'P0001', 'invalid_request', 'ขนาดติดลบ → invalid_request');
select throws_ok($$ select public.storage_reconcile_step((select id from j), '{"ok":true,"truncated":true,"versions":[]}'::jsonb, true) $$,
  'P0001', 'invalid_request', 'หน้าไม่หมดแต่ไม่มี cursor → invalid_request');
select throws_ok($$ select public.storage_reconcile_step((select id from j), '{"ok":true}'::jsonb, true) $$,
  'P0001', 'invalid_request', 'ไม่มีรายการ versions → invalid_request');
select is(public.storage_reconcile_step(-1, '{"ok":true,"versions":[]}'::jsonb, true), '{"action":"skip"}'::jsonb,
  'งานที่ไม่ได้ถืออยู่ → skip');
reset role;

-- ---------------------------------------------------------------------------
-- 6. หน้าสุดท้าย: B2 มากกว่า → ค่าชดเชย = ส่วนต่าง + ประวัติ
-- ---------------------------------------------------------------------------
set local role service_role;
select is((select public.storage_reconcile_step(id, '{"ok":true,"truncated":false,"delete_markers":2,
  "versions":[{"k":"other/readme","v":"o1","s":7,"l":true}]}'::jsonb, true) - 'b2_bytes' - 'diff_bytes' - 'offset_bytes' - 'exceeds_threshold' from j),
          '{"action":"done","requests":5}'::jsonb, 'หน้าสุดท้าย → done');
reset role;
-- B2 = 350 + 1000 + 7 = 1357 · ยอดที่ระบบนับ = base (ไม่มีค่าชดเชย)
select is((select b2_bytes from public.storage_reconciliations), 1357::bigint, 'ยอด B2 รวมทุกหน้า');
select is((select diff_bytes from public.storage_reconciliations), 1357 - (select used from base),
  'diff = B2 − (assets + ที่จองไว้)');
select is((select storage_offset_bytes from public.storage_settings), greatest(1357 - (select used from base), 0),
  'ค่าชดเชย = greatest(diff, 0)');
select is(private.storage_used_bytes(), greatest(1357, (select used from base)),
  'ยอดที่ใช้คิดโควตา = ยอดที่มากกว่า');
select ok((select reconciled_at is not null from public.storage_settings), 'บันทึกเวลาเทียบล่าสุด');
select is((select breakdown from public.storage_reconciliations) - 'unknown_bytes' - 'unknown_versions',
          '{"files_bytes":350,"files_versions":3,"staging_bytes":1000,"staging_versions":1,"other_bytes":7,"other_versions":1,
            "noncurrent_bytes":50,"noncurrent_versions":1,"delete_markers":3}'::jsonb,
  'ประวัติแยกยอดตาม prefix / เวอร์ชันซ่อน / ป้ายซ่อน');
select ok((select requests = 5 and runs = 2 and offset_before_bytes = 0 and job_id = (select id from j)
             from public.storage_reconciliations), 'ประวัติเก็บจำนวนคำขอ/รอบ และค่าชดเชยก่อนหน้า');
select is((select status from private.jobs where id = (select id from j)), 'done', 'ปิดงาน');
select ok((select assets_unchanged from (select count(*) = 2 as assets_unchanged from public.assets
             where id in ('a4900000-0000-4000-8000-000000000001', 'a4900000-0000-4000-8000-000000000002')) x)
          and not exists (select 1 from private.jobs where kind = 'delete_asset'
                            and payload ->> 'asset_id' like 'a4900000%'),
  'ผลเทียบไม่ลบไฟล์และไม่สร้างงานลบ');

-- ---------------------------------------------------------------------------
-- 7. B2 น้อยกว่า → ไม่ลดยอด (ค่าชดเชย 0) · ธงเกินเกณฑ์ · งบรายวันหมด
-- ---------------------------------------------------------------------------
select is(private.storage_reconcile_enqueue(), null, 'วันเดียวกันมีงานแล้ว (dedupe ตามวันที่ไทย) → ไม่สร้างซ้ำ');
insert into private.jobs (kind, payload, dedupe_key, status, locked_at, attempts)
values ('storage_reconcile', '{}'::jsonb, 'test-2', 'running', clock_timestamp(), 1);
create temp table j2 as select id from private.jobs where kind = 'storage_reconcile' and dedupe_key = 'test-2';
grant select on j2 to service_role;
set local role service_role;
select is((select public.storage_reconcile_start(id) ->> 'action' from j2), 'list', 'งานที่สองเริ่มได้');
select is((select (public.storage_reconcile_step(id, '{"ok":true,"truncated":false,"versions":[]}'::jsonb, true) ->> 'offset_bytes')::bigint from j2),
          0::bigint, 'B2 ว่าง (น้อยกว่าที่นับ) → ค่าชดเชย 0 ไม่ลดยอด');
reset role;
select ok((select diff_bytes = -(select used from base) and offset_before_bytes = greatest(1357 - (select used from base), 0)
                  and exceeds_threshold
             from public.storage_reconciliations where job_id = (select id from j2)),
  'ประวัติเก็บ diff ติดลบ + ธงเกินเกณฑ์ (ต่าง ≥ 5%)');

insert into private.jobs (kind, payload, dedupe_key, status, locked_at, attempts)
values ('storage_reconcile', '{}'::jsonb, 'test-3', 'running', clock_timestamp(), 1);
create temp table j3 as select id from private.jobs where kind = 'storage_reconcile' and dedupe_key = 'test-3';
grant select on j3 to service_role;
update public.storage_settings set reconcile_daily_budget_requests = 6;  -- ใช้ไปแล้ว 6 ครั้งวันนี้
set local role service_role;
select is((select public.storage_reconcile_start(id) from j3),
          '{"action":"paused","reason":"daily_budget"}'::jsonb, 'งบ Class C ของวันหมด → พักถึงวันใหม่');
reset role;
select ok((select status = 'pending' and run_at = private.b2_next_day() and payload ? 'started_at'
             from private.jobs where dedupe_key = 'test-3'), 'พักไว้ พร้อมเริ่มนับยอดเมื่อถึงวันใหม่');

select * from finish();
rollback;
