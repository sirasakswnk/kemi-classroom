-- ทดสอบ 0046_due_reminders: ตั้ง/เลื่อน/ยกเลิกงานเตือน 24 ชม. (J7, L5, N3) และการสร้างแจ้งเตือนใกล้กำหนด
-- ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(29);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู T สอนห้อง R1 (นักเรียน A, B) · นักเรียน C เข้าห้องทีหลัง
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40460000-0000-4000-8000-000000000001', 'ภาคทดสอบเตือน', 'active');
insert into public.term_control (term_id) values ('40460000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10460000-0000-4000-8000-000000000001', 'ครูเตือน');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30460000-0000-4000-8000-000000000001', '20460000-0000-4000-8000-000000000001', 'google', 'rm-t', 't46@example.com', 'teacher', '10460000-0000-4000-8000-000000000001');
insert into public.students (id, student_code, display_name) values
  ('60460000-0000-4000-8000-00000000000a', '946000000001', 'ก เตือน'),
  ('60460000-0000-4000-8000-00000000000b', '946000000002', 'ข เตือน'),
  ('60460000-0000-4000-8000-00000000000c', '946000000003', 'ค เตือน');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70460000-0000-4000-8000-000000000001', '40460000-0000-4000-8000-000000000001', '10460000-0000-4000-8000-000000000001', 'ห้องเตือน', 'QQQQ46');
insert into public.memberships (classroom_id, student_id) values
  ('70460000-0000-4000-8000-000000000001', '60460000-0000-4000-8000-00000000000a'),
  ('70460000-0000-4000-8000-000000000001', '60460000-0000-4000-8000-00000000000b');

-- เวลาสัมพัทธ์จากตอนนี้ (นาทีเต็มตาม check ของ due_at)
-- เวลาฐานคงที่ทั้งไฟล์ (ต้นนาทีปัจจุบัน) กันการข้ามนาทีระหว่างคำสั่ง
create temp table t46_base as select date_trunc('minute', clock_timestamp()) as b;
create function pg_temp.at(p_hours numeric) returns timestamptz language sql stable as
  $$ select b + make_interval(secs => p_hours * 3600) from t46_base $$;
create function pg_temp.job(p_post text) returns private.jobs language sql stable as
  $$ select j.* from private.jobs j where j.kind = 'due_reminder' and j.dedupe_key = ('80460000-0000-4000-8000-00000000000' || p_post) $$;
create function pg_temp.post(p_post text, p_due timestamptz) returns void language sql as $$
  insert into public.posts (id, classroom_id, kind, title)
    values (('80460000-0000-4000-8000-00000000000' || p_post)::uuid, '70460000-0000-4000-8000-000000000001', 'homework', 'งาน ' || p_post);
  insert into public.assignments (post_id, full_score, due_at)
    values (('80460000-0000-4000-8000-00000000000' || p_post)::uuid, 10, p_due) $$;
create function pg_temp.due(p_post text, p_due timestamptz) returns void language sql as
  $$ update public.assignments set due_at = p_due where post_id = ('80460000-0000-4000-8000-00000000000' || p_post)::uuid $$;
create function pg_temp.send(p_post text) returns integer language sql volatile as $$
  select private.send_due_reminders(j.dedupe_key::uuid, (j.payload ->> 'due_at')::timestamptz, j.run_at)
    from private.jobs j where j.kind = 'due_reminder' and j.dedupe_key = ('80460000-0000-4000-8000-00000000000' || p_post) $$;
create function pg_temp.reminded(p_post text, p_student text) returns integer language sql stable as $$
  select count(*)::integer from public.notifications n
   where n.kind = 'due_reminder' and n.post_id = ('80460000-0000-4000-8000-00000000000' || p_post)::uuid
     and n.recipient_student_id = ('60460000-0000-4000-8000-00000000000' || p_student)::uuid $$;
create function pg_temp.done(p_post text) returns void language sql as $$
  update private.jobs set status = 'done' where kind = 'due_reminder'
     and dedupe_key = ('80460000-0000-4000-8000-00000000000' || p_post) $$;

select set_config('request.jwt.claims',
                  json_build_object('sub', '20460000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);

-- ---------------------------------------------------------------------------
-- 1. ตอนโพสต์ (J7)
-- ---------------------------------------------------------------------------
select pg_temp.post('1', pg_temp.at(72));
select is((pg_temp.job('1')).status, 'pending', 'โพสต์งานกำหนด 3 วัน → มีงานเตือนรอ');
select is((pg_temp.job('1')).run_at, pg_temp.at(48), 'งานเตือนตั้งที่กำหนด − 24 ชม.');
select is(((pg_temp.job('1')).payload ->> 'due_at')::timestamptz, pg_temp.at(72), 'payload จำกำหนดที่ตั้งไว้');
select pg_temp.post('2', pg_temp.at(10));
select ok(pg_temp.job('2') is null, 'J7: โพสต์เมื่อเหลือ 10 ชม. ไม่มีงานเตือน');
select pg_temp.post('3', pg_temp.at(23.9));
select ok(pg_temp.job('3') is null, 'J7: เหลือน้อยกว่า 24 ชม. เล็กน้อยก็ไม่มีงานเตือน');

-- งานเป็นชุดไม่มีผู้ใช้ในคำขอ → ไม่ตั้ง
select set_config('request.jwt.claims', '', true);
select pg_temp.post('9', pg_temp.at(72));
select ok(pg_temp.job('9') is null, 'ไม่มีผู้ใช้ในคำขอ (กู้ข้อมูล/SQL ตรง) ไม่ตั้งงานเตือน');
select set_config('request.jwt.claims',
                  json_build_object('sub', '20460000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);

-- ---------------------------------------------------------------------------
-- 2. ขยายจาก 10 ชม. เป็น 3 วัน → เตือน 1 ครั้ง (L5)
-- ---------------------------------------------------------------------------
select pg_temp.due('2', pg_temp.at(72));
select is((pg_temp.job('2')).run_at, pg_temp.at(48), 'ขยายเป็น 3 วัน → ตั้งงานเตือนที่กำหนดใหม่ − 24 ชม.');
select is(pg_temp.send('2'), 2, 'ถึงเวลา → เตือน A และ B');
select is(pg_temp.send('2'), 0, 'เรียกซ้ำไม่เตือนซ้ำ');
select is(pg_temp.reminded('2', 'a'), 1, 'A ได้เตือน 1 ครั้ง');

-- ---------------------------------------------------------------------------
-- 3. เคยเตือนแล้ว ขยายอีก → ไม่เตือนซ้ำ; คนที่ยังไม่เคยได้เตือนได้ครั้งเดียว
-- ---------------------------------------------------------------------------
select pg_temp.done('2');
insert into public.memberships (classroom_id, student_id) values
  ('70460000-0000-4000-8000-000000000001', '60460000-0000-4000-8000-00000000000c');
select pg_temp.due('2', pg_temp.at(120));
select is((pg_temp.job('2')).status || ' ' || (pg_temp.job('2')).run_at::text, 'pending ' || pg_temp.at(96)::text,
          'ขยายหลังเตือนแล้ว → งานเตือนรอใหม่ที่กำหนดใหม่ − 24 ชม.');
select is(pg_temp.send('2'), 1, 'รอบใหม่เตือนเฉพาะ C ที่ยังไม่เคยได้เตือน');
select is(array[pg_temp.reminded('2', 'a'), pg_temp.reminded('2', 'b'), pg_temp.reminded('2', 'c')], array[1, 1, 1],
          'L5: ไม่เกินครั้งเดียวต่อคนต่องาน');

-- ---------------------------------------------------------------------------
-- 4. ตรวจสถานะล่าสุดก่อนสร้าง
-- ---------------------------------------------------------------------------
insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('80460000-0000-4000-8000-000000000001', '60460000-0000-4000-8000-00000000000b', clock_timestamp(), clock_timestamp());
select is(private.send_due_reminders('80460000-0000-4000-8000-000000000001', pg_temp.at(10), pg_temp.at(48)), 0,
          'กำหนดไม่ตรง payload (งานเตือนเก่า) → ไม่สร้าง');
select is(private.send_due_reminders('80460000-0000-4000-8000-000000000001', pg_temp.at(72), pg_temp.at(40)), 0,
          'ยังไม่ถึงช่วง 24 ชม. → ไม่สร้าง');
select is(private.send_due_reminders('80460000-0000-4000-8000-000000000001', pg_temp.at(72), pg_temp.at(72)), 0,
          'ถึงกำหนดแล้ว → ไม่สร้าง');
select is(pg_temp.send('1'), 2, 'เตือนเฉพาะคนที่ยังไม่ส่ง (A, C — B ส่งแล้ว)');
select is(pg_temp.reminded('1', 'b'), 0, 'B ส่งแล้วไม่ได้เตือน');

-- ---------------------------------------------------------------------------
-- 5. เลื่อนเร็วขึ้น / ปิดรับ / เปิดรับอีกครั้ง / เฉลย / ลบ (N3)
-- ---------------------------------------------------------------------------
select pg_temp.post('4', pg_temp.at(96));
select pg_temp.due('4', pg_temp.at(48));
select is((pg_temp.job('4')).status || ' ' || (pg_temp.job('4')).run_at::text, 'pending ' || pg_temp.at(24)::text,
          'เลื่อนเร็วขึ้นแต่ยังห่างเกิน 24 ชม. → งานเตือนย้ายตาม');
select pg_temp.due('4', pg_temp.at(20));
select is((pg_temp.job('4')).status || ' ' || (pg_temp.job('4')).last_error::text, 'done cancelled',
          'เลื่อนเร็วขึ้นจนเหลือไม่ถึง 24 ชม. → ยกเลิกงานเตือน');
select pg_temp.due('4', pg_temp.at(96));
select is((pg_temp.job('4')).status, 'pending', 'ขยายกลับเกิน 24 ชม. → ตั้งใหม่');
update public.assignments set closed_at = clock_timestamp() where post_id = '80460000-0000-4000-8000-000000000004';
select is((pg_temp.job('4')).last_error, 'cancelled', 'ปิดรับทันที → ยกเลิกงานเตือน');
select is(private.send_due_reminders('80460000-0000-4000-8000-000000000004', pg_temp.at(96), pg_temp.at(72)), 0,
          'ปิดรับแล้ว → ไม่สร้างแม้ถูกเรียก');
update public.assignments set closed_at = null where post_id = '80460000-0000-4000-8000-000000000004';
select is((pg_temp.job('4')).status || ' ' || (pg_temp.job('4')).run_at::text, 'pending ' || pg_temp.at(72)::text,
          'เปิดรับอีกครั้งเมื่อกำหนดยังห่าง → ตั้งใหม่');
update public.assignments set full_score = 20 where post_id = '80460000-0000-4000-8000-000000000004';
select is((pg_temp.job('4')).attempts, 0, 'แก้ช่องอื่นของงานไม่แตะงานเตือน');
insert into public.solutions (assignment_id, published_at) values ('80460000-0000-4000-8000-000000000004', clock_timestamp());
select is((pg_temp.job('4')).last_error, 'cancelled', 'เผยแพร่เฉลย → ยกเลิกงานเตือน');

select pg_temp.post('5', pg_temp.at(96));
delete from public.posts where id = '80460000-0000-4000-8000-000000000005';
select is((pg_temp.job('5')).status || ' ' || (pg_temp.job('5')).last_error::text, 'done cancelled',
          'ลบงาน → ยกเลิกงานเตือน');

-- ภาคเรียนจบ (K5) → ไม่สร้าง
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
select is(private.send_due_reminders('80460000-0000-4000-8000-000000000002', pg_temp.at(120), pg_temp.at(100)), 0,
          'ภาคเรียนจบแล้ว → ไม่สร้าง');

select ok(not exists (select 1 from information_schema.routine_privileges
                       where routine_schema = 'private' and routine_name in ('send_due_reminders', 'schedule_due_reminder',
                                                                            'cancel_due_reminder')
                         and grantee in ('anon', 'authenticated', 'PUBLIC')),
          'ฟังก์ชันงานเตือนไม่ GRANT ให้ผู้ใช้');

select * from finish();
rollback;
