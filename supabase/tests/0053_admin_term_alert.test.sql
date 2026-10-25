-- ทดสอบ 0053_admin_term_alert: เตือนภาคเรียนเปิดค้างเกิน 6 เดือนใน D01 (ผู้ดูแลเท่านั้น, อ่านอย่างเดียว)
-- ข้อมูลสมมติทั้งหมด (@example.com) · ปรับ term_control ในทรานแซกชันนี้เท่านั้น (ไม่เรียก terms_start/terms_end) แล้ว rollback
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

select plan(12);

insert into public.terms (id, name, status) values ('45300000-0000-4000-8000-000000000001', 'ภาคทดสอบหกเดือน', 'active');
insert into public.term_control (term_id) values ('45300000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('15300000-0000-4000-8000-000000000001', 'ครูหกเดือน');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('35300000-0000-4000-8000-000000000001', '25300000-0000-4000-8000-000000000001', 'google', 'ta-1',
   'teacher53@example.com', 'teacher', '15300000-0000-4000-8000-000000000001'),
  ('35300000-0000-4000-8000-000000000003', '25300000-0000-4000-8000-000000000003', 'google', 'ta-3',
   'admin53@example.com', 'admin', null);

-- เวลาเริ่มภาคเรียนย้อนจากตอนนี้ตามปฏิทินไทย
create function pg_temp.start_ago(p interval) returns void language sql as $$
  update public.term_control
     set started_at = ((clock_timestamp() at time zone 'Asia/Bangkok') - p) at time zone 'Asia/Bangkok',
         status = 'active', ended_at = null
   where singleton $$;
create temp table snap as select (select row_to_json(c)::text from public.term_control c) as control,
                                 (select count(*) from public.terms) as terms;
grant select on snap to authenticated;

-- ---------------------------------------------------------------------------
-- 1. สิทธิ์: ไม่ใช่ผู้ดูแลอ่านไม่ได้
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.admin_term_alert()', 'EXECUTE'), 'anon เรียกไม่ได้');
set local role authenticated;
set local request.jwt.claims to '{"sub": "25300000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok('select public.admin_term_alert()', 'P0001', 'forbidden', 'ครูอ่านไม่ได้');
set local request.jwt.claims to '{"sub": "25300000-0000-4000-8000-0000000000ff", "role": "authenticated"}';
select throws_ok('select public.admin_term_alert()', 'P0001', 'forbidden', 'ผู้ใช้ไม่มีบัญชีอ่านไม่ได้');

-- ---------------------------------------------------------------------------
-- 2. เกณฑ์ 6 เดือน (นับจากเวลาเริ่มภาคเรียน)
-- ---------------------------------------------------------------------------
set local role postgres;
select pg_temp.start_ago(interval '5 months 29 days');
set local role authenticated;
set local request.jwt.claims to '{"sub": "25300000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.admin_term_alert(), null, '5 เดือน 29 วัน → ไม่เตือน');
set local role postgres;
select pg_temp.start_ago(interval '6 months' - interval '1 minute');
set local role authenticated;
select is(public.admin_term_alert(), null, 'อีก 1 นาทีครบ 6 เดือน → ยังไม่เตือน');
set local role postgres;
select pg_temp.start_ago(interval '6 months 1 minute');
set local role authenticated;
select is(public.admin_term_alert() ->> 'name', 'ภาคทดสอบหกเดือน', 'เกิน 6 เดือน → เตือน พร้อมชื่อภาคเรียน');
select ok((select (a ->> 'due_at')::timestamptz < clock_timestamp()
                  and (a ->> 'started_at')::timestamptz < (a ->> 'due_at')::timestamptz
                  and (a ->> 'days_open')::integer between 181 and 185
             from public.admin_term_alert() a), 'บอกวันเริ่ม วันครบ 6 เดือน และจำนวนวันที่เปิดค้าง');
set local role postgres;
select pg_temp.start_ago(interval '1 year');
set local role authenticated;
select isnt(public.admin_term_alert(), null, 'เปิดค้าง 1 ปี → เตือน');

-- ---------------------------------------------------------------------------
-- 3. จบภาคเรียนแล้ว → ไม่เตือน
-- ---------------------------------------------------------------------------
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select is(public.admin_term_alert(), null, 'จบภาคเรียนแล้ว (ended) → ไม่เตือนแม้เริ่มมานาน');

-- ---------------------------------------------------------------------------
-- 4. อ่านอย่างเดียว: ไม่เปลี่ยนสถานะ ไม่สร้างภาคเรียน ไม่แจ้งเตือน
-- ---------------------------------------------------------------------------
set local role postgres;
select pg_temp.start_ago(interval '1 year');
create temp table before_call as select row_to_json(c)::text as control from public.term_control c;
create temp table notif_before as select count(*) as n from public.notifications;
grant select on before_call, notif_before to authenticated;
set local role authenticated;
select isnt(public.admin_term_alert(), null, 'เรียกขณะเตือน');
set local role postgres;
select is((select row_to_json(c)::text from public.term_control c), (select control from before_call),
  'term_control ไม่ถูกเปลี่ยน');
select ok((select count(*) from public.terms) = (select terms from snap)
          and (select count(*) from public.notifications) = (select n from notif_before),
  'ไม่สร้างภาคเรียนและไม่แจ้งครู');

select * from finish();
rollback;
