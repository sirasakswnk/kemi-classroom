-- ทดสอบ 0024_jobs_cron: ตารางเวลา pg_cron, jobs_tick ปลุก Edge Function เฉพาะเมื่อมีงานและตั้งค่าครบ (รหัสลับจาก Vault)
-- คำขอของ pg_net อยู่ในคิวจน commit — ไฟล์นี้ rollback จึงไม่ส่งจริง
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(8);

select is((select schedule || ' | ' || command from cron.job where jobname = 'kemi-process-jobs'),
  '*/2 * * * * | select private.jobs_tick()', 'cron ทุก 2 นาทีเรียก private.jobs_tick()');
select is_empty(
  $$ select r from unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, 'private.jobs_tick()', 'EXECUTE') $$,
  'jobs_tick เรียกได้เฉพาะ postgres (cron)');

delete from private.jobs;
delete from public.assets where status = 'copying';
create temp table q0 on commit drop as select count(*) as n from net.http_request_queue;
select is(private.jobs_tick() -> 'called', 'false'::jsonb, 'ไม่มีงาน → ไม่ปลุกฟังก์ชัน');
select is((select count(*) from net.http_request_queue), (select n from q0), 'ไม่มีคำขอ HTTP');

insert into private.jobs (kind, payload, dedupe_key) values ('noop', '{}', 'tick-test');
delete from vault.secrets where name in ('process_jobs_url', 'process_jobs_secret');
select is(private.jobs_tick() ->> 'reason', 'not_configured', 'มีงานแต่ยังไม่ตั้ง URL/รหัสลับใน Vault → ไม่เรียก');

select vault.create_secret('https://example.invalid/functions/v1/process-jobs', 'process_jobs_url');
select vault.create_secret('test-secret-value', 'process_jobs_secret');
create temp table t on commit drop as select private.jobs_tick() as r;
select is((select r -> 'called' from t), 'true'::jsonb, 'มีงาน + ตั้งค่าครบ → ปลุกฟังก์ชัน');
select is((select q.url from net.http_request_queue q where q.id = (select (r ->> 'request_id')::bigint from t)),
  'https://example.invalid/functions/v1/process-jobs', 'ส่งไป URL จาก Vault');
select is((select q.headers ->> 'x-jobs-secret' from net.http_request_queue q where q.id = (select (r ->> 'request_id')::bigint from t)),
  'test-secret-value', 'แนบรหัสลับจาก Vault ใน header x-jobs-secret');

select * from finish();
rollback;
