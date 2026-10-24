-- ทดสอบ 0044_notification_events: แจ้งเตือนเกิดจากคำสั่งเดิม — ผู้รับ, กันซ้ำ, ทรานแซกชันเดียว, ไม่แจ้งผู้ทำเอง
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

select plan(37);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู T สอนห้อง R1 (นักเรียน A, B) · ครู X สอนห้อง R2 (นักเรียน C)
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40440000-0000-4000-8000-000000000001', 'ภาคทดสอบเหตุการณ์', 'active');
insert into public.term_control (term_id) values ('40440000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('10440000-0000-4000-8000-000000000001', 'ครูเหตุการณ์'),
  ('10440000-0000-4000-8000-000000000002', 'ครูห้องอื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30440000-0000-4000-8000-000000000001', '20440000-0000-4000-8000-000000000001', 'google', 'ev-t', 't44@example.com', 'teacher', '10440000-0000-4000-8000-000000000001'),
  ('30440000-0000-4000-8000-000000000002', '20440000-0000-4000-8000-000000000002', 'google', 'ev-x', 'x44@example.com', 'teacher', '10440000-0000-4000-8000-000000000002'),
  ('30440000-0000-4000-8000-00000000000a', '20440000-0000-4000-8000-00000000000a', 'google', 'ev-a', 'a44@example.com', 'student', null),
  ('30440000-0000-4000-8000-00000000000b', '20440000-0000-4000-8000-00000000000b', 'google', 'ev-b', 'b44@example.com', 'student', null),
  ('30440000-0000-4000-8000-00000000000c', '20440000-0000-4000-8000-00000000000c', 'google', 'ev-c', 'c44@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60440000-0000-4000-8000-00000000000a', '944000000001', 'ก เหตุการณ์', '30440000-0000-4000-8000-00000000000a'),
  ('60440000-0000-4000-8000-00000000000b', '944000000002', 'ข เหตุการณ์', '30440000-0000-4000-8000-00000000000b'),
  ('60440000-0000-4000-8000-00000000000c', '944000000003', 'ค เหตุการณ์', '30440000-0000-4000-8000-00000000000c');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70440000-0000-4000-8000-000000000001', '40440000-0000-4000-8000-000000000001', '10440000-0000-4000-8000-000000000001', 'ห้องเหตุการณ์', 'QQQQ44'),
  ('70440000-0000-4000-8000-000000000002', '40440000-0000-4000-8000-000000000001', '10440000-0000-4000-8000-000000000002', 'ห้องอื่น', 'QQQR44');
insert into public.memberships (classroom_id, student_id) values
  ('70440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000a'),
  ('70440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000b'),
  ('70440000-0000-4000-8000-000000000002', '60440000-0000-4000-8000-00000000000c');

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- จำนวนแจ้งเตือนตามผู้รับ/ชนิด (อ่านตารางในนาม postgres)
create function pg_temp.n(p_kind text, p_student text default null, p_teacher text default null) returns integer
  language sql security definer set search_path = '' as $$
  select count(*)::integer from public.notifications n
   where n.kind = p_kind
     and (p_student is null or n.recipient_student_id = ('60440000-0000-4000-8000-0000000000' || p_student)::uuid)
     and (p_teacher is null or n.recipient_teacher_id = ('10440000-0000-4000-8000-00000000000' || p_teacher)::uuid) $$;
grant execute on function pg_temp.n(text, text, text) to authenticated;
create function pg_temp.unread(p_kind text, p_student text default null, p_teacher text default null) returns integer
  language sql security definer set search_path = '' as $$
  select count(*)::integer from public.notifications n
   where n.kind = p_kind and n.read_at is null
     and (p_student is null or n.recipient_student_id = ('60440000-0000-4000-8000-0000000000' || p_student)::uuid)
     and (p_teacher is null or n.recipient_teacher_id = ('10440000-0000-4000-8000-00000000000' || p_teacher)::uuid) $$;
grant execute on function pg_temp.unread(text, text, text) to authenticated;
create function pg_temp.read_all() returns void language sql security definer set search_path = '' as
  $$ update public.notifications set read_at = clock_timestamp() where read_at is null $$;
grant execute on function pg_temp.read_all() to authenticated;

-- ---------------------------------------------------------------------------
-- 1. โพสต์ใหม่ → สมาชิกห้องเท่านั้น (คำสั่งของครู T)
-- ---------------------------------------------------------------------------
-- ไม่มีผู้ใช้ (เช่นงานเบื้องหลัง) ก็สร้างได้
select set_config('request.jwt.claims', '', true);
insert into public.posts (id, classroom_id, kind, title) values
  ('80440000-0000-4000-8000-000000000003', '70440000-0000-4000-8000-000000000002', 'announcement', 'ประกาศห้องอื่น');
select is(pg_temp.n('post_published', '0c'), 1, 'ไม่มีผู้ใช้ในคำขอก็สร้างแจ้งเตือนได้');
delete from public.posts where id = '80440000-0000-4000-8000-000000000003';
select pg_temp.as_user('20440000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title) values
  ('80440000-0000-4000-8000-000000000001', '70440000-0000-4000-8000-000000000001', 'homework', 'งานเหตุการณ์'),
  ('80440000-0000-4000-8000-000000000002', '70440000-0000-4000-8000-000000000001', 'announcement', 'ประกาศเหตุการณ์');
insert into public.assignments (post_id, full_score, due_at) values
  ('80440000-0000-4000-8000-000000000001', 10, '2026-11-01T13:00:00Z');
select is(pg_temp.n('post_published', '0a') + pg_temp.n('post_published', '0b'), 4, 'งานและประกาศใหม่แจ้ง A และ B คนละ 2 รายการ');
select is(pg_temp.n('post_published', '0c'), 0, 'นักเรียนห้องอื่นไม่ได้แจ้งเตือน');
select is((select count(*)::integer from public.notifications where recipient_teacher_id is not null), 0,
          'ครูที่โพสต์ไม่ได้แจ้งเตือนของตัวเอง');
select is(public.my_notifications() -> 'items', '[]'::jsonb, 'กระดิ่งของครู T ว่าง');
select lives_ok($$ select private.notify_students('post_published', '80440000-0000-4000-8000-000000000001',
                    'post_published:80440000-0000-4000-8000-000000000001',
                    array['60440000-0000-4000-8000-00000000000a']::uuid[]) $$, 'สร้างซ้ำด้วยคีย์เดิมไม่ error');
select is(pg_temp.n('post_published', '0a'), 2, 'คีย์กันซ้ำ: สร้างซ้ำไม่เพิ่มแถว');

-- ---------------------------------------------------------------------------
-- 2. ความคิดเห็นผ่าน post_comment (ทรานแซกชันเดียว · เรียกซ้ำ · แจ้งเตือนล้มไม่ทำให้คำสั่งล้ม)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('20440000-0000-4000-8000-000000000001');
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000a',
                    'ครูเขียน', 'e0440000-0000-4000-8000-000000000001') $$, 'ครูเขียนความคิดเห็นถึง A');
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000a',
                    'ครูเขียน', 'e0440000-0000-4000-8000-000000000001') $$, 'เรียกซ้ำด้วย request_key เดิม');
select is(pg_temp.n('teacher_comment', '0a'), 1, 'เรียกซ้ำไม่สร้างแจ้งเตือนซ้ำ — A ได้ 1 รายการ');
select is(pg_temp.n('student_comment'), 0, 'ครูที่เขียนความคิดเห็นไม่ได้กระดิ่งของตัวเอง');

-- คำสั่งล้มหลังเขียนแล้ว → ความคิดเห็นและแจ้งเตือนย้อนทั้งคู่
select throws_ok($$ do $d$ begin
                      perform public.post_comment('80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000b',
                                                  'ย้อน', 'e0440000-0000-4000-8000-000000000002');
                      raise exception using errcode = 'P0001', message = 't44_boom';
                    end $d$ $$, 'P0001', 't44_boom', 'คำสั่งที่ล้มหลังเขียนความคิดเห็น');
select is(pg_temp.n('teacher_comment', '0b'), 0, 'คำสั่งล้ม → ไม่มีแจ้งเตือนค้าง');

-- ตารางแจ้งเตือนปฏิเสธการเขียน → คำสั่งเดิมยังสำเร็จ
reset role;
set local role postgres;
alter table public.notifications add constraint t44_block check (kind <> 'teacher_comment') not valid;
set local role authenticated;
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000b',
                    'ยังส่งได้', 'e0440000-0000-4000-8000-000000000003') $$, 'สร้างแจ้งเตือนล้ม คำสั่งเดิมไม่ล้ม');
reset role;
set local role postgres;
select is((select count(*)::integer from public.comments
            where student_id = '60440000-0000-4000-8000-00000000000b'), 1,
          'ความคิดเห็นถูกบันทึก (ทั้งที่แจ้งเตือนล้ม) และคำสั่งที่ย้อนไม่ทิ้งความคิดเห็น');
select is(pg_temp.n('teacher_comment', '0b'), 0, 'แจ้งเตือนที่ล้มไม่ถูกบันทึก');
alter table public.notifications drop constraint t44_block;

-- นักเรียน A เขียน → ครู T รวมแถวเดียวต่องานต่อนักเรียน
set local role authenticated;
select pg_temp.as_user('20440000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', null, 'ถามครู 1',
                    'e0440000-0000-4000-8000-00000000000a') $$, 'A เขียนความคิดเห็น');
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', null, 'ถามครู 1',
                    'e0440000-0000-4000-8000-00000000000a') $$, 'A เรียกซ้ำด้วย request_key เดิม');
select is(pg_temp.n('student_comment', null, '1'), 1, 'ครู T ได้ 1 รายการ (เรียกซ้ำไม่เพิ่ม)');
select is(pg_temp.n('teacher_comment', '0a'), 1, 'A ไม่ได้แจ้งเตือนจากความคิดเห็นของตัวเอง');
select pg_temp.read_all();
select lives_ok($$ select public.post_comment('80440000-0000-4000-8000-000000000001', null, 'ถามครู 2',
                    'e0440000-0000-4000-8000-00000000000b') $$, 'A เขียนอีกข้อความ');
select is(pg_temp.n('student_comment', null, '1') * 10 + pg_temp.unread('student_comment', null, '1'), 11,
          'ข้อความใหม่ใช้แถวเดิมและกลับเป็นยังไม่อ่าน');
reset role;
set local role postgres;
select is((select n.comment_id from public.notifications n where n.kind = 'student_comment'),
          (select c.id from public.comments c where c.body = 'ถามครู 2'), 'แถวรวมชี้ความคิดเห็นล่าสุด');

-- ---------------------------------------------------------------------------
-- 3. งานรอตรวจ — แถวเดียวต่องาน ตัวเลขอ่านจากสถานะปัจจุบัน
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20440000-0000-4000-8000-00000000000a');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50440000-0000-4000-8000-00000000000a', '80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000a',
   '2026-10-24T01:00:00Z', '2026-10-24T01:00:00Z');
select is(pg_temp.n('pending_review', null, '1'), 1, 'A ส่งงาน → ครู T มีงานรอตรวจ');
select pg_temp.read_all();
update public.submissions set last_submitted_at = '2026-10-24T02:00:00Z', content_revision = 2
 where id = '50440000-0000-4000-8000-00000000000a';
select is(pg_temp.n('pending_review', null, '1') * 10 + pg_temp.unread('pending_review', null, '1'), 11,
          'ส่งแก้ใช้แถวเดิมและกลับเป็นยังไม่อ่าน');
update public.submissions set reward_granted = true where id = '50440000-0000-4000-8000-00000000000a';
select is(pg_temp.unread('pending_review', null, '1'), 1, 'แก้ช่องอื่นของงานส่งไม่แตะแจ้งเตือน');
insert into public.grades (submission_id, passed, timing, timing_due_at, timing_basis_at, timing_i1,
                           applied_penalty_pct, graded_revision, graded_at, graded_by_account_id) values
  ('50440000-0000-4000-8000-00000000000a', true, 'on_time', '2026-11-01T13:00:00Z', '2026-10-24T01:00:00Z', false,
   0, 2, '2026-10-24T03:00:00Z', '30440000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.as_user('20440000-0000-4000-8000-000000000001');
select is((select jsonb_build_object('n', x -> 'pending_count', 'relevant', x -> 'relevant')
             from jsonb_array_elements(public.my_notifications() -> 'items') x where x ->> 'kind' = 'pending_review'),
          '{"n": 0, "relevant": false}'::jsonb, 'ตรวจหมดแล้ว → ตัวเลขเป็น 0 และหมดความเกี่ยวข้อง (อ่านตอนเปิดดู)');
reset role;
set local role postgres;

-- ---------------------------------------------------------------------------
-- 4. เปิดสิทธิ์แก้ · เปลี่ยนกำหนด · ปิดรับ · เฉลย (คำสั่งของครู T)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20440000-0000-4000-8000-000000000001');
insert into public.revision_permissions (submission_id, opened_by_account_id) values
  ('50440000-0000-4000-8000-00000000000a', '30440000-0000-4000-8000-000000000001');
select is(pg_temp.n('revision_opened', '0a'), 1, 'เปิดสิทธิ์แก้ → A ได้แจ้งเตือน');

update public.assignments set due_at = '2026-11-02T13:00:00Z' where post_id = '80440000-0000-4000-8000-000000000001';
select is(pg_temp.n('due_changed', '0a') + pg_temp.n('due_changed', '0b'), 2, 'เปลี่ยนกำหนด → ทุกคนในห้อง (รวมคนที่ส่งแล้ว)');
select pg_temp.read_all();
update public.assignments set close_at = '2026-11-05T13:00:00Z' where post_id = '80440000-0000-4000-8000-000000000001';
select is(pg_temp.n('due_changed', '0a') * 10 + pg_temp.unread('due_changed', '0a'), 11,
          'เปลี่ยนวันปิดรับใช้แถวเดิมและกลับเป็นยังไม่อ่าน');
update public.assignments set full_score_locked_at = clock_timestamp() where post_id = '80440000-0000-4000-8000-000000000001';
select is(pg_temp.n('intake_closed'), 0, 'แก้ช่องอื่นของงานไม่สร้างแจ้งเตือน');
update public.assignments set closed_at = clock_timestamp() where post_id = '80440000-0000-4000-8000-000000000001';
select is(array[pg_temp.n('intake_closed', '0a'), pg_temp.n('intake_closed', '0b')], array[0, 1],
          'ปิดรับทันที → เฉพาะคนที่ยังไม่ส่ง');

insert into public.solutions (assignment_id, body) values ('80440000-0000-4000-8000-000000000001', 'เฉลย');
select is(pg_temp.n('solution_published'), 0, 'บันทึกเฉลยที่ยังไม่เผยแพร่ไม่แจ้ง');
update public.solutions set published_at = clock_timestamp() where assignment_id = '80440000-0000-4000-8000-000000000001';
select is(pg_temp.n('solution_published', '0a') + pg_temp.n('solution_published', '0b'), 2, 'เผยแพร่เฉลย → ทุกคนในห้อง');
update public.solutions set body = 'เฉลยแก้', updated_at = clock_timestamp()
 where assignment_id = '80440000-0000-4000-8000-000000000001';
select is(pg_temp.n('solution_published'), 2, 'แก้เฉลยหลังเผยแพร่ไม่แจ้งซ้ำ');

-- ---------------------------------------------------------------------------
-- 5. ไม่แจ้งผู้ทำเอง (ฝั่งครู) · ทุกแถวผ่าน check ของ 0043
-- ---------------------------------------------------------------------------
delete from public.notifications where kind = 'student_comment';
select pg_temp.as_user('20440000-0000-4000-8000-000000000001');
insert into public.comments (assignment_id, student_id, author_account_id, body)
  values ('80440000-0000-4000-8000-000000000001', '60440000-0000-4000-8000-00000000000a',
          '30440000-0000-4000-8000-00000000000a', 'ข้อความทดสอบผู้ทำ');
select is(pg_temp.n('student_comment'), 0, 'ผู้ทำคำสั่งเป็นครูผู้รับเอง → ข้าม');
select is((select count(*)::integer from public.notifications where recipient_student_id = '60440000-0000-4000-8000-00000000000c'
                                                                 or recipient_teacher_id = '10440000-0000-4000-8000-000000000002'),
          0, 'ห้องอื่นไม่ได้แจ้งเตือนใดเลย');

select * from finish();
rollback;
