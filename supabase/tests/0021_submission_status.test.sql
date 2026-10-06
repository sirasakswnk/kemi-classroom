-- ทดสอบ 0021_submission_status: submission_status (S03), my_work (S02/S01), create_upload_batch ปฏิเสธเมื่อส่งไม่ได้แน่นอน
-- และผลของ RPC อ่านสถานะตรงกับ submit_assignment (ใช้ฟังก์ชันตัดสินตัวเดียวกัน) — ข้อมูลสมมติ (@example.com) rollback ตอนจบ
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

select plan(44);

select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.require_current_term(uuid)',
                         'private.submission_timing(timestamp with time zone,boolean,timestamp with time zone)',
                         'private.submission_outcome(uuid,uuid,timestamp with time zone)',
                         'private.submission_verdict(uuid,uuid,timestamp with time zone)']) f,
            unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันตัดสินร่วมใช้ภายในเท่านั้น');
select ok((select position('private.submission_outcome(p_assignment_id, v_student_id, v_now)' in d) > 0
                  and position('submission_rule' in d) = 0
             from pg_get_functiondef('public.submit_assignment(uuid,uuid[],integer,uuid)'::regprocedure) d),
  'submit_assignment ตัดสินผ่าน submission_outcome (ไม่เรียก submission_rule เอง)');
select ok((select position('private.submission_outcome(v_post.id, v_student_id, clock_timestamp())' in d) > 0
             from pg_get_functiondef('public.create_upload_batch(text,uuid,uuid,jsonb,uuid,boolean)'::regprocedure) d),
  'create_upload_batch (submission) ตัดสินผ่าน submission_outcome ตัวเดียวกัน');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: S1, S2 สมาชิกห้อง 1 · S1, S3 สมาชิกห้อง 2
-- งานห้อง 1: H1 อีก 1 วัน · H2 เลยกำหนด (S1 ส่งทันไว้แล้ว ไม่มีสิทธิ์แก้, S2 ส่งแล้วมีสิทธิ์แก้) · H3 ปิดรับแล้ว
--            H4 เฉลยแล้ว+รับหลังเฉลย · H5 เฉลยแล้ว ไม่รับ · A6 ประกาศ · ห้อง 2: H7 อีก 2 วัน
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4d000000-0000-4000-8000-000000000001', 'ภาคทดสอบสถานะงาน', 'active');
insert into public.term_control (term_id) values ('4d000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('1d000000-0000-4000-8000-000000000001', 'ครูทดสอบสถานะงาน');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3d000000-0000-4000-8000-000000000001', '2d000000-0000-4000-8000-000000000001', 'google', 'ss-1', 'teacher21@example.com', 'teacher', '1d000000-0000-4000-8000-000000000001'),
  ('3d000000-0000-4000-8000-000000000011', '2d000000-0000-4000-8000-000000000011', 'google', 'ss-11', 's1-21@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000012', '2d000000-0000-4000-8000-000000000012', 'google', 'ss-12', 's2-21@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000013', '2d000000-0000-4000-8000-000000000013', 'google', 'ss-13', 's3-21@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6d000000-0000-4000-8000-000000000011', '920000000000211', 'หนึ่ง สถานะ', '3d000000-0000-4000-8000-000000000011'),
  ('6d000000-0000-4000-8000-000000000012', '920000000000212', 'สอง สถานะ', '3d000000-0000-4000-8000-000000000012'),
  ('6d000000-0000-4000-8000-000000000013', '920000000000213', 'สาม สถานะ', '3d000000-0000-4000-8000-000000000013');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7d000000-0000-4000-8000-000000000001', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000001', 'เคมีทดสอบสถานะ 1', 'ZZZZ52'),
  ('7d000000-0000-4000-8000-000000000002', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000001', 'เคมีทดสอบสถานะ 2', 'ZZZZ53');
insert into public.memberships (classroom_id, student_id) values
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000011'),
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000012'),
  ('7d000000-0000-4000-8000-000000000002', '6d000000-0000-4000-8000-000000000011'),
  ('7d000000-0000-4000-8000-000000000002', '6d000000-0000-4000-8000-000000000013');

create function pg_temp.p(n integer) returns uuid language sql immutable as
  $$ select ('8d000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create temp table due0 on commit drop as select date_trunc('minute', clock_timestamp()) as m;
grant select on due0 to authenticated;
insert into public.posts (id, classroom_id, kind, title)
select pg_temp.p(n), case when n = 7 then '7d000000-0000-4000-8000-000000000002'::uuid else '7d000000-0000-4000-8000-000000000001'::uuid end,
       case when n = 6 then 'announcement' else 'homework' end, 'งานสถานะ ' || n
  from generate_series(1, 7) n;
insert into public.assignments (post_id, full_score, reward_tokens, due_at, close_at, accept_after_solution)
select pg_temp.p(n), 10, 2,
       (select m from due0) + case n when 1 then interval '1 day' when 7 then interval '2 days' when 2 then interval '-1 day' else interval '-2 days' end,
       case when n = 3 then (select m from due0) - interval '1 day' end,
       n = 4
  from unnest(array[1, 2, 3, 4, 5, 7]) n;
insert into public.solutions (assignment_id, body, published_at) values
  (pg_temp.p(4), 'เฉลย', clock_timestamp()), (pg_temp.p(5), 'เฉลย', clock_timestamp());
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5d000000-0000-4000-8000-000000000012', pg_temp.p(2), '6d000000-0000-4000-8000-000000000011', (select m from due0) - interval '1 day 1 hour', (select m from due0) - interval '1 day 1 hour'),
  ('5d000000-0000-4000-8000-000000000022', pg_temp.p(2), '6d000000-0000-4000-8000-000000000012', (select m from due0) - interval '1 day 1 hour', (select m from due0) - interval '1 day 1 hour');
insert into public.revision_permissions (submission_id, opened_by_account_id) values
  ('5d000000-0000-4000-8000-000000000022', '3d000000-0000-4000-8000-000000000001');
-- ไฟล์ของ S1 ที่ผูกกับงานส่ง H2 + batch/asset สำหรับส่ง H1
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, files, reserved_bytes, expires_at) values
  ('9d000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000011', 'submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(1), '[{}]', 10, clock_timestamp() + interval '1 hour');
insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('bd000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000011', 'submission', null, 'staging/t21/1', 's1', 'files/t21/1.pdf', 'application/pdf', 4321, 'งานเก่า.pdf'),
  ('bd000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000011', 'submission', '9d000000-0000-4000-8000-000000000001', 'staging/t21/2', 's2', 'files/t21/2.jpg', 'image/jpeg', 1000, 'หน้า1.jpg');
update public.assets set status = 'ready', version_id = 'v', checksum = 'e', ready_at = clock_timestamp() where id::text like 'bd000000-%';
insert into public.attachments (asset_id, submission_id, position) values
  ('bd000000-0000-4000-8000-000000000001', '5d000000-0000-4000-8000-000000000012', 1);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text, p_path text) returns jsonb language sql stable as
  $$ select body #> string_to_array(p_path, '.') from res where label = p_label $$;
create function pg_temp.st(p_label text, p_n integer) returns void language sql as
  $$ insert into res values (p_label, public.submission_status(pg_temp.p(p_n))) $$;
create function pg_temp.row_of(p_label text, p_n integer) returns jsonb language sql stable as
  $$ select e from res, jsonb_array_elements(body) e where label = p_label and e ->> 'post_id' = pg_temp.p(p_n)::text $$;
grant execute on function pg_temp.p(integer), pg_temp.r(text, text), pg_temp.st(text, integer), pg_temp.row_of(text, integer)
  to authenticated;
create function pg_temp.files(n integer default 1) returns jsonb language sql immutable as
  $$ select '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]'::jsonb $$;
grant execute on function pg_temp.files(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- ก: submission_status (S1)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000011", "role": "authenticated"}';
insert into res values ('h1', public.submission_status(pg_temp.p(1)));
select is(pg_temp.r('h1', 'outcome') || pg_temp.r('h1', 'blocked') || pg_temp.r('h1', 'submission'),
  '["first_on_time", null, null]'::jsonb, 'H1 ยังไม่ส่ง ก่อนกำหนด → ส่งได้ (ทัน) ยังไม่มีงานส่ง');
select is(pg_temp.r('h1', 'intake') || pg_temp.r('h1', 'permission_open') || pg_temp.r('h1', 'solution_published'),
  '["open", false, false]'::jsonb, 'H1 เปิดรับ ไม่มีสิทธิ์แก้ค้าง ไม่มีเฉลย');
select is((pg_temp.r('h1', 'due_at') #>> '{}')::timestamptz, (select m from due0) + interval '1 day', 'คืนกำหนดส่ง');
select ok(abs(extract(epoch from (pg_temp.r('h1', 'server_now') #>> '{}')::timestamptz - clock_timestamp())) < 5,
  'คืนเวลาของเซิร์ฟเวอร์');
insert into res values ('h2', public.submission_status(pg_temp.p(2)));
select is(pg_temp.r('h2', 'outcome') || pg_temp.r('h2', 'blocked'), '[null, "resubmit_not_allowed"]'::jsonb,
  'H2 ส่งแล้ว เลยกำหนด ไม่มีสิทธิ์ → blocked resubmit_not_allowed');
select is(pg_temp.r('h2', 'submission') - 'submission_id' - 'first_submitted_at' - 'last_submitted_at',
  jsonb_build_object('content_revision', 1, 'first_after_solution', false, 'timing', 'on_time',
    'files', jsonb_build_array(jsonb_build_object('asset_id', 'bd000000-0000-4000-8000-000000000001', 'file_name', 'งานเก่า.pdf',
                                                  'content_type', 'application/pdf', 'size_bytes', 4321))),
  'H2 งานส่งปัจจุบัน: รุ่น ทัน (ส่งก่อนกำหนด) ไฟล์ที่ส่ง');
insert into res values ('h3', public.submission_status(pg_temp.p(3)));
select is(pg_temp.r('h3', 'blocked') || pg_temp.r('h3', 'intake'), '["submission_closed", "closed"]'::jsonb,
  'H3 ปิดรับแล้ว ยังไม่ส่ง → submission_closed');
insert into res values ('h4', public.submission_status(pg_temp.p(4)));
select is(pg_temp.r('h4', 'outcome') || pg_temp.r('h4', 'intake') || pg_temp.r('h4', 'solution_published'),
  '["first_after_solution", "after_solution", true]'::jsonb, 'H4 ช่วงรับหลังเฉลย → first_after_solution');
insert into res values ('h5', public.submission_status(pg_temp.p(5)));
select is(pg_temp.r('h5', 'blocked'), '"submission_closed"', 'H5 เฉลยแล้วไม่รับหลังเฉลย → submission_closed');
select throws_ok($$ select public.submission_status(pg_temp.p(6)) $$, 'P0001', 'forbidden', 'ประกาศ → forbidden');
select throws_ok($$ select public.submission_status('8d000000-0000-4000-8000-0000000000ff') $$, 'P0001', 'forbidden',
  'งานที่ไม่มีอยู่ → forbidden');

set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000012", "role": "authenticated"}';
insert into res values ('s2h2', public.submission_status(pg_temp.p(2)));
select is(pg_temp.r('s2h2', 'outcome') || pg_temp.r('s2h2', 'permission_open'), '["resubmit_permission", true]'::jsonb,
  'S2 H2 มีสิทธิ์แก้ค้าง → ส่งแก้ได้ (ใช้สิทธิ์)');
select is(pg_temp.r('s2h2', 'submission.files'), '[]'::jsonb, 'งานส่งที่ไม่มีไฟล์ผูก → files ว่าง');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000013", "role": "authenticated"}';
select throws_ok($$ select public.submission_status(pg_temp.p(1)) $$, 'P0001', 'not_member', 'ไม่ใช่สมาชิกห้อง → not_member');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.submission_status(pg_temp.p(1)) $$, 'P0001', 'forbidden', 'ครูเรียกไม่ได้ (เฉพาะนักเรียน)');
select throws_ok($$ select public.my_work(null) $$, 'P0001', 'forbidden', 'ครูเรียก my_work ไม่ได้');

-- ---------------------------------------------------------------------------
-- ข: my_work
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000011", "role": "authenticated"}';
insert into res values ('w1', public.my_work('7d000000-0000-4000-8000-000000000001'));
select is((select jsonb_agg(e -> 'title' order by o) from res, jsonb_array_elements(body) with ordinality x(e, o) where label = 'w1'),
  '["งานสถานะ 3", "งานสถานะ 4", "งานสถานะ 5", "งานสถานะ 2", "งานสถานะ 1"]'::jsonb,
  'ห้อง 1: เฉพาะการบ้าน (ไม่มีประกาศ) เรียงกำหนดส่งจากเร็วไปช้า');
select is(pg_temp.row_of('w1', 1) - 'post_id' - 'due_at',
  jsonb_build_object('classroom_id', '7d000000-0000-4000-8000-000000000001', 'classroom_name', 'เคมีทดสอบสถานะ 1',
    'title', 'งานสถานะ 1', 'close_at', null, 'reward_tokens', 2, 'submitted', false, 'timing', null,
    'last_submitted_at', null, 'content_revision', null, 'permission_open', false, 'outcome', 'first_on_time', 'blocked', null),
  'แถว H1: ยังไม่ส่ง ส่งได้ (ทัน) พร้อมรางวัลและชื่อห้อง');
select is(pg_temp.row_of('w1', 2) -> 'submitted' || (pg_temp.row_of('w1', 2) -> 'timing') || (pg_temp.row_of('w1', 2) -> 'blocked')
          || (pg_temp.row_of('w1', 2) -> 'content_revision'),
  '[true, "on_time", "resubmit_not_allowed", 1]'::jsonb, 'แถว H2: ส่งแล้ว ทัน ส่งแก้ไม่ได้ รุ่น 1');
select is(pg_temp.row_of('w1', 3) -> 'blocked', '"submission_closed"', 'แถว H3: ปิดรับแล้ว');
select is(pg_temp.row_of('w1', 4) -> 'outcome', '"first_after_solution"', 'แถว H4: ส่งได้หลังเฉลย');
insert into res values ('wall', public.my_work(null));
select is((select jsonb_array_length(body) from res where label = 'wall'), 6, 'ไม่ระบุห้อง = การบ้านทุกห้องที่เป็นสมาชิก (5 + 1)');
select is(pg_temp.row_of('wall', 7) -> 'classroom_name', '"เคมีทดสอบสถานะ 2"', 'มีงานห้อง 2 พร้อมชื่อห้อง (S01)');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000013", "role": "authenticated"}';
select throws_ok($$ select public.my_work('7d000000-0000-4000-8000-000000000001') $$, 'P0001', 'not_member',
  'ห้องที่ไม่ได้เป็นสมาชิก → not_member');
insert into res values ('s3all', public.my_work(null));
select is((select jsonb_array_length(body) from res where label = 's3all'), 1, 'S3 เห็นเฉพาะงานห้องที่เป็นสมาชิก');
set local role postgres;
delete from public.memberships where student_id = '6d000000-0000-4000-8000-000000000013';
set local role authenticated;
select is(public.my_work(null), '[]'::jsonb, 'ถูกเอาออกจากทุกห้อง → รายการว่าง');

-- ---------------------------------------------------------------------------
-- ค: create_upload_batch ปฏิเสธเมื่อส่งไม่ได้แน่นอน (รหัสเดียวกับ submit_assignment)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(3), pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'submission_closed', 'ปิดรับแล้ว ยังไม่เคยส่ง → submission_closed');
select throws_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(2), pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'resubmit_not_allowed', 'เลยกำหนด ส่งแล้ว ไม่มีสิทธิ์แก้ → resubmit_not_allowed');
select throws_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(5), pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'submission_closed', 'เฉลยแล้วไม่รับหลังเฉลย → submission_closed');
select lives_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(4), pg_temp.files(), gen_random_uuid()) $$,
  'ช่วงรับหลังเฉลย → ขอ batch ได้');
select lives_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(1), pg_temp.files(), gen_random_uuid()) $$,
  'ก่อนกำหนด ยังไม่ส่ง → ขอ batch ได้');
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000012", "role": "authenticated"}';
select lives_ok($$ select public.create_upload_batch('submission', '7d000000-0000-4000-8000-000000000001', pg_temp.p(2), pg_temp.files(), gen_random_uuid()) $$,
  'เลยกำหนดแต่มีสิทธิ์แก้ค้าง → ขอ batch ได้');
select throws_ok($$ select public.submit_assignment(pg_temp.p(2), '{bd000000-0000-4000-8000-000000000001}', 1, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'batch ผ่านแต่ไฟล์ของคนอื่น → submit ยังตรวจไฟล์ตามเดิม');

-- ---------------------------------------------------------------------------
-- ง: ผลของสถานะตรงกับ submit_assignment
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ select public.submit_assignment(pg_temp.p(3), '{bd000000-0000-4000-8000-000000000002}', 0, gen_random_uuid()) $$,
  'P0001', 'submission_file_unavailable', 'H3: ไฟล์จาก batch ของงานอื่นถูกตรวจก่อน (ลำดับเดิมของ submit)');
insert into res values ('sub1', public.submit_assignment(pg_temp.p(1), '{bd000000-0000-4000-8000-000000000002}', 0, gen_random_uuid()));
select is(pg_temp.r('sub1', 'outcome'), pg_temp.r('h1', 'outcome'), 'H1: submit ได้ผลเดียวกับที่สถานะบอกไว้ (first_on_time)');
select is(pg_temp.r('sub1', 'timing'), '"on_time"', 'submit คืน timing จากฟังก์ชันร่วม');
insert into res values ('h1b', public.submission_status(pg_temp.p(1)));
select is(pg_temp.r('h1b', 'outcome') || pg_temp.r('h1b', 'submission.content_revision') || pg_temp.r('h1b', 'submission.timing'),
  '["resubmit", 1, "on_time"]'::jsonb, 'หลังส่ง: สถานะเปลี่ยนเป็นส่งแก้ได้ (ก่อนกำหนด) รุ่น 1 ทัน');
select is(pg_temp.r('h1b', 'submission.last_submitted_at'), pg_temp.r('sub1', 'submitted_at'), 'เวลาที่บันทึกจริงตรงกับผลการส่ง');
select throws_ok($$ select public.submit_assignment(pg_temp.p(2), '{bd000000-0000-4000-8000-000000000001}', 1, gen_random_uuid()) $$,
  'P0001', 'resubmit_not_allowed', 'H2: submit ปฏิเสธด้วยรหัสเดียวกับ blocked ของสถานะ');
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp();
set local role authenticated;
insert into res values ('ended', public.submission_status(pg_temp.p(1)));
select is(pg_temp.r('ended', 'blocked') || pg_temp.r('ended', 'outcome'), '["term_ended", null]'::jsonb,
  'ภาคเรียนจบ → สถานะบอก term_ended (ยังอ่านงานส่งเดิมได้)');
select is(pg_temp.r('ended', 'submission.content_revision'), '1', 'ภาคเรียนจบแล้วยังเห็นงานส่งของตน');

select * from finish();
rollback;
