-- ทดสอบ 0051_admin_jobs: รายการงานที่ล้มเหลว + ลองใหม่ใน D01 (ผู้ดูแลเท่านั้น)
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

select plan(25);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ผู้ดูแล 1 · ครู 1 (มีบัญชี) · นักเรียน 1 ในห้อง · งานที่เลยกำหนดแล้ว
-- ล้างงานล้มเหลวเดิมใน dev ก่อนนับ (rollback ตอนจบคืนครบ)
-- ---------------------------------------------------------------------------
delete from private.jobs where status = 'failed';
insert into public.terms (id, name, status) values ('45100000-0000-4000-8000-000000000001', 'ภาคทดสอบงานล้ม', 'active');
insert into public.term_control (term_id) values ('45100000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('15100000-0000-4000-8000-000000000001', 'ครูงานล้ม');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('35100000-0000-4000-8000-000000000001', '25100000-0000-4000-8000-000000000001', 'google', 'fj-1',
   'teacher51@example.com', 'teacher', '15100000-0000-4000-8000-000000000001'),
  ('35100000-0000-4000-8000-000000000003', '25100000-0000-4000-8000-000000000003', 'google', 'fj-3',
   'admin51@example.com', 'admin', null);
insert into public.students (id, student_code, display_name) values
  ('65100000-0000-4000-8000-00000000000a', '951000000001', 'ก งานล้ม');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('75100000-0000-4000-8000-000000000001', '45100000-0000-4000-8000-000000000001', '15100000-0000-4000-8000-000000000001', 'ห้องงานล้ม', 'QQQQ52');
insert into public.memberships (classroom_id, student_id) values
  ('75100000-0000-4000-8000-000000000001', '65100000-0000-4000-8000-00000000000a');
insert into public.posts (id, classroom_id, kind, title) values
  ('85100000-0000-4000-8000-000000000001', '75100000-0000-4000-8000-000000000001', 'homework', 'งานเลยกำหนด');
insert into public.assignments (post_id, full_score, due_at) values
  ('85100000-0000-4000-8000-000000000001', 10, date_trunc('minute', clock_timestamp()) - interval '2 hours');

-- งานล้มเหลว 3 แบบ + งานที่ยังรอ/กำลังทำ (ไม่ต้องแสดง/ลองใหม่ไม่ได้)
insert into private.jobs (kind, payload, dedupe_key, status, attempts, last_error, updated_at) values
  ('due_reminder', jsonb_build_object('assignment_id', '85100000-0000-4000-8000-000000000001',
                                      'due_at', date_trunc('minute', clock_timestamp()) - interval '2 hours'),
   't51-due', 'failed', 6, 'due_reminder_P0001', clock_timestamp() - interval '1 hour'),
  ('delete_asset', '{"asset_id": "00000000-0000-4000-8000-000000000051", "final_key": "files/secret-name.pdf"}',
   't51-del', 'failed', 6, 'b2_500 <ชื่อไฟล์ ก.pdf>', clock_timestamp()),
  ('storage_reconcile', '{}', 't51-rc-old', 'failed', 6, 'b2_network', clock_timestamp() - interval '2 hours'),
  ('storage_reconcile', '{}', 't51-rc-new', 'pending', 0, null, clock_timestamp()),
  ('delete_asset', '{"asset_id": "00000000-0000-4000-8000-000000000052"}', 't51-run', 'running', 1, null, clock_timestamp());
create temp table ids as select dedupe_key as k, id from private.jobs where dedupe_key like 't51-%';
grant select on ids to authenticated, service_role;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select id from ids where k = p $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;
create function pg_temp.status(p text) returns text language sql stable security definer as
  $$ select status || ' ' || attempts from private.jobs where dedupe_key = p $$;
grant execute on function pg_temp.status(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. สิทธิ์: คนที่ไม่ใช่ผู้ดูแลเรียกไม่ได้
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.admin_failed_jobs()', 'EXECUTE')
          and not has_function_privilege('anon', 'public.admin_retry_job(bigint)', 'EXECUTE'),
  'anon เรียกไม่ได้');
set local role authenticated;
set local request.jwt.claims to '{"sub": "25100000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok('select public.admin_failed_jobs()', 'P0001', 'forbidden', 'ครูอ่านรายการงานล้มเหลวไม่ได้');
select throws_ok($$ select public.admin_retry_job(pg_temp.id('t51-due')) $$, 'P0001', 'forbidden', 'ครูกดลองใหม่ไม่ได้');
set local request.jwt.claims to '{"sub": "25100000-0000-4000-8000-0000000000ff", "role": "authenticated"}';
select throws_ok($$ select public.admin_retry_job(pg_temp.id('t51-due')) $$, 'P0001', 'forbidden', 'ผู้ใช้ที่ไม่มีบัญชีกดไม่ได้');
select is(pg_temp.status('t51-due'), 'failed 6', 'งานไม่ถูกแตะ');

-- ---------------------------------------------------------------------------
-- 2. รายการ: เฉพาะ failed ล่าสุดก่อน ไม่มี payload · error ย่อเหลือรหัส
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "25100000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is((public.admin_failed_jobs() ->> 'failed_total')::integer, 3, 'นับเฉพาะ failed');
select is((select array_agg(x ->> 'kind') from jsonb_array_elements(public.admin_failed_jobs() -> 'items') x),
          array['delete_asset', 'due_reminder', 'storage_reconcile'], 'ล่าสุดก่อน (เวลาที่ล้มล่าสุด)');
select is((select array_agg(distinct k order by k) from jsonb_array_elements(public.admin_failed_jobs() -> 'items') x,
             jsonb_object_keys(x) k),
          array['attempts', 'created_at', 'error', 'failed_at', 'id', 'kind'], 'ไม่มี payload ในผล');
select ok(position('secret-name' in public.admin_failed_jobs()::text) = 0, 'ไม่มี key ไฟล์จาก payload');
select is((public.admin_failed_jobs() -> 'items' -> 0 ->> 'error'), 'b2_500 .pdf', 'error ย่อกรองเหลือตัวอักษรรหัส');

-- ---------------------------------------------------------------------------
-- 3. ลองใหม่: กดซ้ำ / พร้อมกัน ไม่ทำซ้อน
-- ---------------------------------------------------------------------------
select is(public.admin_retry_job(pg_temp.id('t51-due')), '{"result": "queued", "status": "pending"}'::jsonb, 'ลองใหม่ → queued');
set local role postgres;
select ok((select status = 'pending' and attempts = 0 and run_at <= clock_timestamp() and locked_at is null
                  and last_error like 'retry: due_reminder_P0001%'
             from private.jobs where id = pg_temp.id('t51-due')),
  'กลับเป็น pending attempts 0 ถึงคิวทันที (error เดิมเก็บไว้ดู)');
set local role authenticated;
select is(public.admin_retry_job(pg_temp.id('t51-due')), '{"result": "not_failed", "status": "pending"}'::jsonb,
  'กดซ้ำ → not_failed ไม่ทำอะไร');
set local role postgres;
select is((select count(*)::integer from private.jobs where dedupe_key = 't51-due'), 1, 'ไม่มีงานใหม่ซ้อน (แถวเดิม)');
-- ตัวทำงานดึงไปแล้ว (running) ระหว่างที่ผู้ดูแลกดอีกครั้ง → ไม่แตะงานที่กำลังทำ
update private.jobs set status = 'running', attempts = 1, locked_at = clock_timestamp() where id = pg_temp.id('t51-due');
set local role authenticated;
select is(public.admin_retry_job(pg_temp.id('t51-due')) ->> 'result', 'not_failed', 'งาน running → ไม่แตะ');
select is(public.admin_retry_job(pg_temp.id('t51-run')) ->> 'result', 'not_failed', 'งานอื่นที่กำลังทำ → ไม่แตะ');
select is(public.admin_retry_job(-1), '{"result": "not_failed", "status": null}'::jsonb, 'ไม่มีงานนี้ → not_failed');
set local role postgres;
select is(pg_temp.status('t51-due'), 'running 1', 'สถานะของตัวทำงานคงเดิม');

-- ---------------------------------------------------------------------------
-- 4. ตัวรันยังตรวจความเกี่ยวข้องตามเดิม: เตือนใกล้ส่งที่เลยกำหนดแล้ว → ปิดโดยไม่แจ้ง
-- ---------------------------------------------------------------------------
set local role service_role;
select is(public.due_reminder_run(pg_temp.id('t51-due')), '{"action": "done", "sent": 0}'::jsonb,
  'งานที่ลองใหม่ถึงตัวรัน → เลยกำหนดแล้ว ปิดงานไม่แจ้ง');
set local role postgres;
select is((select count(*)::integer from public.notifications
            where kind = 'due_reminder' and post_id = '85100000-0000-4000-8000-000000000001'), 0, 'ไม่มีแจ้งเตือน');
select is(pg_temp.status('t51-due'), 'done 1', 'งานปิดเป็น done');

-- ---------------------------------------------------------------------------
-- 5. เทียบยอดที่มีงานใหม่ค้างอยู่ → ไม่ลองใหม่ (กันเทียบสองงานพร้อมกัน)
-- ---------------------------------------------------------------------------
set local role authenticated;
select is(public.admin_retry_job(pg_temp.id('t51-rc-old')) ->> 'result', 'superseded', 'เทียบยอดเก่า + มีงานใหม่ค้าง → superseded');
set local role postgres;
select is(pg_temp.status('t51-rc-old'), 'failed 6', 'งานเก่ายังเป็น failed');
delete from private.jobs where dedupe_key = 't51-rc-new';
set local role authenticated;
select is(public.admin_retry_job(pg_temp.id('t51-rc-old')) ->> 'result', 'queued', 'ไม่มีงานเทียบอื่นค้าง → ลองใหม่ได้ (ทำต่อจาก cursor เดิม)');
set local role postgres;
select is(pg_temp.status('t51-rc-old'), 'pending 0', 'กลับเป็น pending');

select * from finish();
rollback;
