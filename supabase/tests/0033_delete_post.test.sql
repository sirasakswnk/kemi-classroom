-- ทดสอบ 0033_delete_post: ลบการบ้าน/ประกาศแบบ cascade (N4) — ยอดตรวจซ้ำ (preview_changed), ไม่มีแถวค้าง, ไฟล์ทุกตัวเข้าคิวลบแบบ
-- ระบุ version, สิทธิ์ (นักเรียน/ครูห้องอื่น/ผู้ดูแลนอกโหมด), ใบรับคำขอซ้ำ, ธง maintenance_locks, ยอดพื้นที่ลดหลังงานลบเสร็จ —
-- ข้อมูลสมมติ rollback ตอนจบ
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

select plan(34);

-- ครู 1 ห้อง 1, ครู 2 (ห้อง 2), ผู้ดูแล; S1, S2 สมาชิกห้อง 1
insert into public.terms (id, name, status) values ('4e300000-0000-4000-8000-000000000001', 'ภาคทดสอบลบ', 'active');
insert into public.term_control (term_id) values ('4e300000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e300000-0000-4000-8000-000000000001', 'ครูลบหนึ่ง'), ('1e300000-0000-4000-8000-000000000002', 'ครูลบสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e300000-0000-4000-8000-000000000001', '2e300000-0000-4000-8000-000000000001', 'google', 'dp-1', 'd33a@example.com', 'teacher', '1e300000-0000-4000-8000-000000000001'),
  ('3e300000-0000-4000-8000-000000000002', '2e300000-0000-4000-8000-000000000002', 'google', 'dp-2', 'd33b@example.com', 'teacher', '1e300000-0000-4000-8000-000000000002'),
  ('3e300000-0000-4000-8000-000000000003', '2e300000-0000-4000-8000-000000000003', 'google', 'dp-3', 'd33c@example.com', 'admin', null),
  ('3e300000-0000-4000-8000-000000000011', '2e300000-0000-4000-8000-000000000011', 'google', 'dp-11', 'd33s1@example.com', 'student', null),
  ('3e300000-0000-4000-8000-000000000012', '2e300000-0000-4000-8000-000000000012', 'google', 'dp-12', 'd33s2@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e300000-0000-4000-8000-000000000001', '933000000000331', 'หนึ่ง ลบงาน', '3e300000-0000-4000-8000-000000000011'),
  ('6e300000-0000-4000-8000-000000000002', '933000000000332', 'สอง ลบงาน', '3e300000-0000-4000-8000-000000000012');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e300000-0000-4000-8000-000000000001', '4e300000-0000-4000-8000-000000000001', '1e300000-0000-4000-8000-000000000001', 'เคมีลบ 1', 'ZZZZ93'),
  ('7e300000-0000-4000-8000-000000000002', '4e300000-0000-4000-8000-000000000001', '1e300000-0000-4000-8000-000000000002', 'เคมีลบ 2', 'ZZZZ94');
insert into public.memberships (classroom_id, student_id) values
  ('7e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000001'),
  ('7e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000002');
-- H1 = งานที่จะลบ, H2 = งานที่ต้องไม่ถูกแตะ, A1 = ประกาศ
insert into public.posts (id, classroom_id, kind, title, body, published_at) values
  ('8e300000-0000-4000-8000-000000000001', '7e300000-0000-4000-8000-000000000001', 'homework', 'งานที่จะลบ', null, '2026-09-20T01:00:00Z'),
  ('8e300000-0000-4000-8000-000000000002', '7e300000-0000-4000-8000-000000000001', 'homework', 'งานที่ไม่ถูกแตะ', null, '2026-09-21T01:00:00Z'),
  ('8e300000-0000-4000-8000-000000000003', '7e300000-0000-4000-8000-000000000001', 'announcement', 'ประกาศที่จะลบ', 'เนื้อหา', '2026-09-22T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('8e300000-0000-4000-8000-000000000001', 10, '2026-10-01T13:00:00Z'),
  ('8e300000-0000-4000-8000-000000000002', 10, '2026-10-01T13:00:00Z');
insert into public.solutions (assignment_id, body, published_at) values
  ('8e300000-0000-4000-8000-000000000001', 'เฉลย', '2026-10-02T01:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5e300000-0000-4000-8000-0000000000a1', '8e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000001', '2026-10-01T14:00:00Z', '2026-10-01T14:00:00Z'),
  ('5e300000-0000-4000-8000-0000000000a2', '8e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000002', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z'),
  ('5e300000-0000-4000-8000-0000000000b1', '8e300000-0000-4000-8000-000000000002', '6e300000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z');
-- ความคิดเห็นของ H1: ครูถึง S1 (เหตุผลการหัก), S1 ถึงครู, ข้อความที่ถูกยกเลิก 1; ของ H2 หนึ่งข้อความ
insert into public.comments (id, assignment_id, student_id, author_account_id, body, retracted_at) values
  ('c3300000-0000-4000-8000-000000000001', '8e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000001', '3e300000-0000-4000-8000-000000000001', 'ปรับการหักเป็น 20%', null),
  ('c3300000-0000-4000-8000-000000000002', '8e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000001', '3e300000-0000-4000-8000-000000000011', 'ขอบคุณค่ะ', null),
  ('c3300000-0000-4000-8000-000000000003', '8e300000-0000-4000-8000-000000000001', '6e300000-0000-4000-8000-000000000001', '3e300000-0000-4000-8000-000000000011', null, '2026-10-03T01:00:00Z'),
  ('c3300000-0000-4000-8000-000000000004', '8e300000-0000-4000-8000-000000000002', '6e300000-0000-4000-8000-000000000001', '3e300000-0000-4000-8000-000000000001', 'ของงานอื่น', null);
insert into public.grades (submission_id, raw_score, passed, penalty_override_pct, override_comment_id, timing, timing_due_at,
                           timing_basis_at, timing_i1, applied_penalty_pct, deduction, net_score, graded_revision, graded_at, graded_by_account_id) values
  ('5e300000-0000-4000-8000-0000000000a1', 9, true, 20, 'c3300000-0000-4000-8000-000000000001', 'late', '2026-10-01T13:00:00Z', '2026-10-01T14:00:00Z', false, 20, 1, 8, 1, '2026-10-03T01:00:00Z', '3e300000-0000-4000-8000-000000000001'),
  ('5e300000-0000-4000-8000-0000000000a2', 7, true, null, null, 'on_time', '2026-10-01T13:00:00Z', '2026-09-29T01:00:00Z', false, 0, 0, 7, 1, '2026-10-03T01:00:00Z', '3e300000-0000-4000-8000-000000000001'),
  ('5e300000-0000-4000-8000-0000000000b1', 5, true, null, null, 'on_time', '2026-10-01T13:00:00Z', '2026-09-29T01:00:00Z', false, 0, 0, 5, 1, '2026-10-03T01:00:00Z', '3e300000-0000-4000-8000-000000000001');
insert into public.revision_permissions (submission_id, status, opened_by_account_id) values
  ('5e300000-0000-4000-8000-0000000000a1', 'open', '3e300000-0000-4000-8000-000000000001');
-- batch ของ H1 ที่ยังค้าง (นักเรียนอัปโหลดไว้แต่ยังไม่ได้ส่ง)
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, reserved_bytes, expires_at) values
  ('ba300000-0000-4000-8000-000000000001', '3e300000-0000-4000-8000-000000000011', 'submission', '7e300000-0000-4000-8000-000000000001',
   '8e300000-0000-4000-8000-000000000001', 9100, clock_timestamp() + interval '1 hour');
-- ไฟล์: โจทย์ H1 (101), เฉลย H1 (102), งานส่ง S1 สองไฟล์ (103, 104), งานส่ง S2 (105), ประกาศ A1 (106) → ผูกกับสิ่งที่จะถูกลบ 6 ไฟล์
--       ไฟล์ของ H2 (201 โจทย์, 202 งานส่ง) ต้องไม่ถูกแตะ; ไฟล์ค้างใน batch ของ H1: พร้อมใช้ที่ไม่ผูก (301) และ copying (302)
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name, upload_batch_id) values
  ('ae300000-0000-4000-8000-000000000101', '3e300000-0000-4000-8000-000000000001', 'post', 'staging/t33/101', 's', 'files/t33/101.pdf', 'application/pdf', 1000, 'โจทย์ H1.pdf', null),
  ('ae300000-0000-4000-8000-000000000102', '3e300000-0000-4000-8000-000000000001', 'solution', 'staging/t33/102', 's', 'files/t33/102.pdf', 'application/pdf', 2000, 'เฉลย H1.pdf', null),
  ('ae300000-0000-4000-8000-000000000103', '3e300000-0000-4000-8000-000000000011', 'submission', 'staging/t33/103', 's', 'files/t33/103.jpg', 'image/jpeg', 3000, 'ส่ง S1 ก.jpg', null),
  ('ae300000-0000-4000-8000-000000000104', '3e300000-0000-4000-8000-000000000011', 'submission', 'staging/t33/104', 's', 'files/t33/104.pdf', 'application/pdf', 4000, 'ส่ง S1 ข.pdf', null),
  ('ae300000-0000-4000-8000-000000000105', '3e300000-0000-4000-8000-000000000012', 'submission', 'staging/t33/105', 's', 'files/t33/105.jpg', 'image/jpeg', 5000, 'ส่ง S2.jpg', null),
  ('ae300000-0000-4000-8000-000000000106', '3e300000-0000-4000-8000-000000000001', 'post', 'staging/t33/106', 's', 'files/t33/106.jpg', 'image/jpeg', 6000, 'ประกาศ.jpg', null),
  ('ae300000-0000-4000-8000-000000000201', '3e300000-0000-4000-8000-000000000001', 'post', 'staging/t33/201', 's', 'files/t33/201.pdf', 'application/pdf', 7000, 'โจทย์ H2.pdf', null),
  ('ae300000-0000-4000-8000-000000000202', '3e300000-0000-4000-8000-000000000011', 'submission', 'staging/t33/202', 's', 'files/t33/202.jpg', 'image/jpeg', 8000, 'ส่ง H2.jpg', null),
  ('ae300000-0000-4000-8000-000000000301', '3e300000-0000-4000-8000-000000000011', 'submission', 'staging/t33/301', 's', 'files/t33/301.jpg', 'image/jpeg', 9000, 'ค้างพร้อมใช้.jpg', 'ba300000-0000-4000-8000-000000000001'),
  ('ae300000-0000-4000-8000-000000000302', '3e300000-0000-4000-8000-000000000011', 'submission', 'staging/t33/302', 's', 'files/t33/302.jpg', 'image/jpeg', 100, 'ค้างกำลังคัดลอก.jpg', 'ba300000-0000-4000-8000-000000000001');
update public.assets set status = 'ready', version_id = 'v-' || right(id::text, 3), checksum = 'e', ready_at = clock_timestamp()
 where id::text like 'ae300000-%' and right(id::text, 3) <> '302';
update public.assets set version_id = 'v-302' where id = 'ae300000-0000-4000-8000-000000000302';
insert into public.attachments (asset_id, post_id, position) values
  ('ae300000-0000-4000-8000-000000000101', '8e300000-0000-4000-8000-000000000001', 1),
  ('ae300000-0000-4000-8000-000000000106', '8e300000-0000-4000-8000-000000000003', 1),
  ('ae300000-0000-4000-8000-000000000201', '8e300000-0000-4000-8000-000000000002', 1);
insert into public.attachments (asset_id, solution_id, position) values
  ('ae300000-0000-4000-8000-000000000102', '8e300000-0000-4000-8000-000000000001', 1);
insert into public.attachments (asset_id, submission_id, position) values
  ('ae300000-0000-4000-8000-000000000103', '5e300000-0000-4000-8000-0000000000a1', 1),
  ('ae300000-0000-4000-8000-000000000104', '5e300000-0000-4000-8000-0000000000a1', 2),
  ('ae300000-0000-4000-8000-000000000105', '5e300000-0000-4000-8000-0000000000a2', 1),
  ('ae300000-0000-4000-8000-000000000202', '5e300000-0000-4000-8000-0000000000b1', 1);

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
-- ยอดที่คาดไว้ของ H1 (งานส่ง 2, ผลตรวจ 2, ความคิดเห็นที่ยังไม่ถูกยกเลิก 2, ไฟล์ที่ผูก 5 = โจทย์ 1 + เฉลย 1 + งานส่ง 3)
create function pg_temp.h1_expected(p_over jsonb default '{}') returns jsonb language sql immutable as
  $$ select '{"submissions": 2, "grades": 2, "comments": 2, "files": 5}'::jsonb || p_over $$;
grant execute on function pg_temp.h1_expected(jsonb) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ยอดที่จะถูกลบ
select pg_temp.as_user('2e300000-0000-4000-8000-000000000001');
select is(public.post_delete_preview('8e300000-0000-4000-8000-000000000001') - 'post_id' - 'classroom_id',
  '{"kind": "homework", "title": "งานที่จะลบ", "submissions": 2, "grades": 2, "comments": 2, "files": 5}'::jsonb,
  'ยอด: งานส่ง 2, ผลตรวจ 2, ความคิดเห็น 2 (ไม่นับที่ยกเลิกแล้ว), ไฟล์ที่ผูก 5 (โจทย์ + เฉลย + งานส่งทุกคน)');
select is(public.post_delete_preview('8e300000-0000-4000-8000-000000000003') - 'post_id' - 'classroom_id',
  '{"kind": "announcement", "title": "ประกาศที่จะลบ", "submissions": 0, "grades": 0, "comments": 0, "files": 1}'::jsonb,
  'ประกาศ: ไม่มีงานส่ง/ผลตรวจ/ความคิดเห็น มีไฟล์แนบ 1');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000003');
select is(public.post_delete_preview('8e300000-0000-4000-8000-000000000001') -> 'files', '5'::jsonb, 'ผู้ดูแลดูยอดได้โดยไม่ต้องโหมดผู้ดูแล');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000002');
select throws_ok($$ select public.post_delete_preview('8e300000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden', 'ครูห้องอื่นดูยอดไม่ได้');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000011');
select throws_ok($$ select public.post_delete_preview('8e300000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden', 'นักเรียนดูยอดไม่ได้');

-- ---------------------------------------------------------------------------
-- สิทธิ์ลบ
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนลบไม่ได้');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000002');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นลบไม่ได้');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000003');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลลบไม่ได้');
select pg_temp.as_user('2e300000-0000-4000-8000-000000000001');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-0000000000ff', pg_temp.h1_expected(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'โพสต์ที่ไม่มี → forbidden');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), null) $$,
  'P0001', 'request_key_required', 'ต้องมี request key');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', '{"submissions": 2}', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ยอดที่คาดไว้ไม่ครบ → invalid_request');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001',
    '{"submissions": 2, "grades": 2, "comments": 2, "files": "5"}', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ยอดที่ไม่ใช่จำนวนเต็ม → invalid_request');

-- ---------------------------------------------------------------------------
-- ยอดไม่ตรง → preview_changed และไม่มีอะไรถูกลบ
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected('{"submissions": 1}'), gen_random_uuid()) $$,
  'P0001', 'preview_changed', 'จำนวนงานส่งต่าง → preview_changed');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected('{"files": 4}'), gen_random_uuid()) $$,
  'P0001', 'preview_changed', 'จำนวนไฟล์ต่าง → preview_changed');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected('{"comments": 3}'), gen_random_uuid()) $$,
  'P0001', 'preview_changed', 'จำนวนความคิดเห็นต่าง → preview_changed');
set local role postgres;
select is((select count(*)::integer from public.posts where id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.submissions where assignment_id = '8e300000-0000-4000-8000-000000000001'), 3,
  'preview_changed ไม่ลบอะไร (โพสต์ 1 + งานส่ง 2 ยังอยู่)');

-- ---------------------------------------------------------------------------
-- ลบจริง
create temp table before_used (bytes bigint);
insert into before_used select private.storage_used_bytes();
set local role authenticated;
select pg_temp.as_user('2e300000-0000-4000-8000-000000000001');
create temp table key1 (k uuid);
insert into key1 values ('e0000000-0000-4000-8000-000000000001');
grant select on key1 to authenticated;
insert into res select 'del', public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), (select k from key1));
select is(pg_temp.r('del') - 'post_id' - 'classroom_id',
  '{"kind": "homework", "title": "งานที่จะลบ", "queued_files": 6,
    "deleted": {"submissions": 2, "grades": 2, "comments": 3, "revision_permissions": 1, "files": 5}}'::jsonb,
  'ลบสำเร็จ: ลบแถวทั้งหมด (ความคิดเห็นรวมที่ยกเลิก 3) และไฟล์เข้าคิว 6 (5 ที่ผูก + 1 ค้างพร้อมใช้ใน batch)');

set local role postgres;
select is((select count(*)::integer from public.posts where id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.assignments where post_id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.solutions where assignment_id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.submissions where assignment_id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.comments where assignment_id = '8e300000-0000-4000-8000-000000000001')
        + (select count(*)::integer from public.grades where submission_id in ('5e300000-0000-4000-8000-0000000000a1', '5e300000-0000-4000-8000-0000000000a2'))
        + (select count(*)::integer from public.revision_permissions where submission_id in ('5e300000-0000-4000-8000-0000000000a1', '5e300000-0000-4000-8000-0000000000a2'))
        + (select count(*)::integer from public.attachments where asset_id::text like 'ae300000-%101' or asset_id::text like 'ae300000-%102'
                                                                or asset_id::text like 'ae300000-%103' or asset_id::text like 'ae300000-%104'
                                                                or asset_id::text like 'ae300000-%105')
        + (select count(*)::integer from public.upload_batches where post_id = '8e300000-0000-4000-8000-000000000001'), 0,
  'ไม่มีแถวค้าง: posts, assignments, solutions, submissions, comments, grades, revision_permissions, attachments, upload_batches');
select is((select count(*)::integer from public.posts where id = '8e300000-0000-4000-8000-000000000002')
        + (select count(*)::integer from public.submissions where assignment_id = '8e300000-0000-4000-8000-000000000002')
        + (select count(*)::integer from public.comments where assignment_id = '8e300000-0000-4000-8000-000000000002')
        + (select count(*)::integer from public.grades where submission_id = '5e300000-0000-4000-8000-0000000000b1')
        + (select count(*)::integer from public.attachments where post_id = '8e300000-0000-4000-8000-000000000002'
                                                               or submission_id = '5e300000-0000-4000-8000-0000000000b1'), 6,
  'งานอื่นไม่ถูกแตะ: โพสต์ 1 + งานส่ง 1 + ความคิดเห็น 1 + ผลตรวจ 1 + ไฟล์ 2');
select is((select count(*)::integer from public.posts where id = '8e300000-0000-4000-8000-000000000003'), 1, 'ประกาศไม่ถูกแตะตอนลบการบ้าน');

-- ไฟล์: 6 ตัวเข้า deleting พร้อมเวลา + งานลบแบบระบุ version; ไฟล์ของงานอื่นยัง ready; copying ที่ค้างปล่อยให้ sweeper จัดการ
select is((select count(*)::integer from public.assets where status = 'deleting' and id::text like 'ae300000-%'), 6, 'ไฟล์ 6 ตัวเป็น deleting');
select is((select array_agg(right(id::text, 3) order by id) from public.assets where status = 'deleting' and id::text like 'ae300000-%'),
  array['101', '102', '103', '104', '105', '301'], 'ได้แก่ โจทย์ เฉลย งานส่ง 3 ไฟล์ และไฟล์ค้างพร้อมใช้ (ไม่ใช่ประกาศ/งานอื่น/copying)');
select is((select count(*)::integer from public.assets where status = 'deleting' and delete_requested_at is null), 0, 'ทุกตัวมีเวลาขอลบ');
select is((select jsonb_agg(jsonb_build_object('v', j.payload ->> 'version_id', 'reason', j.payload ->> 'reason') order by j.payload ->> 'asset_id')
             from private.jobs j where j.kind = 'delete_asset' and j.dedupe_key like 'ae300000-%'),
  '[{"v": "v-101", "reason": "post_deleted"}, {"v": "v-102", "reason": "post_deleted"}, {"v": "v-103", "reason": "post_deleted"},
    {"v": "v-104", "reason": "post_deleted"}, {"v": "v-105", "reason": "post_deleted"}, {"v": "v-301", "reason": "post_deleted"}]'::jsonb,
  'งานลบ delete_asset 6 งาน ระบุ version_id ของแต่ละไฟล์ (ไม่ลบ B2 ตรงจากคำสั่งนี้)');
select is((select string_agg(right(id::text, 3) || ':' || status, ',' order by id)
             from public.assets where id::text like 'ae300000-%' and right(id::text, 3) in ('106', '201', '202', '302')),
  '106:ready,201:ready,202:ready,302:copying', 'ไฟล์ของประกาศ/งานอื่น ยัง ready; copying ยังเป็น copying');

-- ตัวทำงานลบ: มีธง maintenance_locks → รอ; ไม่มี → ลบแถว asset และยอดพื้นที่ลด
update private.jobs set status = 'running', locked_at = clock_timestamp()
 where kind = 'delete_asset' and dedupe_key = 'ae300000-0000-4000-8000-000000000101';
insert into private.maintenance_locks (name, reason, expires_at) values ('t33-backup', 'ทดสอบ', clock_timestamp() + interval '30 minutes');
select is(public.delete_asset_begin((select id from private.jobs where dedupe_key = 'ae300000-0000-4000-8000-000000000101' and kind = 'delete_asset')) ->> 'action',
  'defer', 'ระหว่างมีธง maintenance_locks งานลบรอ (เลื่อนไปหลังธงหมดอายุ)');
delete from private.maintenance_locks where name = 't33-backup';
update private.jobs set status = 'running', locked_at = clock_timestamp()
 where kind = 'delete_asset' and dedupe_key like 'ae300000-%';
create temp table fin (n integer);
do $$
declare
  j record;
  v_begin jsonb;
  v_n integer := 0;
begin
  for j in select id from private.jobs where kind = 'delete_asset' and dedupe_key like 'ae300000-%' order by id loop
    v_begin := public.delete_asset_begin(j.id);
    if v_begin ->> 'action' = 'delete' then
      perform public.delete_asset_finish(j.id);
      v_n := v_n + 1;
    end if;
  end loop;
  insert into fin values (v_n);
end
$$;
select is((select n from fin), 6, 'ตัวทำงานลบได้ทั้ง 6 งาน (action = delete → finish)');
select is((select count(*)::integer from public.assets where id::text like 'ae300000-%' and right(id::text, 3) in ('101', '102', '103', '104', '105', '301')), 0,
  'แถว asset ของไฟล์ที่ลบแล้วหายไป');
select is((select count(*)::integer from private.jobs where kind = 'delete_asset' and dedupe_key like 'ae300000-%' and status = 'done'), 6, 'งานลบเป็น done ทั้ง 6');
select is((select bytes from before_used) - private.storage_used_bytes(), 1000::bigint + 2000 + 3000 + 4000 + 5000 + 9000,
  'ยอดพื้นที่ลดลงเท่าขนาดไฟล์ที่ลบแล้ว (ไม่นับไฟล์ที่ยังไม่ลบ/ของงานอื่น)');

-- คำขอซ้ำด้วย request key เดิม (เน็ตหลุดแล้วกดอีกครั้ง) ได้ผลเดิม ไม่ใช่ forbidden
set local role authenticated;
select pg_temp.as_user('2e300000-0000-4000-8000-000000000001');
select is(public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), (select k from key1)), pg_temp.r('del'),
  'ส่งซ้ำด้วย request key เดิมคืนผลเดิม');
select throws_ok($$ select public.delete_post('8e300000-0000-4000-8000-000000000001', pg_temp.h1_expected(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ลบซ้ำด้วย key ใหม่ (โพสต์หายแล้ว) → forbidden');

-- ประกาศ: คำสั่งเดียวกัน
select is(public.delete_post('8e300000-0000-4000-8000-000000000003', '{"submissions": 0, "grades": 0, "comments": 0, "files": 1}', gen_random_uuid()) - 'post_id' - 'classroom_id',
  '{"kind": "announcement", "title": "ประกาศที่จะลบ", "queued_files": 1,
    "deleted": {"submissions": 0, "grades": 0, "comments": 0, "revision_permissions": 0, "files": 1}}'::jsonb,
  'ลบประกาศด้วยคำสั่งเดียวกัน (ไฟล์แนบเข้าคิว 1)');

-- ผู้ดูแลในโหมดผู้ดูแลลบแทนครูได้ แม้จบภาคเรียนแล้ว (N4 ลบได้ตลอด)
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select pg_temp.as_user('2e300000-0000-4000-8000-000000000003');
select is(public.delete_post('8e300000-0000-4000-8000-000000000002', '{"submissions": 1, "grades": 1, "comments": 1, "files": 2}', gen_random_uuid(), true) -> 'deleted' ->> 'submissions',
  '1', 'ผู้ดูแลในโหมดผู้ดูแลลบได้ แม้จบภาคเรียนแล้ว');

select * from finish();
rollback;
