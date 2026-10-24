-- ทดสอบ 0043_notifications: กระดิ่งของเจ้าของเอง (my_notifications, unread_notification_count, mark_notifications_read)
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
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end
$$;

select plan(32);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู T (2 บัญชี) สอนห้อง R1 · ครู X สอนห้อง R2 · นักเรียน A, B อยู่ R1 (A อยู่ R2 ด้วย)
-- ผู้ดูแล D · บัญชี U ยังไม่ผูกชื่อ · งาน H1 (R1) งาน H2 (R2) ประกาศ P1 (R1)
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40430000-0000-4000-8000-000000000001', 'ภาคทดสอบกระดิ่ง', 'active');
insert into public.teachers (id, display_name) values
  ('10430000-0000-4000-8000-000000000001', 'ครูกระดิ่ง'),
  ('10430000-0000-4000-8000-000000000002', 'ครูห้องอื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30430000-0000-4000-8000-000000000001', '20430000-0000-4000-8000-000000000001', 'google', 'bell-t1', 't1-43@example.com', 'teacher', '10430000-0000-4000-8000-000000000001'),
  ('30430000-0000-4000-8000-000000000002', '20430000-0000-4000-8000-000000000002', 'google', 'bell-t2', 't2-43@example.com', 'teacher', '10430000-0000-4000-8000-000000000001'),
  ('30430000-0000-4000-8000-000000000003', '20430000-0000-4000-8000-000000000003', 'google', 'bell-x', 'x43@example.com', 'teacher', '10430000-0000-4000-8000-000000000002'),
  ('30430000-0000-4000-8000-00000000000d', '20430000-0000-4000-8000-00000000000d', 'google', 'bell-d', 'd43@example.com', 'admin', null),
  ('30430000-0000-4000-8000-00000000000a', '20430000-0000-4000-8000-00000000000a', 'google', 'bell-a', 'a43@example.com', 'student', null),
  ('30430000-0000-4000-8000-00000000000b', '20430000-0000-4000-8000-00000000000b', 'google', 'bell-b', 'b43@example.com', 'student', null),
  ('30430000-0000-4000-8000-000000000009', '20430000-0000-4000-8000-000000000009', 'google', 'bell-u', 'u43@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60430000-0000-4000-8000-00000000000a', '943000000001', 'ก กระดิ่ง', '30430000-0000-4000-8000-00000000000a'),
  ('60430000-0000-4000-8000-00000000000b', '943000000002', 'ข กระดิ่ง', '30430000-0000-4000-8000-00000000000b');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70430000-0000-4000-8000-000000000001', '40430000-0000-4000-8000-000000000001', '10430000-0000-4000-8000-000000000001', 'ห้องกระดิ่ง', 'QQQQ43'),
  ('70430000-0000-4000-8000-000000000002', '40430000-0000-4000-8000-000000000001', '10430000-0000-4000-8000-000000000002', 'ห้องอื่น', 'QQQR43');
insert into public.memberships (classroom_id, student_id) values
  ('70430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000a'),
  ('70430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000b'),
  ('70430000-0000-4000-8000-000000000002', '60430000-0000-4000-8000-00000000000a');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80430000-0000-4000-8000-000000000001', '70430000-0000-4000-8000-000000000001', 'homework', 'งานกระดิ่ง', '2026-10-20T01:00:00Z'),
  ('80430000-0000-4000-8000-000000000002', '70430000-0000-4000-8000-000000000002', 'homework', 'งานห้องอื่น', '2026-10-20T01:00:00Z'),
  ('80430000-0000-4000-8000-000000000003', '70430000-0000-4000-8000-000000000001', 'announcement', 'ประกาศกระดิ่ง', '2026-10-20T02:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('80430000-0000-4000-8000-000000000001', 10, '2026-11-01T13:00:00Z'),
  ('80430000-0000-4000-8000-000000000002', 10, '2026-11-01T13:00:00Z');
insert into public.comments (id, assignment_id, student_id, author_account_id, body, created_at) values
  ('c0430000-0000-4000-8000-000000000001', '80430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000a', '30430000-0000-4000-8000-000000000001', 'ความลับครูกระดิ่ง', '2026-10-21T01:00:00Z'),
  ('c0430000-0000-4000-8000-000000000002', '80430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000a', '30430000-0000-4000-8000-00000000000a', 'ความลับนักเรียนกระดิ่ง', '2026-10-21T02:00:00Z');

-- แจ้งเตือน (at ไล่เวลา): A มี 4 รายการใน R1 + 1 ใน R2, B 1 รายการ, ครู T 3 รายการ, ครู X 1 รายการ
insert into public.notifications (id, recipient_student_id, recipient_teacher_id, kind, post_id, comment_id,
                                  subject_student_id, level, dedupe_key, updated_at) values
  ('90430000-0000-4000-8000-0000000000a1', '60430000-0000-4000-8000-00000000000a', null, 'post_published', '80430000-0000-4000-8000-000000000001', null, null, null, 't43:a1', '2026-10-20T01:00:00Z'),
  ('90430000-0000-4000-8000-0000000000a2', '60430000-0000-4000-8000-00000000000a', null, 'post_published', '80430000-0000-4000-8000-000000000003', null, null, null, 't43:a2', '2026-10-20T02:00:00Z'),
  ('90430000-0000-4000-8000-0000000000a3', '60430000-0000-4000-8000-00000000000a', null, 'teacher_comment', '80430000-0000-4000-8000-000000000001', 'c0430000-0000-4000-8000-000000000001', null, null, 't43:a3', '2026-10-21T01:00:00Z'),
  ('90430000-0000-4000-8000-0000000000a4', '60430000-0000-4000-8000-00000000000a', null, 'due_reminder', '80430000-0000-4000-8000-000000000001', null, null, null, 't43:a4', '2026-10-31T13:00:00Z'),
  ('90430000-0000-4000-8000-0000000000a5', '60430000-0000-4000-8000-00000000000a', null, 'post_published', '80430000-0000-4000-8000-000000000002', null, null, null, 't43:a5', '2026-10-20T01:30:00Z'),
  ('90430000-0000-4000-8000-0000000000b1', '60430000-0000-4000-8000-00000000000b', null, 'post_published', '80430000-0000-4000-8000-000000000001', null, null, null, 't43:b1', '2026-10-20T01:00:00Z'),
  ('90430000-0000-4000-8000-0000000000c1', null, '10430000-0000-4000-8000-000000000001', 'pending_review', '80430000-0000-4000-8000-000000000001', null, null, null, 't43:t1', '2026-10-22T01:00:00Z'),
  ('90430000-0000-4000-8000-0000000000c2', null, '10430000-0000-4000-8000-000000000001', 'student_comment', '80430000-0000-4000-8000-000000000001', 'c0430000-0000-4000-8000-000000000002', '60430000-0000-4000-8000-00000000000a', null, 't43:t2', '2026-10-21T02:00:00Z'),
  ('90430000-0000-4000-8000-0000000000c3', null, '10430000-0000-4000-8000-000000000001', 'storage_threshold', null, null, null, 90, 't43:t3', '2026-10-23T01:00:00Z'),
  ('90430000-0000-4000-8000-0000000000d1', null, '10430000-0000-4000-8000-000000000002', 'pending_review', '80430000-0000-4000-8000-000000000002', null, null, null, 't43:x1', '2026-10-22T01:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50430000-0000-4000-8000-0000000000b1', '80430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000b', '2026-10-22T01:00:00Z', '2026-10-22T01:00:00Z');

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.ids(p jsonb) returns text[] language sql immutable as
  $$ select coalesce(array_agg(right(x ->> 'id', 2) order by ord), '{}') from jsonb_array_elements(p -> 'items') with ordinality t(x, ord) $$;
grant execute on function pg_temp.ids(jsonb) to authenticated;
create function pg_temp.item(p jsonb, p_suffix text) returns jsonb language sql immutable as
  $$ select x from jsonb_array_elements(p -> 'items') x where right(x ->> 'id', 2) = p_suffix $$;
grant execute on function pg_temp.item(jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. ตารางและข้อจำกัด (ในนาม postgres)
-- ---------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'notifications เปิด RLS');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'SELECT')
          and not has_table_privilege('anon', 'public.notifications', 'SELECT')
          and not has_table_privilege('authenticated', 'public.notifications', 'INSERT,UPDATE,DELETE'),
          'authenticated/anon ไม่มีสิทธิ์ตารางตรง — ผ่าน RPC เท่านั้น');
select throws_ok($$ insert into public.notifications (recipient_teacher_id, kind, post_id, dedupe_key)
                    values ('10430000-0000-4000-8000-000000000001', 'post_published', '80430000-0000-4000-8000-000000000001', 't43:bad1') $$,
                 '23514', null, 'ชนิดของนักเรียนส่งให้ครูไม่ได้');
select throws_ok($$ insert into public.notifications (recipient_student_id, recipient_teacher_id, kind, post_id, dedupe_key)
                    values ('60430000-0000-4000-8000-00000000000a', '10430000-0000-4000-8000-000000000001', 'post_published', '80430000-0000-4000-8000-000000000001', 't43:bad2') $$,
                 '23514', null, 'ผู้รับมีได้คนเดียว');
select throws_ok($$ insert into public.notifications (recipient_teacher_id, kind, post_id, dedupe_key)
                    values ('10430000-0000-4000-8000-000000000001', 'student_comment', '80430000-0000-4000-8000-000000000001', 't43:bad3') $$,
                 '23514', null, 'student_comment ต้องมีความคิดเห็นและนักเรียนที่พูดถึง');
select throws_ok($$ insert into public.notifications (recipient_teacher_id, kind, level, dedupe_key)
                    values ('10430000-0000-4000-8000-000000000001', 'storage_threshold', 85, 't43:bad4') $$,
                 '23514', null, 'ระดับพื้นที่ต้องเป็น 80/90/100');
select throws_ok($$ insert into public.notifications (recipient_student_id, kind, post_id, dedupe_key)
                    values ('60430000-0000-4000-8000-00000000000b', 'post_published', '80430000-0000-4000-8000-000000000001', 't43:b1') $$,
                 '23505', null, 'dedupe_key ซ้ำไม่ได้');
select ok(not exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name = 'notifications'
                         and column_name in ('body', 'snippet', 'message', 'text')),
          'ตารางไม่มีช่องเก็บข้อความ (ส่วน 11)');

-- ---------------------------------------------------------------------------
-- 2. นักเรียน A
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('20430000-0000-4000-8000-00000000000a');
select is(pg_temp.ids(public.my_notifications()), array['a4', 'a3', 'a2', 'a5', 'a1'],
          'A เห็นเฉพาะของตัวเองทุกห้องที่เป็นสมาชิก เรียงจากเหตุการณ์ล่าสุด');
select is((public.my_notifications() ->> 'unread_count')::integer, 5, 'A ยังไม่อ่าน 5');
select is(public.unread_notification_count(), 5, 'ตัวเลขบนกระดิ่งตรงกับรายการ');
select is(pg_temp.item(public.my_notifications(), 'a3') - 'at',
          jsonb_build_object('id', '90430000-0000-4000-8000-0000000000a3', 'kind', 'teacher_comment', 'read', false,
                             'relevant', true, 'post_id', '80430000-0000-4000-8000-000000000001', 'post_kind', 'homework',
                             'title', 'งานกระดิ่ง', 'classroom_id', '70430000-0000-4000-8000-000000000001',
                             'classroom_name', 'ห้องกระดิ่ง', 'due_at', '2026-11-01T13:00:00+00:00',
                             'comment_id', 'c0430000-0000-4000-8000-000000000001', 'comment_retracted', false,
                             'student_id', null, 'student_name', null, 'pending_count', null, 'level', null),
          'รายการความคิดเห็นของครูอ้างรหัสเป้าหมาย พร้อมชื่องาน/ห้องปัจจุบัน');
select ok(position('ความลับ' in public.my_notifications()::text) = 0, 'ผลไม่มีเนื้อความคิดเห็น');
select is(pg_temp.ids(public.my_notifications(null, 2)), array['a4', 'a3'], 'p_limit จำกัดจำนวน');
select is(pg_temp.ids(public.my_notifications('2026-10-21T01:00:00Z', 30)), array['a2', 'a5', 'a1'],
          'p_before ให้หน้าถัดไป (เก่ากว่าค่าที่ส่ง)');
select throws_ok($$ select public.my_notifications(null, 101) $$, 'P0001', 'invalid_request', 'p_limit เกิน 100 ถูกปฏิเสธ');
select is((pg_temp.item(public.my_notifications(), 'a4') ->> 'relevant')::boolean, true, 'เตือนใกล้ส่งยังเกี่ยวข้องเมื่อยังไม่ส่ง');

-- ทำเครื่องหมายอ่าน: ของตัวเองลด · รหัสของ B ถูกข้าม
select is(public.mark_notifications_read(array['90430000-0000-4000-8000-0000000000a1',
                                               '90430000-0000-4000-8000-0000000000b1']::uuid[]), 4,
          'อ่านรายการที่เลือกแล้วคืนยอดยังไม่อ่าน');
select is((pg_temp.item(public.my_notifications(), 'a1') ->> 'read')::boolean, true, 'รายการที่เลือกเป็นอ่านแล้ว');

-- ---------------------------------------------------------------------------
-- 3. นักเรียน B · ยังไม่ผูกชื่อ · ผู้ดูแล
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20430000-0000-4000-8000-00000000000b');
select is(pg_temp.ids(public.my_notifications()), array['b1'], 'B เห็นของตัวเองเท่านั้น');
select is(public.unread_notification_count(), 1, 'รหัสของ B ที่ A ส่งมาไม่ถูกทำเป็นอ่านแล้ว');
select pg_temp.as_user('20430000-0000-4000-8000-000000000009');
select is(public.my_notifications(), '{"unread_count": 0, "items": []}'::jsonb, 'บัญชีที่ยังไม่ผูกชื่อได้กระดิ่งว่าง');
select pg_temp.as_user('20430000-0000-4000-8000-00000000000d');
select is(public.unread_notification_count(), 0, 'ผู้ดูแลยังไม่มีกระดิ่ง (P6-04b)');

-- ---------------------------------------------------------------------------
-- 4. ครู T (บัญชีที่สองเห็นกระดิ่งเดียวกัน) · ครู X
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20430000-0000-4000-8000-000000000002');
select is(pg_temp.ids(public.my_notifications()), array['c3', 'c1', 'c2'],
          'ครูเห็นของห้องที่ตนสอน + พื้นที่เก็บไฟล์ ทุกบัญชีของครูคนเดียวกัน');
select is(pg_temp.item(public.my_notifications(), 'c1') ->> 'pending_count', '1', 'งานรอตรวจนับจากสถานะปัจจุบัน');
select is(pg_temp.item(public.my_notifications(), 'c2') ->> 'student_name', 'ก กระดิ่ง', 'ความคิดเห็นจากนักเรียนบอกชื่อนักเรียน');
select is((pg_temp.item(public.my_notifications(), 'c3') ->> 'level')::integer, 90, 'แจ้งพื้นที่บอกระดับ');
select is(public.mark_notifications_read(), 0, 'อ่านทั้งหมด');
select pg_temp.as_user('20430000-0000-4000-8000-000000000003');
select is(pg_temp.ids(public.my_notifications()), array['d1'], 'ครูอีกคนไม่เห็นของห้องที่ไม่ได้สอน และ “อ่านทั้งหมด” ของ T ไม่แตะของ X');

-- ---------------------------------------------------------------------------
-- 5. สถานะปัจจุบัน: ส่งแล้ว / ยกเลิกความคิดเห็น / ถูกเอาออกจากห้อง
-- ---------------------------------------------------------------------------
reset role;
set local role postgres;
insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at)
  values ('80430000-0000-4000-8000-000000000001', '60430000-0000-4000-8000-00000000000a', '2026-10-31T14:00:00Z', '2026-10-31T14:00:00Z');
update public.comments set body = null, retracted_at = '2026-10-22T00:00:00Z' where id = 'c0430000-0000-4000-8000-000000000001';
delete from public.memberships where classroom_id = '70430000-0000-4000-8000-000000000002'
                                 and student_id = '60430000-0000-4000-8000-00000000000a';
set local role authenticated;
select pg_temp.as_user('20430000-0000-4000-8000-00000000000a');
select is((pg_temp.item(public.my_notifications(), 'a4') ->> 'relevant')::boolean, false, 'ส่งแล้ว เตือนใกล้ส่งไม่เกี่ยวข้องแล้ว');
select is((pg_temp.item(public.my_notifications(), 'a3') ->> 'comment_retracted')::boolean, true,
          'ความคิดเห็นที่ยกเลิกแล้วบอกสถานะให้แสดง “ข้อความนี้ถูกยกเลิก”');
select is(pg_temp.ids(public.my_notifications()), array['a4', 'a3', 'a2', 'a1'],
          'ถูกเอาออกจากห้องแล้ว แจ้งเตือนของห้องนั้นหายทันที');

select * from finish();
rollback;
