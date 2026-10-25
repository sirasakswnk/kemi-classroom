-- ทดสอบ 0047_due_reminder_run: ตัวรันงานเตือนของ process-jobs (service_role)
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

select plan(16);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ห้อง R1 (นักเรียน A, B) · งานใส่ตรงในนาม postgres (ไม่มีผู้ใช้ → ไม่ตั้งงานเตือนเอง) แล้วใส่งานเตือนเอง
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40470000-0000-4000-8000-000000000001', 'ภาคทดสอบตัวรัน', 'active');
insert into public.term_control (term_id) values ('40470000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10470000-0000-4000-8000-000000000001', 'ครูตัวรัน');
insert into public.students (id, student_code, display_name) values
  ('60470000-0000-4000-8000-00000000000a', '947000000001', 'ก ตัวรัน'),
  ('60470000-0000-4000-8000-00000000000b', '947000000002', 'ข ตัวรัน');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70470000-0000-4000-8000-000000000001', '40470000-0000-4000-8000-000000000001', '10470000-0000-4000-8000-000000000001', 'ห้องตัวรัน', 'QQQQ47');
insert into public.memberships (classroom_id, student_id) values
  ('70470000-0000-4000-8000-000000000001', '60470000-0000-4000-8000-00000000000a'),
  ('70470000-0000-4000-8000-000000000001', '60470000-0000-4000-8000-00000000000b');

create temp table t47_base as select date_trunc('minute', clock_timestamp()) as b;
create function pg_temp.at(p_hours numeric) returns timestamptz language sql stable as
  $$ select b + make_interval(secs => p_hours * 3600) from t47_base $$;
-- งาน n กำหนด p_due + งานเตือน (status ตามที่ให้ — running = ถูก jobs_claim ดึงแล้ว) ที่ payload จำกำหนด p_payload_due
create function pg_temp.setup(p_n integer, p_due timestamptz, p_payload_due timestamptz, p_status text default 'running')
returns bigint language plpgsql as $$
declare
  v_post uuid := ('80470000-0000-4000-8000-00000000000' || p_n)::uuid;
  v_id bigint;
begin
  insert into public.posts (id, classroom_id, kind, title) values (v_post, '70470000-0000-4000-8000-000000000001', 'homework', 'งาน ' || p_n);
  insert into public.assignments (post_id, full_score, due_at) values (v_post, 10, p_due);
  insert into private.jobs (kind, payload, dedupe_key, status, run_at, attempts, locked_at)
  values ('due_reminder', jsonb_build_object('assignment_id', v_post, 'due_at', p_payload_due), v_post::text, p_status,
          p_payload_due - interval '24 hours', case when p_status = 'running' then 1 else 0 end,
          case when p_status = 'running' then clock_timestamp() end)
  returning id into v_id;
  return v_id;
end $$;
create function pg_temp.reminded(p_n integer) returns integer language sql stable as
  $$ select count(*)::integer from public.notifications n
      where n.kind = 'due_reminder' and n.post_id = ('80470000-0000-4000-8000-00000000000' || p_n)::uuid $$;
create function pg_temp.job(p_id bigint) returns text language sql stable as
  $$ select j.status || ' ' || coalesce(j.last_error, '-') from private.jobs j where j.id = p_id $$;

create temp table t47_jobs (n integer primary key, id bigint);
insert into t47_jobs values
  (1, pg_temp.setup(1, pg_temp.at(20), pg_temp.at(20))),
  (2, pg_temp.setup(2, pg_temp.at(-1), pg_temp.at(-1))),
  (3, pg_temp.setup(3, pg_temp.at(20), pg_temp.at(30))),
  (4, pg_temp.setup(4, pg_temp.at(20), pg_temp.at(20), 'pending'));
insert into private.jobs (kind, payload, dedupe_key, status, attempts, locked_at)
  values ('delete_asset', '{"asset_id": "00000000-0000-4000-8000-000000000000"}', 't47-other', 'running', 1, clock_timestamp());
grant select on t47_jobs to service_role;
create function pg_temp.id(p_n integer) returns bigint language sql stable as $$ select id from t47_jobs where n = p_n $$;
grant execute on function pg_temp.id(integer) to service_role;

-- ---------------------------------------------------------------------------
-- 1. สิทธิ์
-- ---------------------------------------------------------------------------
set local role authenticated;
select throws_ok($$ select public.due_reminder_run(1) $$, '42501', null, 'ผู้ใช้เรียกตัวรันงานเตือนไม่ได้');
reset role;
set local role postgres;
select ok(has_function_privilege('service_role', 'public.due_reminder_run(bigint)', 'EXECUTE'), 'service_role เรียกได้');

-- ---------------------------------------------------------------------------
-- 2. ในนาม service_role (เหมือน process-jobs)
-- ---------------------------------------------------------------------------
set local role service_role;
select is(public.due_reminder_run(pg_temp.id(1)), '{"action": "done", "sent": 2}'::jsonb, 'งานที่ถึงคิว → เตือน A และ B');
select is(public.due_reminder_run(pg_temp.id(1)), '{"action": "skip"}'::jsonb,
          'เรียกซ้ำ (ตัวทำงานซ้อน) หลังงานปิดแล้ว → skip');
select is(public.due_reminder_run(pg_temp.id(2)), '{"action": "done", "sent": 0}'::jsonb,
          'ถึงคิวช้าจนเลยกำหนดส่ง (cron หยุดไป) → ไม่สร้างแจ้งเตือน');
select is(public.due_reminder_run(pg_temp.id(3)), '{"action": "done", "sent": 0}'::jsonb,
          'กำหนดเปลี่ยนแล้ว (payload เก่า) → ไม่สร้าง');
select is(public.due_reminder_run(pg_temp.id(4)), '{"action": "skip"}'::jsonb, 'งานที่ยังไม่ถูกดึง (pending) → skip');
reset role;
set local role postgres;
select is(public.due_reminder_run((select j.id from private.jobs j where j.dedupe_key = 't47-other')),
          '{"action": "skip"}'::jsonb, 'งานชนิดอื่น → skip');
select is(public.due_reminder_run(-1), '{"action": "skip"}'::jsonb, 'งานที่ไม่มีอยู่ → skip');

-- ---------------------------------------------------------------------------
-- 3. ผลในตาราง
-- ---------------------------------------------------------------------------
select is(pg_temp.reminded(1), 2, 'งาน 1 มีแจ้งเตือนใกล้กำหนด 2 รายการ (เรียกซ้ำไม่เพิ่ม)');
select is(pg_temp.job(pg_temp.id(1)), 'done sent 2', 'งาน 1 ปิดพร้อมบันทึกจำนวนที่ส่ง');
select is(pg_temp.reminded(2), 0, 'งานที่เลยกำหนดแล้วไม่มีแจ้งเตือน');
select is(pg_temp.job(pg_temp.id(2)), 'done sent 0', 'งานเตือนที่ช้าเกินถูกปิด ไม่ค้างลองใหม่');
select is(pg_temp.reminded(3), 0, 'payload เก่าไม่มีแจ้งเตือน');
select is(pg_temp.job(pg_temp.id(4)), 'pending -', 'งานที่ยังไม่ถูกดึงคงสถานะเดิม');
select is((select j.status from private.jobs j where j.dedupe_key = 't47-other'), 'running', 'งานชนิดอื่นไม่ถูกแตะ');

select * from finish();
rollback;
