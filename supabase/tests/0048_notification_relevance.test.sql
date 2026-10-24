-- ทดสอบ 0048_notification_relevance: กระดิ่งตามสถานะปัจจุบัน — หมดความเกี่ยวข้องแล้วจาง (relevant false) และไม่นับยังไม่อ่าน
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

select plan(20);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู T สอนห้อง R · นักเรียน A อยู่ R · งาน H1 (เปิดรับ) H2 (ครูปิดรับแล้ว) H3 (ไม่มีงานส่ง) · ประกาศ P
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40480000-0000-4000-8000-000000000001', 'ภาคทดสอบความเกี่ยวข้อง', 'active');
insert into public.teachers (id, display_name) values ('10480000-0000-4000-8000-000000000001', 'ครูความเกี่ยวข้อง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30480000-0000-4000-8000-000000000001', '20480000-0000-4000-8000-000000000001', 'google', 'rel-t', 't48@example.com', 'teacher', '10480000-0000-4000-8000-000000000001'),
  ('30480000-0000-4000-8000-00000000000a', '20480000-0000-4000-8000-00000000000a', 'google', 'rel-a', 'a48@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60480000-0000-4000-8000-00000000000a', '948000000001', 'ก ความเกี่ยวข้อง', '30480000-0000-4000-8000-00000000000a');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70480000-0000-4000-8000-000000000001', '40480000-0000-4000-8000-000000000001', '10480000-0000-4000-8000-000000000001', 'ห้องความเกี่ยวข้อง', 'QQQQ48');
insert into public.memberships (classroom_id, student_id) values
  ('70480000-0000-4000-8000-000000000001', '60480000-0000-4000-8000-00000000000a');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80480000-0000-4000-8000-000000000001', '70480000-0000-4000-8000-000000000001', 'homework', 'งานเปิดรับ', '2026-10-20T01:00:00Z'),
  ('80480000-0000-4000-8000-000000000002', '70480000-0000-4000-8000-000000000001', 'homework', 'งานปิดรับ', '2026-10-20T01:00:00Z'),
  ('80480000-0000-4000-8000-000000000003', '70480000-0000-4000-8000-000000000001', 'homework', 'งานไม่มีคนส่ง', '2026-10-20T01:00:00Z'),
  ('80480000-0000-4000-8000-000000000004', '70480000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ', '2026-10-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('80480000-0000-4000-8000-000000000001', 10, '2099-11-01T13:00:00Z'),
  ('80480000-0000-4000-8000-000000000002', 10, '2099-11-01T13:00:00Z'),
  ('80480000-0000-4000-8000-000000000003', 10, '2099-11-01T13:00:00Z');
update public.assignments set closed_at = '2026-10-21T01:00:00Z' where post_id = '80480000-0000-4000-8000-000000000002';
insert into public.comments (id, assignment_id, student_id, author_account_id, body, created_at, retracted_at) values
  ('c0480000-0000-4000-8000-000000000001', '80480000-0000-4000-8000-000000000001', '60480000-0000-4000-8000-00000000000a', '30480000-0000-4000-8000-000000000001', 'ครูยังอยู่', '2026-10-21T01:00:00Z', null),
  ('c0480000-0000-4000-8000-000000000002', '80480000-0000-4000-8000-000000000001', '60480000-0000-4000-8000-00000000000a', '30480000-0000-4000-8000-000000000001', null, '2026-10-21T02:00:00Z', '2026-10-21T03:00:00Z'),
  ('c0480000-0000-4000-8000-000000000003', '80480000-0000-4000-8000-000000000001', '60480000-0000-4000-8000-00000000000a', '30480000-0000-4000-8000-00000000000a', null, '2026-10-21T04:00:00Z', '2026-10-21T05:00:00Z');
delete from public.notifications;

-- A: d1 เตือน H1 (ยังไม่ส่ง เปิดรับ) · d2 เตือน H2 (ปิดรับ) · k1 ความคิดเห็นปกติ · k2 ยกเลิกแล้ว · p1 ประกาศใหม่
-- T: s1 ความคิดเห็นนักเรียนที่ยกเลิก · r3 รอตรวจ H3 (ไม่มีงานส่งรอตรวจ)
insert into public.notifications (id, recipient_student_id, recipient_teacher_id, kind, post_id, comment_id,
                                  subject_student_id, dedupe_key, updated_at) values
  ('90480000-0000-4000-8000-0000000000d1', '60480000-0000-4000-8000-00000000000a', null, 'due_reminder', '80480000-0000-4000-8000-000000000001', null, null, 't48:d1', '2026-10-22T05:00:00Z'),
  ('90480000-0000-4000-8000-0000000000d2', '60480000-0000-4000-8000-00000000000a', null, 'due_reminder', '80480000-0000-4000-8000-000000000002', null, null, 't48:d2', '2026-10-22T04:00:00Z'),
  ('90480000-0000-4000-8000-0000000000c1', '60480000-0000-4000-8000-00000000000a', null, 'teacher_comment', '80480000-0000-4000-8000-000000000001', 'c0480000-0000-4000-8000-000000000001', null, 't48:c1', '2026-10-22T03:00:00Z'),
  ('90480000-0000-4000-8000-0000000000c2', '60480000-0000-4000-8000-00000000000a', null, 'teacher_comment', '80480000-0000-4000-8000-000000000001', 'c0480000-0000-4000-8000-000000000002', null, 't48:c2', '2026-10-22T02:00:00Z'),
  ('90480000-0000-4000-8000-0000000000e1', '60480000-0000-4000-8000-00000000000a', null, 'post_published', '80480000-0000-4000-8000-000000000004', null, null, 't48:e1', '2026-10-22T01:00:00Z'),
  ('90480000-0000-4000-8000-0000000000f1', null, '10480000-0000-4000-8000-000000000001', 'student_comment', '80480000-0000-4000-8000-000000000001', 'c0480000-0000-4000-8000-000000000003', '60480000-0000-4000-8000-00000000000a', 't48:f1', '2026-10-22T02:00:00Z'),
  ('90480000-0000-4000-8000-0000000000b3', null, '10480000-0000-4000-8000-000000000001', 'pending_review', '80480000-0000-4000-8000-000000000003', null, null, 't48:b3', '2026-10-22T01:00:00Z');
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.item(p jsonb, p_suffix text) returns jsonb language sql immutable as
  $$ select x from jsonb_array_elements(p -> 'items') x where right(x ->> 'id', 2) = p_suffix $$;
grant execute on function pg_temp.item(jsonb, text) to authenticated;

select ok(not has_function_privilege('authenticated', 'private.notification_relevant(text,uuid,uuid,uuid)', 'EXECUTE')
          and not has_function_privilege('anon', 'private.notification_relevant(text,uuid,uuid,uuid)', 'EXECUTE'),
          'notification_relevant เรียกตรงไม่ได้');

-- ---------------------------------------------------------------------------
-- 1. นักเรียน A — ก่อนส่ง
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('20480000-0000-4000-8000-00000000000a');
create temp table r1 on commit drop as select public.my_notifications() as v;

select is((select pg_temp.item(v, 'd1') ->> 'relevant' from r1), 'true', 'เตือนใกล้ส่ง ยังไม่ส่ง + เปิดรับ → เกี่ยวข้อง');
select is((select pg_temp.item(v, 'd1') ->> 'submitted' from r1), 'false', 'เตือนใกล้ส่ง submitted = false');
select is((select pg_temp.item(v, 'd2') ->> 'relevant' from r1), 'false', 'เตือนใกล้ส่งของงานที่ปิดรับแล้ว → จาง');
select is((select pg_temp.item(v, 'c1') ->> 'relevant' from r1), 'true', 'ความคิดเห็นปกติ → เกี่ยวข้อง');
select is((select pg_temp.item(v, 'c2') ->> 'relevant' from r1), 'false', 'ความคิดเห็นที่ยกเลิก → จาง');
select is((select pg_temp.item(v, 'c2') ->> 'comment_retracted' from r1), 'true', 'ความคิดเห็นที่ยกเลิก comment_retracted = true');
select is((select pg_temp.item(v, 'e1') -> 'submitted' from r1), 'null'::jsonb, 'ชนิดอื่นไม่มี submitted');
select is((select (v ->> 'unread_count')::integer from r1), 3, 'ยังไม่อ่านนับเฉพาะที่เกี่ยวข้อง (d1 k1 p1)');
select is(public.unread_notification_count(), 3, 'ตัวเลขบนกระดิ่งตรงกับ unread_count ของรายการ');
select is((select jsonb_array_length(v -> 'items') from r1), 5, 'รายการที่จางยังอยู่ในกระดิ่ง');

-- ---------------------------------------------------------------------------
-- 2. A ส่งงาน H1 แล้ว → เตือนใกล้ส่งหมดความเกี่ยวข้อง
-- ---------------------------------------------------------------------------
reset role;
set local role postgres;
select set_config('request.jwt.claims', '', true);  -- ไม่มีผู้ใช้ → trigger ไม่สร้างงานรอตรวจให้ครู (0045)
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50480000-0000-4000-8000-0000000000a1', '80480000-0000-4000-8000-000000000001', '60480000-0000-4000-8000-00000000000a', '2026-10-22T06:00:00Z', '2026-10-22T06:00:00Z');
set local role authenticated;
select pg_temp.as_user('20480000-0000-4000-8000-00000000000a');
create temp table r2 on commit drop as select public.my_notifications() as v;
select is((select pg_temp.item(v, 'd1') ->> 'relevant' from r2), 'false', 'ส่งแล้ว → เตือนใกล้ส่งจาง');
select is((select pg_temp.item(v, 'd1') ->> 'submitted' from r2), 'true', 'ส่งแล้ว submitted = true');
select is((select pg_temp.item(v, 'd1') ->> 'read' from r2), 'false', 'สถานะอ่านที่เก็บไว้ไม่เปลี่ยน');
select is(public.unread_notification_count(), 2, 'ส่งแล้วไม่นับเป็นยังไม่อ่าน');
select is(public.mark_notifications_read(array['90480000-0000-4000-8000-0000000000c1']::uuid[]), 1,
          'mark_notifications_read คืนจำนวนที่นับแบบใหม่');
select is(public.mark_notifications_read(), 0, 'อ่านทั้งหมด → 0');

-- ---------------------------------------------------------------------------
-- 3. ครู T
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20480000-0000-4000-8000-000000000001');
create temp table r3 on commit drop as select public.my_notifications() as v;
select is((select pg_temp.item(v, 'f1') ->> 'relevant' from r3), 'false', 'ความคิดเห็นนักเรียนที่ยกเลิก → จาง');
select is((select pg_temp.item(v, 'b3') ->> 'relevant' from r3), 'false', 'รอตรวจแต่ไม่มีงานค้าง → จาง');
select is(public.unread_notification_count(), 0, 'ครู: รายการที่จางไม่นับ');

select * from finish();
rollback;
