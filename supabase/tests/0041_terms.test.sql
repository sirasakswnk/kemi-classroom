-- ทดสอบ 0041_terms: terms_end (J9, K5) / terms_start (1.2, I5) — สิทธิ์ ชื่อ หน้าจอเก่า คำขอซ้ำ
-- และกติกาเดียวกันใน RPC เดิมทุกจุด: นักเรียนส่งงาน/เขียนหรือยกเลิกความคิดเห็นไม่ได้ แต่สุ่ม/เลือกชิ้นแสดงได้;
-- ครูตรวจ/เขียนความคิดเห็นได้; งานเข้าเกณฑ์ยังได้โทเคนจนเริ่มเทอมใหม่ แล้วงานเทอมเก่าไม่ให้โทเคนเข้าเทอมใหม่
-- การตรวจงานชนการเริ่มเทอมจริงสองการเชื่อมต่อ: ops/concurrency/term-start.mjs (ฐานข้อมูลในเครื่องเท่านั้น)
-- ข้อมูลสมมติ rollback ตอนจบ — ไม่เปลี่ยนภาคเรียนจริงของฐานข้อมูล
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

select plan(53);

select is_empty(
  $$ select r from unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, 'private.term_state()', 'EXECUTE') $$,
  'term_state ใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: เทอม T1 (active, epoch เดิม) ครู 1 คน ผู้ดูแล 1 คน ห้อง C1 (T1)
-- S1 (บัญชี, สมาชิก C1, ยอด 3, มีเครื่องราง K1 แสดงข้างชื่อ) S2 (บัญชี, สมาชิก C1)
-- H1 (2 โทเคน) / H2 (3 โทเคน) การบ้าน C1 กำหนดส่งอนาคต — S1 ส่งทันทั้งสองงาน ยังไม่ตรวจ · CM ความคิดเห็นของ S1 ใน H1
insert into public.terms (id, name, status) values ('40410000-0000-4000-8000-000000000001', 'ภาคทดสอบเปลี่ยนเทอม', 'active');
insert into public.term_control (term_id) values ('40410000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
create temp table ctl0 on commit drop as select c.epoch from public.term_control c where c.singleton;
grant select on ctl0 to authenticated;
insert into public.teachers (id, display_name) values ('10410000-0000-4000-8000-000000000001', 'ครูเปลี่ยนเทอม');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30410000-0000-4000-8000-000000000001', '20410000-0000-4000-8000-000000000001', 'google', 'tm-1', 't41@example.com', 'teacher', '10410000-0000-4000-8000-000000000001'),
  ('30410000-0000-4000-8000-000000000002', '20410000-0000-4000-8000-000000000002', 'google', 'tm-2', 'a41@example.com', 'admin', null),
  ('30410000-0000-4000-8000-000000000011', '20410000-0000-4000-8000-000000000011', 'google', 'tm-11', 's41a@example.com', 'student', null),
  ('30410000-0000-4000-8000-000000000012', '20410000-0000-4000-8000-000000000012', 'google', 'tm-12', 's41b@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60410000-0000-4000-8000-000000000001', '941000000000411', 'หนึ่ง เปลี่ยนเทอม', '30410000-0000-4000-8000-000000000011'),
  ('60410000-0000-4000-8000-000000000002', '941000000000412', 'สอง เปลี่ยนเทอม', '30410000-0000-4000-8000-000000000012');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70410000-0000-4000-8000-000000000001', '40410000-0000-4000-8000-000000000001', '10410000-0000-4000-8000-000000000001', 'เคมีเปลี่ยนเทอม', 'ZZZZ4A');
insert into public.memberships (classroom_id, student_id) values
  ('70410000-0000-4000-8000-000000000001', '60410000-0000-4000-8000-000000000001'),
  ('70410000-0000-4000-8000-000000000001', '60410000-0000-4000-8000-000000000002');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80410000-0000-4000-8000-000000000001', '70410000-0000-4000-8000-000000000001', 'homework', 'H1', '2026-09-20T01:00:00Z'),
  ('80410000-0000-4000-8000-000000000002', '70410000-0000-4000-8000-000000000001', 'homework', 'H2', '2026-09-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, reward_tokens) values
  ('80410000-0000-4000-8000-000000000001', 10, '2027-06-30T13:00:00Z', 2),
  ('80410000-0000-4000-8000-000000000002', 10, '2027-06-30T13:00:00Z', 3);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50410000-0000-4000-8000-000000000001', '80410000-0000-4000-8000-000000000001', '60410000-0000-4000-8000-000000000001', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z'),
  ('50410000-0000-4000-8000-000000000002', '80410000-0000-4000-8000-000000000002', '60410000-0000-4000-8000-000000000001', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z');
insert into public.comments (id, assignment_id, student_id, author_account_id, body) values
  ('c0410000-0000-4000-8000-000000000001', '80410000-0000-4000-8000-000000000001', '60410000-0000-4000-8000-000000000001', '30410000-0000-4000-8000-000000000011', 'ครูคะ ข้อ 2');
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('b0410000-0000-4000-8000-000000000001', 1, 'เครื่องรางเปลี่ยนเทอม 1', '', 'ก', 9041),
  ('b0410000-0000-4000-8000-000000000002', 1, 'เครื่องรางเปลี่ยนเทอม 2', '', 'ข', 9042);
insert into public.owned_charms (student_id, charm_id) values
  ('60410000-0000-4000-8000-000000000001', 'b0410000-0000-4000-8000-000000000001');
insert into public.student_equipment (student_id, charm_id) values
  ('60410000-0000-4000-8000-000000000001', 'b0410000-0000-4000-8000-000000000001');
insert into public.wallets (student_id, term_id, balance) values
  ('60410000-0000-4000-8000-000000000001', '40410000-0000-4000-8000-000000000001', 3);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- ตรวจผ่านด้วย request key ใหม่ (ไฟล์รุ่น 1) ตามรุ่นผลตรวจที่มีตอนนี้
create function pg_temp.g(p_sub text) returns jsonb language sql as $$
  select public.grade_submission(p_sub::uuid, 8, true, null, null, 1,
           coalesce((select g.version from public.grades g where g.submission_id = p_sub::uuid), 0), gen_random_uuid())
$$;
grant execute on function pg_temp.g(text) to authenticated;
create function pg_temp.files() returns jsonb language sql immutable as
  $$ select '[{"file_name":"a.jpg","content_type":"image/jpeg","size_bytes":5000}]'::jsonb $$;
grant execute on function pg_temp.files() to authenticated;
-- ยอดของ S1 ในเทอม t (ไม่มีแถว = null)
create function pg_temp.bal(t text) returns integer language sql stable as $$
  select w.balance from public.wallets w where w.student_id = '60410000-0000-4000-8000-000000000001' and w.term_id = t::uuid
$$;
grant execute on function pg_temp.bal(text) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ก: สิทธิ์และค่าที่ส่งมา
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20410000-0000-4000-8000-000000000011');
select throws_ok($$ select public.terms_end('40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนจบภาคเรียนไม่ได้');
select throws_ok($$ select public.terms_start('ภาคใหม่', '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนเริ่มภาคเรียนไม่ได้');
select pg_temp.as_user('20410000-0000-4000-8000-000000000002');
select throws_ok($$ select public.terms_start('ภาคใหม่', '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลต้องอยู่ในโหมดผู้ดูแล');
select pg_temp.as_user('20410000-0000-4000-8000-000000000001');
select throws_ok($$ select public.terms_start('ภาคใหม่', '40410000-0000-4000-8000-000000000001', null) $$,
  'P0001', 'request_key_required', 'ต้องมี request key');
select throws_ok($$ select public.terms_start('   ', '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ชื่อว่างไม่ได้');
select throws_ok(format($$ select public.terms_start(%L, '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$, repeat('ก', 61)),
  'P0001', 'invalid_request', 'ชื่อเกิน 60 ตัวไม่ได้');
select throws_ok($$ select public.terms_start('ภาคใหม่', null, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ต้องส่งภาคเรียนที่หน้าจอเห็น');
select throws_ok($$ select public.terms_end(gen_random_uuid(), gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'จบจากหน้าจอที่เห็นภาคเรียนอื่น → stale_revision');
select throws_ok($$ select public.terms_start('ภาคใหม่', gen_random_uuid(), gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'เริ่มจากหน้าจอที่เห็นภาคเรียนอื่น → stale_revision');

-- ---------------------------------------------------------------------------
-- ข: จบภาคเรียน (J9) — คำขอซ้ำคืนผลเดิม, จบซ้ำด้วยคำขอใหม่ = term_ended
-- ---------------------------------------------------------------------------
insert into res values ('end', public.terms_end('40410000-0000-4000-8000-000000000001', 'e0410000-0000-4000-8000-000000000001'));
select is(pg_temp.r('end') - 'ended_at' - 'started_at',
  jsonb_build_object('term_id', '40410000-0000-4000-8000-000000000001', 'name', 'ภาคทดสอบเปลี่ยนเทอม',
                     'status', 'ended', 'epoch', (select epoch from ctl0)),
  'จบแล้ว: สถานะ ended ภาคเรียนเดิม epoch ไม่เปลี่ยน');
select ok((select c.status = 'ended' and c.ended_at = (pg_temp.r('end') ->> 'ended_at')::timestamptz
             and c.term_id = '40410000-0000-4000-8000-000000000001'
             from public.term_control c where c.singleton),
  'term_control: ended + ended_at ตรงผล');
select ok((select t.status = 'ended' and t.ended_at = (pg_temp.r('end') ->> 'ended_at')::timestamptz and t.superseded_at is null
             from public.terms t where t.id = '40410000-0000-4000-8000-000000000001'),
  'terms: ended_at = จุดเริ่มนับอายุข้อมูล (J9.2)');
select is(public.terms_end('40410000-0000-4000-8000-000000000001', 'e0410000-0000-4000-8000-000000000001'), pg_temp.r('end'),
  'กดจบซ้ำด้วยคำขอเดิม → ผลเดิม');
select throws_ok($$ select public.terms_end('40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'จบไปแล้ว คำขอใหม่ → term_ended');
select is(pg_temp.bal('40410000-0000-4000-8000-000000000001'), 3, 'จบภาคเรียนไม่ล้างยอด (K5)');

-- ---------------------------------------------------------------------------
-- ค: ระหว่าง ended — นักเรียน (K5): ส่งงาน/ความคิดเห็นไม่ได้ สุ่ม/เลือกชิ้นแสดงได้
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20410000-0000-4000-8000-000000000011');
select throws_ok($$ select public.create_upload_batch('submission', '70410000-0000-4000-8000-000000000001',
                    '80410000-0000-4000-8000-000000000001', pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ended: ขออัปโหลดไฟล์ส่งงานไม่ได้');
select throws_ok($$ select public.submit_assignment('80410000-0000-4000-8000-000000000001', array[gen_random_uuid()], 1, gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ended: ส่งงานไม่ได้');
select throws_ok($$ select public.post_comment('80410000-0000-4000-8000-000000000001', null, 'ส่งไม่ได้แล้วค่ะ', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ended: นักเรียนเขียนความคิดเห็นไม่ได้');
select throws_ok($$ select public.retract_comment('c0410000-0000-4000-8000-000000000001') $$,
  'P0001', 'term_ended', 'ended: นักเรียนยกเลิกความคิดเห็นไม่ได้');
select is((public.comment_thread('80410000-0000-4000-8000-000000000001', null) ->> 'can_write')::boolean, false,
  'ended: ช่องความคิดเห็นบอกนักเรียนว่าเขียนไม่ได้');
select is((public.get_draw_options() ->> 'balance')::integer, 3, 'ended: ยังเห็นยอดเดิม');
insert into res values ('draw', public.draw_charm(public.get_draw_options() ->> 'rates_key', gen_random_uuid()));
select is((select w.balance from public.wallets w
            where w.student_id = '60410000-0000-4000-8000-000000000001' and w.term_id = '40410000-0000-4000-8000-000000000001'), 2,
  'ended: สุ่มได้ ยอดลด 1 (K5)');
select lives_ok($$ select public.set_equipment('b0410000-0000-4000-8000-000000000001') $$,
  'ended: เลือกชิ้นที่แสดงข้างชื่อได้');

-- ครู: ตรวจ/ความคิดเห็นได้, งานเข้าเกณฑ์ยังได้โทเคน, การบ้านใหม่ไม่ได้ ประกาศได้
select pg_temp.as_user('20410000-0000-4000-8000-000000000001');
insert into res values ('g1', pg_temp.g('50410000-0000-4000-8000-000000000001'));
select is(jsonb_build_array(pg_temp.r('g1') -> 'reward_tokens_granted', pg_temp.r('g1') -> 'wallet_balance'), '[2, 4]'::jsonb,
  'ended: ตรวจผ่านงานที่ส่งทัน → ได้ 2 โทเคน เข้ายอดเทอมเดิม (K5)');
select lives_ok($$ select public.post_comment('80410000-0000-4000-8000-000000000001', '60410000-0000-4000-8000-000000000001', 'ครูตอบนะ', gen_random_uuid()) $$,
  'ended: ครูเขียนความคิดเห็นได้');
select throws_ok($$ select public.create_post('70410000-0000-4000-8000-000000000001',
                    jsonb_build_object('kind', 'homework', 'title', 'งานใหม่', 'body', '', 'full_score', 10, 'late_penalty_pct', 0,
                                       'reward_tokens', 1, 'due_at', '2027-06-30T13:00:00Z'), gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ended: โพสต์การบ้านใหม่ไม่ได้');
select lives_ok($$ select public.create_post('70410000-0000-4000-8000-000000000001',
                   jsonb_build_object('kind', 'announcement', 'title', 'แจ้งคะแนน', 'body', 'ดูคะแนนได้แล้ว'), gen_random_uuid()) $$,
  'ended: โพสต์ประกาศได้');

-- ---------------------------------------------------------------------------
-- ง: เริ่มภาคเรียนใหม่จาก ended — ชื่อซ้ำ, ผล, เทอมเดิมคง ended, คำขอซ้ำ/หน้าจอเก่า
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.terms_start('  ภาคทดสอบเปลี่ยนเทอม ', '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'term_name_taken', 'ชื่อซ้ำกับภาคเรียนที่มีอยู่ → term_name_taken');
insert into res values ('start', public.terms_start('  ภาคทดสอบใหม่  ', '40410000-0000-4000-8000-000000000001', 'e0410000-0000-4000-8000-000000000002'));
select is(pg_temp.r('start') - 'term_id' - 'started_at',
  jsonb_build_object('name', 'ภาคทดสอบใหม่', 'status', 'active', 'epoch', (select epoch from ctl0) + 1, 'ended_at', null,
                     'previous_term_id', '40410000-0000-4000-8000-000000000001'),
  'เริ่มแล้ว: ชื่อตัดช่องว่าง active epoch +1 บอกภาคเรียนก่อน');
select ok((select c.term_id = (pg_temp.r('start') ->> 'term_id')::uuid and c.status = 'active' and c.ended_at is null
             and c.started_at = (pg_temp.r('start') ->> 'started_at')::timestamptz
             from public.term_control c where c.singleton),
  'term_control ชี้ภาคเรียนใหม่');
select ok((select t.status = 'active' and t.started_at = (pg_temp.r('start') ->> 'started_at')::timestamptz
             from public.terms t where t.id = (pg_temp.r('start') ->> 'term_id')::uuid),
  'terms: แถวภาคเรียนใหม่ active');
select ok((select t.status = 'ended' and t.ended_at = (pg_temp.r('end') ->> 'ended_at')::timestamptz and t.superseded_at is null
             from public.terms t where t.id = '40410000-0000-4000-8000-000000000001'),
  'เริ่มจาก ended: เทอมเดิมคง ended ไม่เริ่มนับอายุใหม่');
select is(public.terms_start('  ภาคทดสอบใหม่  ', '40410000-0000-4000-8000-000000000001', 'e0410000-0000-4000-8000-000000000002'),
  pg_temp.r('start'), 'กดเริ่มซ้ำด้วยคำขอเดิม → ผลเดิม ไม่เกิดเทอมใหม่อีก');
select throws_ok($$ select public.terms_start('ภาคทดสอบใหม่อีก', '40410000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'หน้าจอเก่า (เห็นเทอมก่อน) กดเริ่มด้วยคำขอใหม่ → stale_revision');
select throws_ok($$ select public.terms_start('ภาคอื่น', '40410000-0000-4000-8000-000000000001', 'e0410000-0000-4000-8000-000000000002') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่ชื่อต่าง → request_key_conflict');
select is((select count(*)::integer from public.terms t where t.name like 'ภาคทดสอบใหม่%'), 1, 'มีภาคเรียนใหม่แถวเดียว');

-- ยอด/ของสะสมหลังเริ่มเทอมใหม่ (1.2)
select is(pg_temp.bal(pg_temp.r('start') ->> 'term_id'), null, 'ยอดเทอมใหม่ยังไม่มีแถว (= 0)');
select is(pg_temp.bal('40410000-0000-4000-8000-000000000001'), 4, 'แถวยอดเทอมเก่าเก็บไว้ ไม่ลบ');
select is((select count(*)::integer from public.owned_charms o where o.student_id = '60410000-0000-4000-8000-000000000001'), 2,
  'owned_charms คงอยู่ (ของเดิม + ที่สุ่มตอน ended)');
select is((select e.charm_id from public.student_equipment e where e.student_id = '60410000-0000-4000-8000-000000000001'),
  'b0410000-0000-4000-8000-000000000001'::uuid, 'ชิ้นที่แสดงข้างชื่อคงอยู่');

select pg_temp.as_user('20410000-0000-4000-8000-000000000011');
select is((public.get_draw_options() ->> 'balance')::integer, 0, 'นักเรียนเห็นยอด 0 ในเทอมใหม่');
select throws_ok($$ select public.draw_charm(public.get_draw_options() ->> 'rates_key', gen_random_uuid()) $$,
  'P0001', 'insufficient_balance', 'ยอด 0 สุ่มไม่ได้');
select throws_ok($$ select public.submit_assignment('80410000-0000-4000-8000-000000000002', array[gen_random_uuid()], 1, gen_random_uuid()) $$,
  'P0001', 'term_ended', 'งานในห้องของเทอมก่อน: ส่งไม่ได้');
select throws_ok($$ select public.post_comment('80410000-0000-4000-8000-000000000002', null, 'ยังถามได้ไหม', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'งานในห้องของเทอมก่อน: นักเรียนเขียนความคิดเห็นไม่ได้');

-- I5: ตรวจงานเทอมเก่าหลังเริ่มเทอมใหม่ → บันทึกคะแนนได้ ไม่ให้โทเคน
select pg_temp.as_user('20410000-0000-4000-8000-000000000001');
insert into res values ('g2', pg_temp.g('50410000-0000-4000-8000-000000000002'));
select is((pg_temp.r('g2') ->> 'reward_tokens_granted')::integer, 0, 'I5: งานเทอมเก่าตรวจผ่านหลังเริ่มเทอมใหม่ ไม่ได้โทเคน');
select ok((select g.raw_score = 8 and g.passed from public.grades g where g.submission_id = '50410000-0000-4000-8000-000000000002'),
  'I5: คะแนนบันทึกได้');
select ok(pg_temp.bal(pg_temp.r('start') ->> 'term_id') is null and pg_temp.bal('40410000-0000-4000-8000-000000000001') = 4,
  'I5: ยอดเทอมใหม่และเทอมเก่าไม่เปลี่ยน');
select lives_ok($$ select public.post_comment('80410000-0000-4000-8000-000000000002', '60410000-0000-4000-8000-000000000001', 'ครูตรวจแล้ว', gen_random_uuid()) $$,
  'ครูยังเขียนความคิดเห็นในงานเทอมก่อนได้');

-- ---------------------------------------------------------------------------
-- จ: เริ่มจาก active (ไม่ต้องจบก่อน) → เทอมเดิม superseded; ผู้ดูแลในโหมดผู้ดูแลทำแทนได้
-- ---------------------------------------------------------------------------
insert into res values ('start2', public.terms_start('ภาคทดสอบถัดไป', (pg_temp.r('start') ->> 'term_id')::uuid, gen_random_uuid()));
select ok((select t.status = 'superseded' and t.superseded_at = (pg_temp.r('start2') ->> 'started_at')::timestamptz and t.ended_at is null
             from public.terms t where t.id = (pg_temp.r('start') ->> 'term_id')::uuid),
  'เริ่มจาก active: เทอมเดิม superseded นับอายุจากเวลาที่กดเริ่ม');
select is((pg_temp.r('start2') ->> 'epoch')::integer, (select epoch from ctl0) + 2, 'epoch เพิ่มทุกครั้งที่เริ่มเทอม');
select pg_temp.as_user('20410000-0000-4000-8000-000000000002');
select is(public.terms_end((pg_temp.r('start2') ->> 'term_id')::uuid, gen_random_uuid(), true) ->> 'status', 'ended',
  'ผู้ดูแลในโหมดผู้ดูแลจบภาคเรียนแทนครูได้');

reset role;
-- เริ่ม/จบล็อก term_control แบบ exclusive (รอคำสั่งที่ถือ share) — การชนจริงทดสอบใน ops/concurrency/term-start.mjs
select ok((select bool_and(pg_get_functiondef(f) ~* 'from public\.term_control c where c\.singleton for update')
             from unnest(array['public.terms_start(text,uuid,uuid,boolean)'::regprocedure,
                               'public.terms_end(uuid,uuid,boolean)'::regprocedure]) f),
  'terms_start/terms_end ล็อก term_control FOR UPDATE');

select * from finish();
rollback;
