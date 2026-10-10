-- ทดสอบ 0020_submissions: ตารางรับการส่ง 7 แถว + ขอบเวลา, submit_assignment (ไฟล์ใหม่/ไฟล์เดิม, รุ่น, request key, สิทธิ์แก้ K3,
-- งานลบไฟล์ที่ถูกแทนใน jobs, I4), create_upload_batch วัตถุประสงค์ submission, authorize_files/RLS ของงานส่ง,
-- นักเรียนที่ถูกเอาออกแล้วเข้าใหม่เห็นงานเดิม — ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
-- สองคำขอพร้อมกันจริง (สองการเชื่อมต่อ) ทดสอบแยกไว้ในโน้ต P3-07 — ไฟล์นี้ตรวจลำดับล็อกเชิงโครงสร้าง
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

select plan(118);

-- ---------------------------------------------------------------------------
-- ก: โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.submission_rule(boolean,timestamp with time zone,timestamp with time zone,text,boolean,boolean,boolean)',
                         'private.assignment_intake(uuid,timestamp with time zone)',
                         'private.submission_latest_graded(uuid)', 'private.submission_files_ids(uuid[])',
                         'private.submission_files_json(uuid)', 'private.submissions_guard()',
                         'private.revision_permissions_guard()']) f,
            unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยของงานส่งใช้ภายในเท่านั้น');
select is_empty(
  $$ select format('%s %s %s', r, t, p)
       from unnest(array['public.submissions', 'public.revision_permissions']) t,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
      where has_table_privilege(r, t, p) $$,
  'ตารางงานส่งไม่มีสิทธิ์เขียนตรง (เขียนผ่าน RPC เท่านั้น)');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.submissions'::regclass, 'public.revision_permissions'::regclass)),
  'เปิด RLS ทั้งสองตาราง');
select ok(has_table_privilege('authenticated', 'public.submissions', 'SELECT')
          and has_table_privilege('authenticated', 'public.revision_permissions', 'SELECT')
          and not has_table_privilege('anon', 'public.submissions', 'SELECT'),
  'authenticated อ่านได้ตาม RLS, anon อ่านไม่ได้');
-- ลำดับในตัวฟังก์ชัน: advisory lock ของงานส่ง → ล็อกแถวงานส่ง → ล็อก asset → อ่าน clock_timestamp() หลังสุด
select ok((select position('''submission:''' in d) > 0
                  and position('order by a.id for update' in d) > position('''submission:''' in d)
                  and position('r.status = ''open'' for update' in d) > position('order by a.id for update' in d)
                  and position('v_now := clock_timestamp()' in d) > position('r.status = ''open'' for update' in d)
             from pg_get_functiondef('public.submit_assignment(uuid,uuid[],integer,uuid)'::regprocedure) d),
  'submit_assignment: advisory lock ของงานส่ง → ล็อกแถว → ล็อก asset/สิทธิ์แก้ → อ่าน clock_timestamp() หลังได้ล็อก');

-- ---------------------------------------------------------------------------
-- ข: ตารางรับการส่ง (ฟังก์ชันล้วน) — กำหนด 13:00:00 UTC (= 20:00 น.) ไม่มีช่วงผ่อนผัน
-- ---------------------------------------------------------------------------
create function pg_temp.rule(p_submitted boolean, p_now text, p_intake text default 'open', p_sol boolean default false,
                             p_graded boolean default false, p_perm boolean default false) returns text language sql as
  $$ select private.submission_rule(p_submitted, '2026-11-10 13:00:00+00', p_now::timestamptz, p_intake, p_sol, p_graded, p_perm) $$;

select is(pg_temp.rule(false, '2026-11-10 12:59:59+00'), 'first_on_time', 'แถว 2: ยังไม่เคยส่ง ก่อนกำหนด → ทัน');
select is(pg_temp.rule(false, '2026-11-10 13:00:00+00'), 'first_on_time', 'แถว 2 ขอบ: ส่งที่วินาที 00 ของกำหนดพอดี → ทัน');
select is(pg_temp.rule(false, '2026-11-10 13:00:00.000001+00'), 'first_late', 'แถว 3 ขอบ: เลยกำหนด 1 ไมโครวินาที → สาย');
select is(pg_temp.rule(false, '2026-11-10 13:00:01+00'), 'first_late', 'แถว 3: เลยกำหนด 1 วินาที ยังเปิดรับ → สาย');
select is(pg_temp.rule(false, '2026-11-12 00:00:00+00', 'after_solution', true), 'first_after_solution',
  'แถว 4: ยังไม่เคยส่ง เฉลยเผยแพร่แล้วและรับหลังเฉลย → first_after_solution');
select is(pg_temp.rule(false, '2026-11-09 00:00:00+00', 'after_solution', true), 'first_after_solution',
  'แถว 4 ชนะแถว 2: ส่งแรกหลังเฉลยเป็นสายเสมอแม้ยังไม่ถึงกำหนด');
select is(pg_temp.rule(true, '2026-11-10 13:00:00+00'), 'resubmit', 'แถว 5 ขอบ: เคยส่ง ที่วินาที 00 ของกำหนด ยังไม่ตรวจ → ส่งแก้ไม่ใช้สิทธิ์');
select throws_ok($$ select pg_temp.rule(true, '2026-11-10 13:00:01+00') $$, 'P0001', 'resubmit_not_allowed',
  'แถว 6 ขอบ: เคยส่ง เลยกำหนด 1 วินาที ไม่มีสิทธิ์แก้ → resubmit_not_allowed');
select is(pg_temp.rule(true, '2026-11-10 13:00:01+00', p_perm => true), 'resubmit_permission',
  'แถว 6: เคยส่ง เลยกำหนด มีสิทธิ์แก้ → รับและใช้สิทธิ์');
select throws_ok($$ select pg_temp.rule(true, '2026-11-09 00:00:00+00', p_graded => true) $$, 'P0001', 'resubmit_not_allowed',
  'แถว 6: ก่อนกำหนดแต่รุ่นล่าสุดมีผลตรวจแล้ว ไม่มีสิทธิ์ → resubmit_not_allowed');
select is(pg_temp.rule(true, '2026-11-09 00:00:00+00', p_graded => true, p_perm => true), 'resubmit_permission',
  'แถว 6: ก่อนกำหนด มีผลตรวจแล้ว มีสิทธิ์แก้ → ใช้สิทธิ์');
select throws_ok($$ select pg_temp.rule(true, '2026-11-12 00:00:00+00', 'closed', true, false, true) $$, 'P0001', 'submission_closed',
  'แถว 6 (E1): เฉลยเผยแพร่แล้วแต่ไม่รับหลังเฉลย มีสิทธิ์แก้ก็ไม่รับ');
select is(pg_temp.rule(true, '2026-11-12 00:00:00+00', 'after_solution', true, false, true), 'resubmit_permission',
  'แถว 6 (E1): ช่วงรับหลังเฉลย + สิทธิ์แก้ → รับ');
select throws_ok($$ select pg_temp.rule(true, '2026-11-09 00:00:00+00', 'after_solution', true) $$, 'P0001', 'resubmit_not_allowed',
  'หลังเฉลยส่งแก้ต้องมีสิทธิ์เสมอ แม้ยังไม่ถึงกำหนด (แถว 5 ใช้ไม่ได้)');
select throws_ok($$ select pg_temp.rule(false, '2026-11-12 00:00:00+00', 'closed') $$, 'P0001', 'submission_closed',
  'แถว 7: ปิดรับแล้ว ยังไม่เคยส่ง → submission_closed');
select is(pg_temp.rule(true, '2026-11-12 00:00:00+00', 'closed', p_perm => true), 'resubmit_permission',
  'แถว 7: ปิดรับแล้ว มีสิทธิ์แก้ค้าง → รับตามแถว 6');
select throws_ok($$ select pg_temp.rule(true, '2026-11-12 00:00:00+00', 'closed') $$, 'P0001', 'submission_closed',
  'แถว 7: ปิดรับแล้ว เคยส่ง ไม่มีสิทธิ์ → submission_closed');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ภาคเรียนปัจจุบัน + ภาคเรียนก่อน, ครู 2 คน, ผู้ดูแล, นักเรียน S1–S3 สมาชิกห้อง 1
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values
  ('4f000000-0000-4000-8000-000000000000', 'ภาคก่อนทดสอบงานส่ง', 'superseded'),
  ('4f000000-0000-4000-8000-000000000001', 'ภาคทดสอบงานส่ง', 'active');
insert into public.term_control (term_id) values ('4f000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1f000000-0000-4000-8000-000000000001', 'ครูทดสอบงานส่ง'),
  ('1f000000-0000-4000-8000-000000000002', 'ครูทดสอบงานส่งสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3f000000-0000-4000-8000-000000000001', '2f000000-0000-4000-8000-000000000001', 'google', 'sb-1', 'teacher20a@example.com', 'teacher', '1f000000-0000-4000-8000-000000000001'),
  ('3f000000-0000-4000-8000-000000000002', '2f000000-0000-4000-8000-000000000002', 'google', 'sb-2', 'teacher20b@example.com', 'teacher', '1f000000-0000-4000-8000-000000000002'),
  ('3f000000-0000-4000-8000-000000000003', '2f000000-0000-4000-8000-000000000003', 'google', 'sb-3', 'admin20@example.com', 'admin', null),
  ('3f000000-0000-4000-8000-000000000011', '2f000000-0000-4000-8000-000000000011', 'google', 'sb-11', 's1-20@example.com', 'student', null),
  ('3f000000-0000-4000-8000-000000000012', '2f000000-0000-4000-8000-000000000012', 'google', 'sb-12', 's2-20@example.com', 'student', null),
  ('3f000000-0000-4000-8000-000000000013', '2f000000-0000-4000-8000-000000000013', 'google', 'sb-13', 's3-20@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6f000000-0000-4000-8000-000000000011', '920000000000201', 'หนึ่ง งานส่ง', '3f000000-0000-4000-8000-000000000011'),
  ('6f000000-0000-4000-8000-000000000012', '920000000000202', 'สอง งานส่ง', '3f000000-0000-4000-8000-000000000012'),
  ('6f000000-0000-4000-8000-000000000013', '920000000000203', 'สาม งานส่ง', '3f000000-0000-4000-8000-000000000013');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000001', 'เคมีทดสอบงานส่ง 1', 'ZZZZ42'),
  ('7f000000-0000-4000-8000-000000000002', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000002', 'เคมีทดสอบงานส่ง 2', 'ZZZZ43'),
  ('7f000000-0000-4000-8000-000000000003', '4f000000-0000-4000-8000-000000000000', '1f000000-0000-4000-8000-000000000001', 'เคมีทดสอบงานส่ง ภาคก่อน', 'ZZZZ44');
insert into public.memberships (classroom_id, student_id) values
  ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000011'),
  ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000012'),
  ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000013'),
  ('7f000000-0000-4000-8000-000000000003', '6f000000-0000-4000-8000-000000000011');

-- งาน (สร้างตรงด้วย postgres): H1 อีก 1 วัน · H2 เลยกำหนด ไม่มีวันปิดรับ · H3 ปิดรับแล้ว · H4 เฉลยแล้ว+รับหลังเฉลย
-- H5 เฉลยแล้ว ไม่รับหลังเฉลย · H6 ห้องภาคก่อน · H7 ห้อง 2 · A8 ประกาศ
create function pg_temp.p(n integer) returns uuid language sql immutable as
  $$ select ('8f000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create temp table due0 on commit drop as select date_trunc('minute', clock_timestamp()) as m;
insert into public.posts (id, classroom_id, kind, title)
select pg_temp.p(n), case n when 6 then '7f000000-0000-4000-8000-000000000003'::uuid when 7 then '7f000000-0000-4000-8000-000000000002'::uuid
                            else '7f000000-0000-4000-8000-000000000001'::uuid end,
       case n when 8 then 'announcement' else 'homework' end, 'งานทดสอบ ' || n
  from generate_series(1, 8) n;
insert into public.assignments (post_id, full_score, due_at, close_at, accept_after_solution)
select pg_temp.p(n), 10,
       (select m from due0) + case when n in (1, 6, 7) then interval '1 day' when n = 2 then interval '-1 day' else interval '-2 days' end,
       case when n = 3 then (select m from due0) - interval '1 day' end,
       n = 4
  from generate_series(1, 7) n;
insert into public.solutions (assignment_id, body, published_at) values
  (pg_temp.p(4), 'เฉลย', clock_timestamp()), (pg_temp.p(5), 'เฉลย', clock_timestamp());

-- batch และ asset ของนักเรียน (ready ทั้งหมด ยกเว้น 16):
--  b1 S1/H1: 1,2,3,16(copying) · b2 S1/H2: 4,5,6 · b3 S1/H3: 7 · b4 S1/H4: 8 · b5 S2/H3: 9, 10 (10 ผูกกับงานส่งเดิมของ S2)
--  b6 S2/H5: 11, 12 (12 ผูกเดิม) · b7 S2/H1: 13 (ไฟล์เดียว — ทดสอบ consumed) · b8 S3/H1: 14, 15
--  b10 S2/H2: 17 (ผูกเดิม), 18 · b9 S1/H1: 20–30 (นับ 11 ไฟล์) และ 31–33 PDF 10 MB (รวมเกิน 20 MB)
create function pg_temp.f(n integer) returns uuid language sql immutable as
  $$ select ('bf000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.b(n integer) returns uuid language sql immutable as
  $$ select ('9f000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.fs(variadic n integer[]) returns uuid[] language sql immutable as
  $$ select coalesce(array_agg(pg_temp.f(x) order by o), '{}') from unnest(n) with ordinality u(x, o) $$;
create temp table spec (asset integer, batch integer, owner uuid, post integer) on commit drop;
insert into spec
select a, b, case when b in (5, 6, 7, 10) then '3f000000-0000-4000-8000-000000000012'::uuid
                  when b = 8 then '3f000000-0000-4000-8000-000000000013'::uuid
                  else '3f000000-0000-4000-8000-000000000011'::uuid end,
       case b when 1 then 1 when 2 then 2 when 3 then 3 when 4 then 4 when 5 then 3 when 6 then 5 when 7 then 1 when 8 then 1 when 10 then 2 else 1 end
  from (values (1, 1), (2, 1), (3, 1), (16, 1), (4, 2), (5, 2), (6, 2), (7, 3), (8, 4), (9, 5), (10, 5), (11, 6), (12, 6),
               (13, 7), (14, 8), (15, 8), (17, 10), (18, 10)) v(a, b)
union all select a, 9, '3f000000-0000-4000-8000-000000000011'::uuid, 1 from generate_series(20, 33) a;
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, files, reserved_bytes, expires_at)
select pg_temp.b(s.batch), min(s.owner::text)::uuid, 'submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(min(s.post)),
       jsonb_agg(jsonb_build_object('staging_key', 'staging/t20/' || s.asset)), 1000, clock_timestamp() + interval '1 hour'
  from spec s group by s.batch;
insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
select pg_temp.f(s.asset), s.owner, 'submission', pg_temp.b(s.batch), 'staging/t20/' || s.asset, 'sv-' || s.asset,
       'files/t20/' || s.asset || '.jpg', 'image/jpeg', case when s.asset between 31 and 33 then 10485760 else 1000 + s.asset end,
       'งาน ' || s.asset || '.jpg'
  from spec s;
update public.assets set status = 'ready', version_id = 'v-' || staging_version_id, checksum = 'e', ready_at = clock_timestamp()
 where id::text like 'bf000000-%' and id <> pg_temp.f(16);

-- งานส่งเดิมของ S2 (สร้างตรง): H3 ไฟล์ 10 · H5 ไฟล์ 12 · H2 ไฟล์ 17 (ส่งแรกก่อนกำหนด 1 ชม.) — ทุกงานมีสิทธิ์แก้ค้าง
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5f000000-0000-4000-8000-000000000023', pg_temp.p(3), '6f000000-0000-4000-8000-000000000012', (select m from due0) - interval '3 days', (select m from due0) - interval '3 days'),
  ('5f000000-0000-4000-8000-000000000025', pg_temp.p(5), '6f000000-0000-4000-8000-000000000012', (select m from due0) - interval '3 days', (select m from due0) - interval '3 days'),
  ('5f000000-0000-4000-8000-000000000022', pg_temp.p(2), '6f000000-0000-4000-8000-000000000012', (select m from due0) - interval '1 day 1 hour', (select m from due0) - interval '1 day 1 hour');
insert into public.attachments (asset_id, submission_id, position) values
  (pg_temp.f(10), '5f000000-0000-4000-8000-000000000023', 1), (pg_temp.f(12), '5f000000-0000-4000-8000-000000000025', 1),
  (pg_temp.f(17), '5f000000-0000-4000-8000-000000000022', 1);
insert into public.revision_permissions (submission_id, opened_by_account_id) values
  ('5f000000-0000-4000-8000-000000000023', '3f000000-0000-4000-8000-000000000001'),
  ('5f000000-0000-4000-8000-000000000025', '3f000000-0000-4000-8000-000000000001'),
  ('5f000000-0000-4000-8000-000000000022', '3f000000-0000-4000-8000-000000000001');

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text, p_key text) returns jsonb language sql stable as
  $$ select body -> p_key from res where label = p_label $$;
create function pg_temp.files_of(p_assignment uuid, p_student uuid) returns uuid[] language sql stable as
  $$ select coalesce(array_agg(t.asset_id order by t.position), '{}')
       from public.attachments t join public.submissions s on s.id = t.submission_id
      where s.assignment_id = p_assignment and s.student_id = p_student $$;
create function pg_temp.sub(p_assignment uuid, p_student uuid) returns public.submissions language sql stable as
  $$ select s.* from public.submissions s where s.assignment_id = p_assignment and s.student_id = p_student $$;
grant execute on function pg_temp.p(integer), pg_temp.f(integer), pg_temp.b(integer), pg_temp.fs(integer[]),
  pg_temp.r(text, text) to authenticated;
create temp table key1 on commit drop as select gen_random_uuid() as k;
grant select on key1 to authenticated;

-- ---------------------------------------------------------------------------
-- ค: สถานะรับงาน (ฟังก์ชันเดียวที่ P4-03 แทนที่)
-- ---------------------------------------------------------------------------
select is(private.assignment_intake(pg_temp.p(2), clock_timestamp()), 'open', 'ไม่มีวันปิดรับ ไม่มีเฉลย → open (รับสาย)');
select is(private.assignment_intake(pg_temp.p(3), (select m from due0) - interval '1 day'), 'open', 'ที่เวลาปิดรับพอดียังเปิดรับ');
select is(private.assignment_intake(pg_temp.p(3), (select m from due0) - interval '1 day' + interval '1 second'), 'closed', 'เลยวันปิดรับ 1 วินาที → closed');
select is(private.assignment_intake(pg_temp.p(4), clock_timestamp()), 'after_solution', 'เฉลยแล้ว + รับหลังเฉลย → after_solution');
select is(private.assignment_intake(pg_temp.p(5), clock_timestamp()), 'closed', 'เฉลยแล้ว ไม่รับหลังเฉลย → closed');
select is(private.submission_latest_graded('5f000000-0000-4000-8000-000000000023'), false, 'รุ่นล่าสุดมีผลตรวจ: false จนกว่า P4-01');

-- ---------------------------------------------------------------------------
-- ง: create_upload_batch วัตถุประสงค์ submission
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';
insert into res values ('batch', public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(1),
  '[{"file_name":"หน้า1.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()));
select is(pg_temp.r('batch', 'purpose'), '"submission"', 'นักเรียนสมาชิกขอ batch งานส่งของการบ้านในห้องได้');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000002', pg_temp.p(7),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'not_member', 'ห้องที่ไม่ได้เป็นสมาชิก → not_member');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(8),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'โพสต์ประกาศ → forbidden');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(7),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'การบ้านของห้องอื่นที่อ้างผ่านห้องตัวเอง → forbidden');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', null,
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ไม่ระบุงาน → invalid_request');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000003', pg_temp.p(6),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'งานของห้องภาคเรียนก่อน → term_ended (K5)');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(1),
  '[{"file_name":"a.pdf","content_type":"application/pdf","size_bytes":10485761}]', gen_random_uuid()) $$,
  'P0001', 'file_too_large', 'J4–J6 ใช้กับชุดนักเรียน (PDF เกิน 10 MB)');
select throws_ok($$ select public.create_upload_batch('post', '7f000000-0000-4000-8000-000000000001', null,
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนขอ batch ไฟล์โจทย์ไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(1),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูขอ batch งานส่งไม่ได้ (ส่งงานแทนนักเรียนไม่ได้)');
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp();
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(1),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ภาคเรียนจบแล้ว (ended) อัปโหลดงานส่งไม่ได้ (K5)');

-- ---------------------------------------------------------------------------
-- จ: submit_assignment — แถว 1 (K5), not_member, ผู้เรียกที่ไม่ใช่นักเรียน
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 2), 0, gen_random_uuid()) $$,
  'P0001', 'term_ended', 'แถว 1: ภาคเรียน ended → term_ended');
set local role postgres;
update public.term_control set status = 'active', ended_at = null;
set local role authenticated;
select throws_ok($$ select public.submit_assignment(pg_temp.p(6), pg_temp.fs(1), 0, gen_random_uuid()) $$,
  'P0001', 'term_ended', 'แถว 1: งานของห้องภาคเรียนก่อน → term_ended');
select throws_ok($$ select public.submit_assignment(pg_temp.p(7), pg_temp.fs(1), 0, gen_random_uuid()) $$,
  'P0001', 'not_member', 'งานของห้องที่ไม่ได้เป็นสมาชิก → not_member');
select throws_ok($$ select public.submit_assignment(pg_temp.p(8), pg_temp.fs(1), 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ประกาศส่งงานไม่ได้ → forbidden');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1), 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูเรียก submit_assignment ไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';

-- รูปแบบรายการไฟล์
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), '{}', 0, gen_random_uuid()) $$,
  'P0001', 'submission_files_required', 'ไม่มีไฟล์ → submission_files_required');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 1), 0, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'id ซ้ำ → invalid_request');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), array[pg_temp.f(1), null], 0, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'มี null → invalid_request');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30), 0, gen_random_uuid()) $$,
  'P0001', 'too_many_files', '11 ไฟล์ → too_many_files');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(31, 32, 33), 0, gen_random_uuid()) $$,
  'P0001', 'batch_too_large', 'รวมเกิน 20 MB → batch_too_large');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1), 1, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'ยังไม่เคยส่งแต่ส่งรุ่น 1 มา → stale_revision');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 16), 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'asset ที่ยังไม่ ready → submission_file_unavailable');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 4), 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'asset ของตนจาก batch ของงานอื่น → submission_file_unavailable');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 13), 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'asset ของนักเรียนคนอื่น (ยังไม่ผูก) → submission_file_unavailable');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), array[pg_temp.f(1), 'bf000000-0000-4000-8000-0000000000ff'], 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'id ที่ไม่มีอยู่ได้รหัสเดียวกัน');
set local role postgres;
select is((select count(*)::integer from public.submissions where student_id = '6f000000-0000-4000-8000-000000000011'), 0,
  'คำขอที่ล้มทั้งหมดไม่สร้างงานส่ง');
select is((select reward_locked_at from public.assignments where post_id = pg_temp.p(1)), null, 'ยังไม่ล็อกรางวัล (ยังไม่มีการส่งสำเร็จ)');

-- ---------------------------------------------------------------------------
-- ฉ: แถว 2 ส่งแรกทัน + I4 + request key ซ้ำ + stale_revision + ส่งแก้แถว 5 + งานลบใน jobs
-- ---------------------------------------------------------------------------
set local role authenticated;
insert into res values ('h1', public.submit_assignment(pg_temp.p(1), pg_temp.fs(2, 1), 0, (select k from key1)));
select is(pg_temp.r('h1', 'outcome'), '"first_on_time"', 'แถว 2: ส่งแรกก่อนกำหนด → first_on_time');
select is(pg_temp.r('h1', 'timing'), '"on_time"', 'ผลบอกทัน');
select is(pg_temp.r('h1', 'content_revision'), '1', 'รุ่นแรก = 1');
select is(pg_temp.r('h1', 'files'), jsonb_build_array(
    jsonb_build_object('asset_id', pg_temp.f(2), 'file_name', 'งาน 2.jpg', 'content_type', 'image/jpeg', 'size_bytes', 1002),
    jsonb_build_object('asset_id', pg_temp.f(1), 'file_name', 'งาน 1.jpg', 'content_type', 'image/jpeg', 'size_bytes', 1001)),
  'ผลคืนไฟล์ตามลำดับที่ส่ง (ไม่มี key/เวอร์ชัน)');
select is(pg_temp.r('h1', 'submitted_at'), pg_temp.r('h1', 'first_submitted_at'), 'คืนเวลาที่บันทึกจริง = เวลาส่งแรก');
select is(public.submit_assignment(pg_temp.p(1), pg_temp.fs(2, 1), 0, (select k from key1)), (select body from res where label = 'h1'),
  'request key เดิมได้ผลเดิม (ไม่ตอบ stale_revision ไม่ส่งซ้ำ)');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(2, 1), 0, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'คำขอที่สองของคนเดียวกันที่ถือรุ่น 0 → stale_revision');
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(3), 0, (select k from key1)) $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่เนื้อหาต่าง → request_key_conflict');
set local role postgres;
select is((select reward_locked_at from public.assignments where post_id = pg_temp.p(1)),
  (pg_temp.r('h1', 'first_submitted_at') #>> '{}')::timestamptz, 'I4: การส่งครั้งแรกของงานตั้ง reward_locked_at');
select is((select count(*)::integer from public.submissions where assignment_id = pg_temp.p(1)), 1, 'ส่งซ้ำด้วย key เดิมไม่สร้างแถวเพิ่ม');

set local role authenticated;
insert into res values ('h1r', public.submit_assignment(pg_temp.p(1), pg_temp.fs(3, 2), 1, gen_random_uuid()));
select is(pg_temp.r('h1r', 'outcome'), '"resubmit"', 'แถว 5: ส่งแก้ก่อนกำหนด ยังไม่ตรวจ → resubmit ไม่ใช้สิทธิ์');
select is(pg_temp.r('h1r', 'content_revision'), '2', 'รุ่นเพิ่มเป็น 2');
select is(pg_temp.r('h1r', 'first_submitted_at'), pg_temp.r('h1', 'first_submitted_at'), 'เวลาส่งแรกคงเดิม');
select ok((pg_temp.r('h1r', 'last_submitted_at') #>> '{}')::timestamptz >= (pg_temp.r('h1', 'last_submitted_at') #>> '{}')::timestamptz
          and pg_temp.r('h1r', 'last_submitted_at') = pg_temp.r('h1r', 'submitted_at'), 'เวลาส่งล่าสุดเลื่อนเป็นเวลาที่บันทึกจริง');
set local role postgres;
select is(pg_temp.files_of(pg_temp.p(1), '6f000000-0000-4000-8000-000000000011'), pg_temp.fs(3, 2),
  'ชุดใหม่: ไฟล์เดิมที่เก็บ (2) ไม่ต้องอัปโหลดซ้ำ + ไฟล์ใหม่ (3) ตามลำดับ');
select is((select status from public.assets where id = pg_temp.f(1)), 'deleting', 'ไฟล์ที่ถูกแทน (1) เลิกผูกและเข้า deleting');
select is((select status from public.assets where id = pg_temp.f(2)), 'ready', 'ไฟล์เดิมที่เก็บไว้ (2) ยัง ready');
select results_eq(
  $$ select kind, dedupe_key, payload from private.jobs where kind = 'delete_asset' and dedupe_key like 'bf000000-%' order by id $$,
  $$ select 'delete_asset'::text, pg_temp.f(1)::text,
            jsonb_build_object('asset_id', pg_temp.f(1), 'final_key', 'files/t20/1.jpg', 'version_id', 'v-sv-1', 'reason', 'replaced') $$,
  'งานลบใน jobs: เฉพาะไฟล์ที่ถูกแทน ระบุ final_key + version_id และ dedupe_key = asset id');

set local role authenticated;
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(1, 2), 2, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'ไฟล์ที่ถูกแทนไปแล้ว (deleting) ใช้อีกไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000012", "role": "authenticated"}';
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(13, 2), 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'ไฟล์เดิมในงานส่งของคนอื่น → submission_file_unavailable');
insert into res values ('s2h1', public.submit_assignment(pg_temp.p(1), pg_temp.fs(13), 0, gen_random_uuid()));
set local role postgres;
select is((select status from public.upload_batches where id = pg_temp.b(7)), 'consumed', 'batch ที่ทุกไฟล์ถูกผูกแล้วตั้ง consumed');
select is((select status from public.upload_batches where id = pg_temp.b(1)), 'open', 'batch ที่ยังมีไฟล์ไม่ผูก (16) คงเปิด');

-- ---------------------------------------------------------------------------
-- ช: แถว 3 สาย + แถว 6 ไม่มี/มีสิทธิ์แก้ (K3) + ส่งล้มไม่ใช้สิทธิ์
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';
insert into res values ('h2', public.submit_assignment(pg_temp.p(2), pg_temp.fs(4), 0, gen_random_uuid()));
select is(pg_temp.r('h2', 'outcome'), '"first_late"', 'แถว 3: ยังไม่เคยส่ง เลยกำหนด ยังเปิดรับ → first_late');
select is(pg_temp.r('h2', 'timing'), '"late"', 'ผลบอกสาย');
select is(pg_temp.r('h2', 'first_after_solution'), 'false', 'ส่งสายธรรมดาไม่ใช่ first_after_solution');
select throws_ok($$ select public.submit_assignment(pg_temp.p(2), pg_temp.fs(5), 1, gen_random_uuid()) $$,
  'P0001', 'resubmit_not_allowed', 'แถว 6: เลยกำหนด ไม่มีสิทธิ์แก้ → resubmit_not_allowed');
set local role postgres;
insert into public.revision_permissions (submission_id, opened_by_account_id)
select s.id, '3f000000-0000-4000-8000-000000000001' from public.submissions s
 where s.assignment_id = pg_temp.p(2) and s.student_id = '6f000000-0000-4000-8000-000000000011';
create temp table h2_before on commit drop as select * from pg_temp.sub(pg_temp.p(2), '6f000000-0000-4000-8000-000000000011');
set local role authenticated;
select throws_ok($$ select public.submit_assignment(pg_temp.p(2), pg_temp.fs(5, 13), 1, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'มีสิทธิ์แก้แต่ส่งล้ม (ไฟล์ของคนอื่น)');
set local role postgres;
select is((select status from public.revision_permissions r join public.submissions s on s.id = r.submission_id
            where s.assignment_id = pg_temp.p(2) and s.student_id = '6f000000-0000-4000-8000-000000000011'), 'open', 'K3: ส่งล้มไม่ใช้สิทธิ์แก้');
select is(pg_temp.files_of(pg_temp.p(2), '6f000000-0000-4000-8000-000000000011'), pg_temp.fs(4), 'ส่งล้ม: ชุดไฟล์เดิมคงอยู่');
select ok((select row(s.last_submitted_at, s.content_revision) = row(b.last_submitted_at, b.content_revision)
             from pg_temp.sub(pg_temp.p(2), '6f000000-0000-4000-8000-000000000011') s, h2_before b),
  'ส่งล้ม: เวลาส่งล่าสุดและรุ่นคงเดิม');
set local role authenticated;
insert into res values ('h2r', public.submit_assignment(pg_temp.p(2), pg_temp.fs(5, 4), 1, gen_random_uuid()));
select is(pg_temp.r('h2r', 'outcome'), '"resubmit_permission"', 'แถว 6: มีสิทธิ์แก้ → รับ');
select is(pg_temp.r('h2r', 'used_permission'), 'true', 'ผลบอกว่าใช้สิทธิ์');
select is(pg_temp.r('h2r', 'timing'), '"late"', 'ส่งแรกสาย ส่งแก้ด้วยสิทธิ์ก็ยังสาย');
set local role postgres;
select ok((select r.status = 'used' and r.used_revision = 2 and r.used_at = (pg_temp.r('h2r', 'submitted_at') #>> '{}')::timestamptz
             from public.revision_permissions r join public.submissions s on s.id = r.submission_id
            where s.assignment_id = pg_temp.p(2) and s.student_id = '6f000000-0000-4000-8000-000000000011'),
  'K3: ใช้สิทธิ์ใน transaction เดียวกับการส่งที่สำเร็จ (used, รุ่นที่ใช้ = 2, เวลาเดียวกัน)');
set local role authenticated;
select throws_ok($$ select public.submit_assignment(pg_temp.p(2), pg_temp.fs(5), 2, gen_random_uuid()) $$,
  'P0001', 'resubmit_not_allowed', 'K3: สิทธิ์ใช้ได้ครั้งเดียว ส่งแก้อีกต้องขอใหม่');

-- I2: งานยังไม่ตรวจคิดทัน/สายจากกำหนดปัจจุบัน — เลื่อนกำหนดของ H1 ให้เร็วกว่าเวลาส่งแรกของ S1 (สร้างตรง)
set local role postgres;
update public.assignments set due_at = (select m from due0) - interval '1 hour' where post_id = pg_temp.p(1);
insert into public.revision_permissions (submission_id, opened_by_account_id)
select (pg_temp.r('h1', 'submission_id') #>> '{}')::uuid, '3f000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into res values ('h1p', public.submit_assignment(pg_temp.p(1), pg_temp.fs(3, 2), 2, gen_random_uuid()));
select is(pg_temp.r('h1p', 'outcome') || pg_temp.r('h1p', 'timing'), '"resubmit_permission"'::jsonb || '"late"'::jsonb,
  'I2: กำหนดเลื่อนเร็วขึ้นจนเวลาส่งแรกเลยกำหนด → สาย (ส่งแก้ได้เพราะมีสิทธิ์)');
set local role postgres;
update public.assignments set due_at = (select m from due0) + interval '1 day' where post_id = pg_temp.p(1);
-- I1: ส่งแรกทัน (S2/H2 ก่อนกำหนด 1 ชม.) แล้วส่งแก้หลังเลยกำหนดด้วยสิทธิ์ → ยังทัน
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000012", "role": "authenticated"}';
insert into res values ('i1', public.submit_assignment(pg_temp.p(2), pg_temp.fs(18), 1, gen_random_uuid()));
select is(pg_temp.r('i1', 'outcome') || pg_temp.r('i1', 'timing'), '"resubmit_permission"'::jsonb || '"on_time"'::jsonb,
  'I1: ส่งแรกทัน ส่งแก้หลังเส้นตายด้วยสิทธิ์ → ยังทัน (ไม่หักเพราะเวลาส่งแก้)');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';

-- ---------------------------------------------------------------------------
-- ซ: แถว 7 ปิดรับ, แถว 4 หลังเฉลย, E1
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.submit_assignment(pg_temp.p(3), pg_temp.fs(7), 0, gen_random_uuid()) $$,
  'P0001', 'submission_closed', 'แถว 7: ปิดรับแล้ว ยังไม่เคยส่ง → submission_closed');
insert into res values ('h4', public.submit_assignment(pg_temp.p(4), pg_temp.fs(8), 0, gen_random_uuid()));
select is(pg_temp.r('h4', 'outcome'), '"first_after_solution"', 'แถว 4: ส่งแรกในช่วงรับหลังเฉลย');
select is(pg_temp.r('h4', 'first_after_solution') || pg_temp.r('h4', 'timing'), 'true'::jsonb || '"late"'::jsonb,
  'แถว 4: first_after_solution = true และนับเป็นสาย');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000012", "role": "authenticated"}';
insert into res values ('h3', public.submit_assignment(pg_temp.p(3), pg_temp.fs(9, 10), 1, gen_random_uuid()));
select is(pg_temp.r('h3', 'outcome'), '"resubmit_permission"', 'แถว 7: ปิดรับแล้วแต่มีสิทธิ์แก้ค้าง → รับตามแถว 6');
select throws_ok($$ select public.submit_assignment(pg_temp.p(5), pg_temp.fs(11, 12), 1, gen_random_uuid()) $$,
  'P0001', 'submission_closed', 'E1: เฉลยแล้วไม่รับหลังเฉลย มีสิทธิ์แก้ก็ส่งแก้ไม่ได้');
set local role postgres;
select is((select status from public.revision_permissions where submission_id = '5f000000-0000-4000-8000-000000000025'), 'open',
  'E1 ปฏิเสธแล้วสิทธิ์แก้ยังไม่ถูกใช้');

-- ---------------------------------------------------------------------------
-- ฌ: สิทธิ์อ่าน (RLS + authorize_files)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select is((select count(*)::integer from public.submissions), 3, 'นักเรียนเห็นเฉพาะงานส่งของตน (S1: H1, H2, H4)');
select is((select count(*)::integer from public.attachments where submission_id is not null), 5, 'นักเรียนเห็นไฟล์งานส่งของตนเท่านั้น');
select is((select count(*)::integer from public.revision_permissions), 2, 'นักเรียนเห็นสิทธิ์แก้ของงานตน');
select is(public.authorize_files(pg_temp.fs(2, 3)), pg_temp.fs(2, 3), 'นักเรียนเจ้าของเปิดไฟล์งานส่งของตนได้');
select is(public.authorize_files(pg_temp.fs(13)), '{}'::uuid[], 'เปิดไฟล์งานส่งของเพื่อนไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is((select count(*)::integer from public.submissions), 7, 'ครูเจ้าของห้องเห็นงานส่งทั้งห้อง');
select is(public.authorize_files(pg_temp.fs(2, 3, 13)), pg_temp.fs(2, 3, 13), 'ครูเจ้าของห้องเปิดไฟล์งานส่งได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is((select count(*)::integer from public.submissions) + (select count(*)::integer from public.revision_permissions), 0,
  'ครูห้องอื่นไม่เห็นงานส่ง/สิทธิ์แก้');
select is(public.authorize_files(pg_temp.fs(2)), '{}'::uuid[], 'ครูห้องอื่นเปิดไฟล์งานส่งไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(2)), pg_temp.fs(2), 'ผู้ดูแลเปิดไฟล์งานส่งได้ (อ่าน — ไม่ต้องโหมดผู้ดูแล)');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at)
                    values (pg_temp.p(3), '6f000000-0000-4000-8000-000000000011', now(), now()) $$,
  '42501', null, 'นักเรียนเขียนตาราง submissions ตรงไม่ได้');

-- ---------------------------------------------------------------------------
-- ญ: ถูกเอาออกแล้วเข้าใหม่เห็นงานเดิม (โน้ต P2-05)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000013", "role": "authenticated"}';
insert into res values ('s3', public.submit_assignment(pg_temp.p(1), pg_temp.fs(14), 0, gen_random_uuid()));
set local role postgres;
delete from public.memberships where student_id = '6f000000-0000-4000-8000-000000000013';
set local role authenticated;
select throws_ok($$ select public.submit_assignment(pg_temp.p(1), pg_temp.fs(14, 15), 1, gen_random_uuid()) $$,
  'P0001', 'not_member', 'ถูกเอาออก → not_member');
select throws_ok($$ select public.create_upload_batch('submission', '7f000000-0000-4000-8000-000000000001', pg_temp.p(1),
  '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]', gen_random_uuid()) $$,
  'P0001', 'not_member', 'ถูกเอาออก → ขอ batch ไม่ได้ (not_member)');
select is((select count(*)::integer from public.submissions), 1, 'ถูกเอาออกแล้วงานส่งของตนยังอยู่และอ่านได้');
set local role postgres;
insert into public.memberships (classroom_id, student_id) values ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000013');
set local role authenticated;
insert into res values ('s3r', public.submit_assignment(pg_temp.p(1), pg_temp.fs(14, 15), 1, gen_random_uuid()));
select is(pg_temp.r('s3r', 'submission_id') || pg_temp.r('s3r', 'content_revision'),
  pg_temp.r('s3', 'submission_id') || '2'::jsonb, 'เข้าห้องใหม่: งานส่งเดิม (แถวเดิม) ส่งแก้ต่อได้ รุ่น 2');

-- ---------------------------------------------------------------------------
-- ฎ: ตัวกันช่องที่แก้ไม่ได้
-- ---------------------------------------------------------------------------
set local role postgres;
select throws_ok($$ update public.submissions set student_id = '6f000000-0000-4000-8000-000000000011'
                     where id = '5f000000-0000-4000-8000-000000000025' $$,
  'P0001', 'immutable_field', 'ย้ายงานส่งไปนักเรียนคนอื่นไม่ได้');
select throws_ok($$ update public.submissions set first_submitted_at = first_submitted_at + interval '1 minute'
                     where id = '5f000000-0000-4000-8000-000000000025' $$,
  'P0001', 'immutable_field', 'เวลาส่งแรกแก้ไม่ได้');
update public.submissions set reward_granted = true where id = '5f000000-0000-4000-8000-000000000025';
select throws_ok($$ update public.submissions set reward_granted = false where id = '5f000000-0000-4000-8000-000000000025' $$,
  'P0001', 'immutable_field', 'reward_granted ไม่ย้อนเป็น false');
select throws_ok($$ update public.revision_permissions set status = 'open', used_at = null, used_revision = null
                     where status = 'used' $$,
  'P0001', 'invalid_status_transition', 'สิทธิ์ที่ใช้แล้วกลับมาเปิดไม่ได้');
select throws_ok($$ insert into public.revision_permissions (submission_id, opened_by_account_id)
                    values ('5f000000-0000-4000-8000-000000000025', '3f000000-0000-4000-8000-000000000001') $$,
  '23505', null, 'สิทธิ์แก้ค้างได้ทีละหนึ่งต่องานส่ง');

select * from finish();
rollback;
