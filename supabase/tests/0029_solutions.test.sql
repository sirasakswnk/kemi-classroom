-- ทดสอบ 0029_solutions: save_solution / publish_solution — ร่างก่อนปิดรับ, เผยแพร่หลังปิดรับเท่านั้น, ช่วงรับหลังเฉลย,
-- K4 แก้หลังเผยแพร่ (คง published_at, คะแนน/first_after_solution ไม่เปลี่ยน), ไฟล์เฉลยเปิดได้เฉพาะครูจนเผยแพร่,
-- สิทธิ์ทุกบทบาท — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(39);

select is_empty(
  $$ select r || ' ' || f from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.solution_files_apply(uuid,uuid[],uuid)', 'private.solution_json(uuid)']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: ครู 1 (ห้อง 1), ครู 2, ผู้ดูแล; N1 สมาชิกห้อง 1 (ส่ง H1 แล้ว มีผลตรวจ)
-- H1 กำหนดผ่านแล้ว ไม่รับหลังเฉลย · H2 กำหนด 2099 รับหลังเฉลย · A1 ประกาศ
-- ไฟล์: 01, 02 เฉลยของครู 1 (ยังไม่ผูก) · 03 เฉลยของครู 2 · 04 โจทย์ของครู 1 (วัตถุประสงค์ผิด)
insert into public.terms (id, name, status) values ('4b000000-0000-4000-8000-000000000001', 'ภาคทดสอบเฉลย', 'active');
insert into public.term_control (term_id) values ('4b000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1b000000-0000-4000-8000-000000000001', 'ครูเฉลยหนึ่ง'), ('1b000000-0000-4000-8000-000000000002', 'ครูเฉลยสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3b000000-0000-4000-8000-000000000001', '2b000000-0000-4000-8000-000000000001', 'google', 'so-1', 't29a@example.com', 'teacher', '1b000000-0000-4000-8000-000000000001'),
  ('3b000000-0000-4000-8000-000000000002', '2b000000-0000-4000-8000-000000000002', 'google', 'so-2', 't29b@example.com', 'teacher', '1b000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000003', '2b000000-0000-4000-8000-000000000003', 'google', 'so-3', 'a29@example.com', 'admin', null),
  ('3b000000-0000-4000-8000-000000000011', '2b000000-0000-4000-8000-000000000011', 'google', 'so-11', 's29a@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6b000000-0000-4000-8000-000000000001', '929000000000291', 'หนึ่ง เฉลย', '3b000000-0000-4000-8000-000000000011');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7b000000-0000-4000-8000-000000000001', '4b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000001', 'เคมีเฉลย 1', 'ZZZZ82');
insert into public.memberships (classroom_id, student_id) values
  ('7b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8b000000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000001', 'homework', 'งานเฉลยหนึ่ง', '2026-09-20T01:00:00Z'),
  ('8b000000-0000-4000-8000-000000000002', '7b000000-0000-4000-8000-000000000001', 'homework', 'งานเฉลยสอง', '2026-09-21T01:00:00Z'),
  ('8b000000-0000-4000-8000-000000000003', '7b000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศเฉลย', '2026-09-22T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, accept_after_solution) values
  ('8b000000-0000-4000-8000-000000000001', 10, '2026-10-01T13:00:00Z', false),
  ('8b000000-0000-4000-8000-000000000002', 10, '2099-10-01T13:00:00Z', true);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z');
insert into public.grades (submission_id, raw_score, passed, timing, timing_due_at, timing_basis_at, timing_i1,
                           applied_penalty_pct, deduction, net_score, graded_revision, graded_at, graded_by_account_id)
values ('5b000000-0000-4000-8000-000000000001', 9, true, 'on_time', '2026-10-01T13:00:00Z', '2026-10-01T12:00:00Z', false,
        0, 0, 9, 1, '2026-10-02T01:00:00Z', '3b000000-0000-4000-8000-000000000001');
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ab000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000001', 'solution', 'staging/t29/1', 's', 'files/t29/1.pdf', 'application/pdf', 100, 'เฉลย1.pdf'),
  ('ab000000-0000-4000-8000-000000000002', '3b000000-0000-4000-8000-000000000001', 'solution', 'staging/t29/2', 's', 'files/t29/2.jpg', 'image/jpeg', 200, 'เฉลย2.jpg'),
  ('ab000000-0000-4000-8000-000000000003', '3b000000-0000-4000-8000-000000000002', 'solution', 'staging/t29/3', 's', 'files/t29/3.jpg', 'image/jpeg', 300, 'ของครูสอง.jpg'),
  ('ab000000-0000-4000-8000-000000000004', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t29/4', 's', 'files/t29/4.jpg', 'image/jpeg', 400, 'โจทย์.jpg');
update public.assets set status = 'ready', version_id = 'v', checksum = 'e', ready_at = clock_timestamp() where id::text like 'ab000000-%';

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.file_ids(p jsonb) returns uuid[] language sql immutable as
  $$ select coalesce(array_agg((e ->> 'asset_id')::uuid order by n), '{}') from jsonb_array_elements(p -> 'files') with ordinality x(e, n) $$;
grant execute on function pg_temp.file_ids(jsonb) to authenticated;

set local role authenticated;
select pg_temp.as_user('2b000000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- ก: ร่างเฉลยก่อนปิดรับ (H2 ยังเปิดรับ)
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', '   ', null, 0, gen_random_uuid()) $$,
  'P0001', 'post_body_required', 'เฉลยต้องมีข้อความหรือไฟล์');
select throws_ok(format($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', %L, null, 0, gen_random_uuid()) $$, repeat('ก', 10001)),
  'P0001', 'post_body_too_long', 'ข้อความเฉลยเกิน 10,000 ตัว');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', 'x', '{ab000000-0000-4000-8000-000000000003}', 0, gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'แนบไฟล์ของครูคนอื่นไม่ได้');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', 'x', '{ab000000-0000-4000-8000-000000000004}', 0, gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'แนบไฟล์วัตถุประสงค์อื่น (โจทย์) ไม่ได้');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', 'x', '{ab000000-0000-4000-8000-000000000001,ab000000-0000-4000-8000-000000000001}', 0, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'id ซ้ำในรายการ');
insert into res values ('d1', public.save_solution('8b000000-0000-4000-8000-000000000002', '  ข้อ 1 ตอบ ก  ',
  '{ab000000-0000-4000-8000-000000000002,ab000000-0000-4000-8000-000000000001}', 0, 'c9000000-0000-4000-8000-000000000001'));
select is(jsonb_build_array(pg_temp.r('d1') -> 'body', pg_temp.r('d1') -> 'published_at', pg_temp.r('d1') -> 'version',
                            pg_temp.r('d1') -> 'changed', pg_temp.r('d1') -> 'intake'),
  '["ข้อ 1 ตอบ ก", null, 1, true, "open"]'::jsonb, 'บันทึกร่างก่อนปิดรับได้');
select is(pg_temp.file_ids(pg_temp.r('d1')), '{ab000000-0000-4000-8000-000000000002,ab000000-0000-4000-8000-000000000001}'::uuid[],
  'ไฟล์เฉลยตามลำดับที่ครูจัด');
select is(public.save_solution('8b000000-0000-4000-8000-000000000002', 'ข้อ 1 ตอบ ก',
  '{ab000000-0000-4000-8000-000000000002,ab000000-0000-4000-8000-000000000001}', 0, 'c9000000-0000-4000-8000-000000000001'),
  pg_temp.r('d1'), 'กดซ้ำด้วย request key เดิมคืนผลเดิม');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000002', 'แท็บอื่น', null, 0, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'มีเฉลยแล้วแต่หน้าจอเห็นว่ายังไม่มี → stale_revision');
insert into res values ('d_same', public.save_solution('8b000000-0000-4000-8000-000000000002', 'ข้อ 1 ตอบ ก', null, 1, gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('d_same') -> 'version', pg_temp.r('d_same') -> 'changed', pg_temp.r('d_same') -> 'updated_at' = pg_temp.r('d1') -> 'updated_at'),
  '[1, false, true]'::jsonb, 'ไม่มีอะไรเปลี่ยน: ไม่ขยับ version/เวลาแก้ (ไม่ส่ง files = คงชุดเดิม)');

select throws_ok($$ select public.publish_solution('8b000000-0000-4000-8000-000000000002', 1, gen_random_uuid()) $$,
  'P0001', 'close_required', 'ยังเปิดรับ: เผยแพร่เฉลยไม่ได้');

-- นักเรียนยังไม่เห็นเฉลยและไฟล์เฉลย
select pg_temp.as_user('2b000000-0000-4000-8000-000000000011');
select is((select count(*)::integer from public.solutions where assignment_id = '8b000000-0000-4000-8000-000000000002'), 0,
  'RLS: นักเรียนไม่เห็นเฉลยที่ยังไม่เผยแพร่');
select is(public.authorize_files('{ab000000-0000-4000-8000-000000000001,ab000000-0000-4000-8000-000000000002}'), '{}'::uuid[],
  'นักเรียนขอลิงก์ไฟล์เฉลยก่อนเผยแพร่ไม่ได้');
select pg_temp.as_user('2b000000-0000-4000-8000-000000000001');
select is(public.authorize_files('{ab000000-0000-4000-8000-000000000001,ab000000-0000-4000-8000-000000000002}'),
  '{ab000000-0000-4000-8000-000000000001,ab000000-0000-4000-8000-000000000002}'::uuid[], 'ครูขอลิงก์ไฟล์เฉลยได้ตลอด');

-- ---------------------------------------------------------------------------
-- ข: ปิดรับแล้วเผยแพร่ (H2 รับหลังเฉลย → ช่วงรับหลังเฉลย)
-- ---------------------------------------------------------------------------
select is(public.close_assignment('8b000000-0000-4000-8000-000000000002', null, gen_random_uuid()) -> 'intake', '"closed"', 'ปิดรับทันที');
select throws_ok($$ select public.publish_solution('8b000000-0000-4000-8000-000000000002', 0, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'เผยแพร่จากหน้าจอที่เห็นเฉลยรุ่นเก่า → stale_revision');
insert into res values ('pub', public.publish_solution('8b000000-0000-4000-8000-000000000002', 1, 'c9000000-0000-4000-8000-000000000002'));
select is(jsonb_build_array(pg_temp.r('pub') -> 'published_at' <> 'null'::jsonb, pg_temp.r('pub') -> 'updated_at' = pg_temp.r('pub') -> 'published_at',
                            pg_temp.r('pub') -> 'version', pg_temp.r('pub') -> 'intake', pg_temp.r('pub') -> 'already_published'),
  '[true, true, 2, "after_solution", false]'::jsonb, 'เผยแพร่หลังปิดรับ: งานรับหลังเฉลยเข้าช่วงรับหลังเฉลย');
select is(public.publish_solution('8b000000-0000-4000-8000-000000000002', 1, 'c9000000-0000-4000-8000-000000000002'), pg_temp.r('pub'),
  'กดซ้ำด้วย request key เดิมคืนผลเดิม');
insert into res values ('pub2', public.publish_solution('8b000000-0000-4000-8000-000000000002', 2, gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('pub2') -> 'already_published', pg_temp.r('pub2') -> 'published_at' = pg_temp.r('pub') -> 'published_at'),
  '[true, true]'::jsonb, 'เผยแพร่แล้วกดอีก: คืนสถานะเดิม ไม่เผยแพร่ซ้ำ');
set local role postgres;
select throws_ok($$ update public.assignments set accept_after_solution = false where post_id = '8b000000-0000-4000-8000-000000000002' $$,
  'P0001', 'after_solution_locked', 'เผยแพร่แล้ว “รับหลังเฉลย” ล็อก');
set local role authenticated;

select pg_temp.as_user('2b000000-0000-4000-8000-000000000011');
select is((select body from public.solutions where assignment_id = '8b000000-0000-4000-8000-000000000002'), 'ข้อ 1 ตอบ ก',
  'นักเรียนเห็นเฉลยหลังเผยแพร่');
select is(public.authorize_files('{ab000000-0000-4000-8000-000000000001}'), '{ab000000-0000-4000-8000-000000000001}'::uuid[],
  'นักเรียนขอลิงก์ไฟล์เฉลยหลังเผยแพร่ได้');
select is(public.submission_status('8b000000-0000-4000-8000-000000000002') -> 'outcome', '"first_after_solution"',
  'ช่วงรับหลังเฉลย: ส่งครั้งแรกได้ (สาย ไม่มีโทเคน)');

-- ---------------------------------------------------------------------------
-- ค: H1 (ไม่รับหลังเฉลย, เลยกำหนดแต่ยังไม่ปิดรับ) + K4 แก้หลังเผยแพร่
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2b000000-0000-4000-8000-000000000001');
insert into res values ('h1d', public.save_solution('8b000000-0000-4000-8000-000000000001', 'เฉลยงานหนึ่ง', null, 0, gen_random_uuid()));
select throws_ok($$ select public.publish_solution('8b000000-0000-4000-8000-000000000001', 1, gen_random_uuid()) $$,
  'P0001', 'close_required', 'เลยกำหนดแต่ยังไม่ปิดรับ: ต้องปิดรับก่อน');
select is(public.close_assignment('8b000000-0000-4000-8000-000000000001', null, gen_random_uuid()) -> 'intake', '"closed"', 'ปิดรับ H1');
insert into res values ('h1p', public.publish_solution('8b000000-0000-4000-8000-000000000001', 1, gen_random_uuid()));
select is(pg_temp.r('h1p') -> 'intake', '"closed"', 'ไม่รับหลังเฉลย: เผยแพร่แล้วยังปิดรับ');
insert into res values ('h1e', public.save_solution('8b000000-0000-4000-8000-000000000001', 'เฉลยงานหนึ่ง (แก้ข้อ 2)',
  null, 2, gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('h1e') -> 'published_at' = pg_temp.r('h1p') -> 'published_at',
                            (pg_temp.r('h1e') ->> 'updated_at')::timestamptz > (pg_temp.r('h1p') ->> 'published_at')::timestamptz,
                            pg_temp.r('h1e') -> 'version', pg_temp.r('h1e') -> 'intake'),
  '[true, true, 3, "closed"]'::jsonb, 'K4: แก้หลังเผยแพร่ คง published_at เลื่อนเวลาแก้ล่าสุด สถานะรับงานไม่เปลี่ยน');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000001', 'x', '{ab000000-0000-4000-8000-000000000002}', 3, gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'ไฟล์ที่ผูกกับเฉลยงานอื่นอยู่ใช้ไม่ได้');
set local role postgres;
select is((select jsonb_build_array(s.first_after_solution, g.net_score, g.timing, g.version)
             from public.submissions s join public.grades g on g.submission_id = s.id
            where s.id = '5b000000-0000-4000-8000-000000000001'), '[false, 9, "on_time", 1]'::jsonb,
  'K4: เผยแพร่/แก้เฉลยไม่เปลี่ยน first_after_solution หรือผลตรวจ');
set local role authenticated;
-- เอาไฟล์ออกจากเฉลยที่เผยแพร่แล้ว: นักเรียนเปิดไฟล์นั้นไม่ได้อีก (เหลือเปิดได้เฉพาะเจ้าของ)
select is(pg_temp.file_ids(public.save_solution('8b000000-0000-4000-8000-000000000002', 'ข้อ 1 ตอบ ก', '{ab000000-0000-4000-8000-000000000002}', 2, gen_random_uuid())),
  '{ab000000-0000-4000-8000-000000000002}'::uuid[], 'เอาไฟล์ออกจากเฉลยได้');
select pg_temp.as_user('2b000000-0000-4000-8000-000000000011');
select is(public.authorize_files('{ab000000-0000-4000-8000-000000000001}'), '{}'::uuid[], 'ไฟล์ที่เอาออกแล้วนักเรียนเปิดไม่ได้');

-- ---------------------------------------------------------------------------
-- ง: สิทธิ์
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000001', 'x', null, 3, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนบันทึกเฉลยไม่ได้');
select throws_ok($$ select public.publish_solution('8b000000-0000-4000-8000-000000000001', 3, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนเผยแพร่เฉลยไม่ได้');
select pg_temp.as_user('2b000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000001', 'x', null, 3, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นบันทึกเฉลยไม่ได้');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000003', 'x', null, 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ประกาศไม่มีเฉลย');
select pg_temp.as_user('2b000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000003', 'x', null, 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูเจ้าของห้อง: ประกาศไม่มีเฉลย');
select pg_temp.as_user('2b000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.save_solution('8b000000-0000-4000-8000-000000000001', 'x', null, 3, gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลบันทึกเฉลยไม่ได้');
select is(public.save_solution('8b000000-0000-4000-8000-000000000001', 'แก้โดยผู้ดูแล', null, 3, gen_random_uuid(), true) -> 'version',
  '4'::jsonb, 'ผู้ดูแลในโหมดผู้ดูแลแก้เฉลยได้');

select * from finish();
rollback;
