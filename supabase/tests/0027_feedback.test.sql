-- ทดสอบ 0027_feedback: open_revision_permission (K3), post_comment / retract_comment (F5, K5) — สิทธิ์ทุกบทบาท,
-- เปิดค้างได้ทีละหนึ่ง, ใช้แล้วเปิดใหม่ได้, ความคิดเห็นของนักเรียน/ครู, ยกเลิกเฉพาะของตน, RLS — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(38);

select is_empty(
  $$ select r || ' ' || f from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.require_post_teacher(uuid,boolean)', 'private.require_comment_student(uuid)',
                         'private.comment_json(public.comments)']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: ครู 1 (ห้อง 1), ครู 2 (ห้อง 2), ผู้ดูแล; ห้อง 1 สมาชิก N1 (บัญชี, ส่งแล้ว), N2 (บัญชี, ยังไม่ส่ง);
-- N3 (บัญชี) ส่งแล้วถูกเอาออก; N4 ไม่อยู่ห้องและไม่เคยส่ง · H1 การบ้านห้อง 1 · A1 ประกาศห้อง 1
insert into public.terms (id, name, status) values ('4d000000-0000-4000-8000-000000000001', 'ภาคทดสอบความคิดเห็น', 'active');
insert into public.term_control (term_id) values ('4d000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1d000000-0000-4000-8000-000000000001', 'ครูคิดเห็นหนึ่ง'), ('1d000000-0000-4000-8000-000000000002', 'ครูคิดเห็นสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3d000000-0000-4000-8000-000000000001', '2d000000-0000-4000-8000-000000000001', 'google', 'fb-1', 't27a@example.com', 'teacher', '1d000000-0000-4000-8000-000000000001'),
  ('3d000000-0000-4000-8000-000000000002', '2d000000-0000-4000-8000-000000000002', 'google', 'fb-2', 't27b@example.com', 'teacher', '1d000000-0000-4000-8000-000000000002'),
  ('3d000000-0000-4000-8000-000000000003', '2d000000-0000-4000-8000-000000000003', 'google', 'fb-3', 'a27@example.com', 'admin', null),
  ('3d000000-0000-4000-8000-000000000011', '2d000000-0000-4000-8000-000000000011', 'google', 'fb-11', 's27a@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000012', '2d000000-0000-4000-8000-000000000012', 'google', 'fb-12', 's27b@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000013', '2d000000-0000-4000-8000-000000000013', 'google', 'fb-13', 's27c@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6d000000-0000-4000-8000-000000000001', '927000000000271', 'หนึ่ง คิดเห็น', '3d000000-0000-4000-8000-000000000011'),
  ('6d000000-0000-4000-8000-000000000002', '927000000000272', 'สอง คิดเห็น', '3d000000-0000-4000-8000-000000000012'),
  ('6d000000-0000-4000-8000-000000000003', '927000000000273', 'สาม คิดเห็น', '3d000000-0000-4000-8000-000000000013'),
  ('6d000000-0000-4000-8000-000000000004', '927000000000274', 'สี่ คิดเห็น', null);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7d000000-0000-4000-8000-000000000001', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000001', 'เคมีคิดเห็น 1', 'ZZZZ77'),
  ('7d000000-0000-4000-8000-000000000002', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000002', 'เคมีคิดเห็น 2', 'ZZZZ78');
insert into public.memberships (classroom_id, student_id) values
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001'),
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000002');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8d000000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-000000000001', 'homework', 'งานคิดเห็น', '2026-09-20T01:00:00Z'),
  ('8d000000-0000-4000-8000-000000000002', '7d000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศคิดเห็น', '2026-09-21T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('8d000000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5d000000-0000-4000-8000-000000000001', '8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z'),
  ('5d000000-0000-4000-8000-000000000003', '8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000003', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z');

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ก: เปิดสิทธิ์แก้ (K3)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2d000000-0000-4000-8000-000000000001');
insert into res values ('p1', public.open_revision_permission('5d000000-0000-4000-8000-000000000001', 'c7000000-0000-4000-8000-000000000001'));
select is(pg_temp.r('p1') - 'permission_id' - 'opened_at' - 'submission_id', '{"status": "open", "already_open": false}'::jsonb,
  'ครูเปิดสิทธิ์แก้ได้');
select is(public.open_revision_permission('5d000000-0000-4000-8000-000000000001', 'c7000000-0000-4000-8000-000000000001'),
  pg_temp.r('p1'), 'กดซ้ำด้วย request key เดิมคืนผลเดิม');
insert into res values ('p1b', public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('p1b') -> 'permission_id', pg_temp.r('p1b') -> 'already_open'),
  jsonb_build_array(pg_temp.r('p1') -> 'permission_id', true), 'มีสิทธิ์ค้างอยู่แล้ว: คืนสิทธิ์เดิม ไม่สร้างใหม่');
select is((select count(*)::integer from public.revision_permissions where submission_id = '5d000000-0000-4000-8000-000000000001'), 1,
  'เปิดค้างได้ทีละหนึ่งสิทธิ์');
select is((select jsonb_build_array(r.status, r.opened_by_account_id) from public.revision_permissions r
            where r.id = (pg_temp.r('p1') ->> 'permission_id')::uuid), '["open", "3d000000-0000-4000-8000-000000000001"]'::jsonb,
  'นักเรียน/ครูอ่านสิทธิ์ผ่าน RLS ได้ และบันทึกผู้เปิด');
select throws_ok($$ select public.open_revision_permission('5d000000-0000-4000-8000-0000000000ff', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'งานส่งที่ไม่มี → forbidden (มีสิทธิ์ได้เฉพาะงานที่ส่งแล้ว)');

-- ใช้สิทธิ์แล้ว (ผลของ submit_assignment — 0020) → ครูเปิดใหม่ได้เป็นแถวใหม่
set local role postgres;
update public.revision_permissions set status = 'used', used_at = clock_timestamp(), used_revision = 2
 where submission_id = '5d000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into res values ('p2', public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('p2') -> 'already_open', pg_temp.r('p2') -> 'permission_id' = pg_temp.r('p1') -> 'permission_id'),
  '[false, false]'::jsonb, 'K3: ใช้สิทธิ์แล้วครูเปิดใหม่ได้ (แถวใหม่)');
select is(public.open_revision_permission('5d000000-0000-4000-8000-000000000003', gen_random_uuid()) -> 'status', '"open"',
  'เปิดสิทธิ์ให้นักเรียนที่ถูกเอาออกแต่มีงานส่งได้');

select pg_temp.as_user('2d000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นเปิดสิทธิ์ไม่ได้');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000011');
select throws_ok($$ select public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนเปิดสิทธิ์ไม่ได้');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลเปิดสิทธิ์ไม่ได้');
select is(public.open_revision_permission('5d000000-0000-4000-8000-000000000001', gen_random_uuid(), true) -> 'already_open',
  'true'::jsonb, 'ผู้ดูแลในโหมดผู้ดูแลเปิดสิทธิ์ได้');

-- ---------------------------------------------------------------------------
-- ข: ความคิดเห็นของนักเรียน
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2d000000-0000-4000-8000-000000000011');
insert into res values ('s1', public.post_comment('8d000000-0000-4000-8000-000000000001', null, '  ครูคะ ข้อ 3 ถามอะไร  ', 'c7000000-0000-4000-8000-000000000011'));
select is(pg_temp.r('s1') - 'comment_id' - 'created_at',
  '{"assignment_id": "8d000000-0000-4000-8000-000000000001", "student_id": "6d000000-0000-4000-8000-000000000001", "author_account_id": "3d000000-0000-4000-8000-000000000011", "author_role": "student", "body": "ครูคะ ข้อ 3 ถามอะไร", "retracted_at": null}'::jsonb,
  'นักเรียนเขียนในช่องของตัวเอง (ตัดช่องว่างหัวท้าย)');
select is(public.post_comment('8d000000-0000-4000-8000-000000000001', null, 'ครูคะ ข้อ 3 ถามอะไร', 'c7000000-0000-4000-8000-000000000011'),
  pg_temp.r('s1'), 'กดส่งซ้ำด้วย request key เดิมคืนข้อความเดิม ไม่สร้างซ้ำ');
select is(public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', 'ระบุตัวเองก็ได้', gen_random_uuid()) -> 'student_id',
  '"6d000000-0000-4000-8000-000000000001"', 'ส่ง student_id ของตัวเองได้');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000002', 'แอบเขียนช่องเพื่อน', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'เขียนในช่องของเพื่อนไม่ได้');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', null, '   ', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ข้อความว่างถูกปฏิเสธ');
select throws_ok(format($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', null, %L, gen_random_uuid()) $$, repeat('ก', 2001)),
  'P0001', 'comment_too_long', 'ข้อความเกิน 2,000 ตัวถูกปฏิเสธ');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000002', null, 'ประกาศ', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ประกาศไม่มีช่องความคิดเห็น');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000013');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', null, 'ยังเขียนได้ไหม', gen_random_uuid()) $$,
  'P0001', 'not_member', 'ถูกเอาออกแล้วเขียนไม่ได้');

-- ---------------------------------------------------------------------------
-- ค: ความคิดเห็นของครู
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2d000000-0000-4000-8000-000000000001');
insert into res values ('t2', public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000002', 'อย่าลืมส่งนะ', gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('t2') -> 'student_id', pg_temp.r('t2') -> 'author_role'),
  '["6d000000-0000-4000-8000-000000000002", "teacher"]'::jsonb, 'ครูเขียนถึงนักเรียนที่ยังไม่ส่งได้');
select is(public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000003', 'งานที่ส่งไว้ตรวจแล้ว', gen_random_uuid()) -> 'student_id',
  '"6d000000-0000-4000-8000-000000000003"', 'ครูเขียนถึงคนที่ถูกเอาออกแต่มีงานส่งได้');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000004', 'ไม่อยู่ห้อง', gen_random_uuid()) $$,
  'P0001', 'student_not_found', 'นักเรียนที่ไม่อยู่ในรายชื่อของงาน → student_not_found');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', null, 'ไม่ระบุ', gen_random_uuid()) $$,
  'P0001', 'student_not_found', 'ครูต้องระบุนักเรียน');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', 'ห้องอื่น', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นเขียนไม่ได้');
select is((select count(*)::integer from public.comments where assignment_id = '8d000000-0000-4000-8000-000000000001'), 0,
  'RLS: ครูห้องอื่นไม่เห็นความคิดเห็น');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', 'ดูแล', gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลเขียนไม่ได้');
select is(public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', 'ดูแลแทนครู', gen_random_uuid(), true) -> 'author_role',
  '"admin"', 'ผู้ดูแลในโหมดผู้ดูแลเขียนได้');

-- ---------------------------------------------------------------------------
-- ง: ยกเลิกข้อความ (F5) + RLS
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2d000000-0000-4000-8000-000000000011');
select throws_ok(format($$ select public.retract_comment(%L) $$, pg_temp.r('t2') ->> 'comment_id'),
  'P0001', 'forbidden', 'ยกเลิกข้อความของคนอื่นไม่ได้');
insert into res values ('s1x', public.retract_comment((pg_temp.r('s1') ->> 'comment_id')::uuid));
select is(jsonb_build_array(pg_temp.r('s1x') -> 'body', pg_temp.r('s1x') -> 'retracted_at' <> 'null'::jsonb),
  '[null, true]'::jsonb, 'ยกเลิกข้อความตัวเอง: ล้างข้อความ ตั้งเวลายกเลิก');
select is(public.retract_comment((pg_temp.r('s1') ->> 'comment_id')::uuid), pg_temp.r('s1x'), 'ยกเลิกซ้ำคืนผลเดิม');
select is((select jsonb_agg(c.body order by c.created_at) from public.comments c),
  '[null, "ระบุตัวเองก็ได้", "ดูแลแทนครู"]'::jsonb,
  'RLS: นักเรียนเห็นเฉพาะช่องตัวเอง ข้อความที่ยกเลิกไม่มีเนื้อความ');
select is((select count(*)::integer from public.comments where student_id <> '6d000000-0000-4000-8000-000000000001'), 0,
  'RLS: ไม่เห็นความคิดเห็นในช่องของเพื่อน');

select pg_temp.as_user('2d000000-0000-4000-8000-000000000001');
select is(public.retract_comment((pg_temp.r('t2') ->> 'comment_id')::uuid) -> 'body', 'null'::jsonb, 'ครูยกเลิกข้อความตัวเองได้');

-- K5: จบภาคเรียนแล้วนักเรียนเขียน/ยกเลิกไม่ได้ ครูยังเขียนได้
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select is(public.post_comment('8d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001', 'หลังจบภาค', gen_random_uuid()) -> 'author_role',
  '"teacher"', 'K5: จบภาคเรียนแล้วครูยังเขียนได้');
select pg_temp.as_user('2d000000-0000-4000-8000-000000000011');
select throws_ok($$ select public.post_comment('8d000000-0000-4000-8000-000000000001', null, 'หลังจบภาค', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'K5: จบภาคเรียนแล้วนักเรียนเขียนไม่ได้');
select throws_ok(format($$ select public.retract_comment(%L) $$,
    (select c.id from public.comments c where c.body = 'ระบุตัวเองก็ได้')),
  'P0001', 'term_ended', 'K5: จบภาคเรียนแล้วนักเรียนยกเลิกข้อความไม่ได้');

select * from finish();
rollback;
