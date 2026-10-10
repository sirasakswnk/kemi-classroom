-- ทดสอบ 0022_teacher_work: teacher_work_summary (T08) และ teacher_submission_list (T03) — สิทธิ์ (ครูเจ้าของห้อง/ผู้ดูแล
-- โดยไม่ต้องโหมดผู้ดูแล; นักเรียน/ครูห้องอื่นไม่ได้), นักเรียนที่ถูกเอาออกแต่เคยส่ง, เรียงเลขที่, ยอด — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(23);

select is_empty(
  $$ select r from unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, 'private.assignment_people(uuid)', 'EXECUTE') $$,
  'assignment_people ใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: ครู 1 (ห้อง 1), ครู 2 (ห้อง 2), ผู้ดูแล; ห้อง 1 สมาชิก S1 (เลขที่ 5 ส่งทัน), S2 (เลขที่ 2 ยังไม่ส่ง),
-- S4 (ไม่มีเลขที่ในรายชื่อภาคนี้ ยังไม่ส่ง); S3 (เลขที่ 9) ส่งช้าแล้วถูกเอาออก · S5 สมาชิกห้อง 2
insert into public.terms (id, name, status) values ('4a000000-0000-4000-8000-000000000001', 'ภาคทดสอบครูดูงาน', 'active');
insert into public.term_control (term_id) values ('4a000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1a000000-0000-4000-8000-000000000001', 'ครูดูงานหนึ่ง'), ('1a000000-0000-4000-8000-000000000002', 'ครูดูงานสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3a000000-0000-4000-8000-000000000001', '2a000000-0000-4000-8000-000000000001', 'google', 'tw-1', 't22a@example.com', 'teacher', '1a000000-0000-4000-8000-000000000001'),
  ('3a000000-0000-4000-8000-000000000002', '2a000000-0000-4000-8000-000000000002', 'google', 'tw-2', 't22b@example.com', 'teacher', '1a000000-0000-4000-8000-000000000002'),
  ('3a000000-0000-4000-8000-000000000003', '2a000000-0000-4000-8000-000000000003', 'google', 'tw-3', 'a22@example.com', 'admin', null),
  ('3a000000-0000-4000-8000-000000000011', '2a000000-0000-4000-8000-000000000011', 'google', 'tw-11', 's22@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6a000000-0000-4000-8000-000000000001', '920000000000221', 'หนึ่ง ครูดู', '3a000000-0000-4000-8000-000000000011'),
  ('6a000000-0000-4000-8000-000000000002', '920000000000222', 'สอง ครูดู', null),
  ('6a000000-0000-4000-8000-000000000003', '920000000000223', 'สาม ครูดู', null),
  ('6a000000-0000-4000-8000-000000000004', '920000000000224', 'สี่ ครูดู', null),
  ('6a000000-0000-4000-8000-000000000005', '920000000000225', 'ห้า ครูดู', null);
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('4a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000001', 'ม.5/1', 5),
  ('4a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000002', 'ม.5/1', 2),
  ('4a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003', 'ม.5/1', 9);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7a000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000001', 'เคมีครูดู 1', 'ZZZZ62'),
  ('7a000000-0000-4000-8000-000000000002', '4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000002', 'เคมีครูดู 2', 'ZZZZ63');
insert into public.memberships (classroom_id, student_id) values
  ('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000001'),
  ('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000002'),
  ('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000004'),
  ('7a000000-0000-4000-8000-000000000002', '6a000000-0000-4000-8000-000000000005');
-- H1 โพสต์ก่อน H2; A3 ประกาศ; H4 ห้อง 2
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000001', 'homework', 'งานหนึ่ง', '2026-10-01T01:00:00Z'),
  ('8a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000001', 'homework', 'งานสอง', '2026-10-02T01:00:00Z'),
  ('8a000000-0000-4000-8000-000000000003', '7a000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ', '2026-10-03T01:00:00Z'),
  ('8a000000-0000-4000-8000-000000000004', '7a000000-0000-4000-8000-000000000002', 'homework', 'งานห้องสอง', '2026-10-02T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, close_at) values
  ('8a000000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z', '2026-10-01T13:00:00Z'),
  ('8a000000-0000-4000-8000-000000000002', 10, '2099-10-10T13:00:00Z', null),
  ('8a000000-0000-4000-8000-000000000004', 10, '2099-10-10T13:00:00Z', null);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, content_revision) values
  ('5a000000-0000-4000-8000-000000000001', '8a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T05:00:00Z', 2),
  ('5a000000-0000-4000-8000-000000000003', '8a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003', '2026-09-30T14:00:00Z', '2026-09-30T14:00:00Z', 1);
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ba000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000011', 'submission', 'staging/t22/1', 's', 'files/t22/1.jpg', 'image/jpeg', 10, '1.jpg'),
  ('ba000000-0000-4000-8000-000000000002', '3a000000-0000-4000-8000-000000000011', 'submission', 'staging/t22/2', 's', 'files/t22/2.jpg', 'image/jpeg', 10, '2.jpg');
update public.assets set status = 'ready', version_id = 'v', checksum = 'e', ready_at = clock_timestamp() where id::text like 'ba000000-%';
insert into public.attachments (asset_id, submission_id, position) values
  ('ba000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', 1),
  ('ba000000-0000-4000-8000-000000000002', '5a000000-0000-4000-8000-000000000001', 2);
-- S3 ถูกเอาออกหลังส่ง (ไม่มีแถว membership)

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.rows(p_label text) returns setof jsonb language sql stable as
  $$ select e from res, jsonb_array_elements(body -> 'rows') e where label = p_label $$;
grant execute on function pg_temp.rows(text) to authenticated;

-- ---------------------------------------------------------------------------
-- ก: ครูเจ้าของห้อง
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('list', public.teacher_submission_list('8a000000-0000-4000-8000-000000000001'));
select is((select jsonb_agg(e ->> 'display_name') from pg_temp.rows('list') e), '["สอง ครูดู", "หนึ่ง ครูดู", "สาม ครูดู", "สี่ ครูดู"]'::jsonb,
  'เรียงเลขที่ของรายชื่อภาคนี้ (2, 5, 9) แล้วคนที่ไม่มีเลขที่ไว้ท้าย');
select is((select e - 'student_id' - 'submission_id' from pg_temp.rows('list') e where e ->> 'display_name' = 'หนึ่ง ครูดู'),
  jsonb_build_object('roll_number', 5, 'display_name', 'หนึ่ง ครูดู', 'member', true,
    'first_submitted_at', '2026-09-29T01:00:00+00:00', 'last_submitted_at', '2026-09-29T05:00:00+00:00',
    'content_revision', 2, 'timing', 'on_time', 'graded', false, 'file_count', 2),
  'แถวที่ส่งแล้ว: เวลาส่งแรก/ล่าสุด ครั้งที่ส่ง ทัน จำนวนไฟล์');
select is((select (e -> 'member') || (e -> 'timing') || (e -> 'roll_number') from pg_temp.rows('list') e where e ->> 'display_name' = 'สาม ครูดู'),
  '[false, "late", 9]'::jsonb, 'ถูกเอาออกแต่เคยส่ง: ยังอยู่ในรายชื่อ member = false ส่งช้า');
select is((select (e -> 'submission_id') || (e -> 'timing') || (e -> 'file_count') from pg_temp.rows('list') e where e ->> 'display_name' = 'สอง ครูดู'),
  '[null, null, 0]'::jsonb, 'ยังไม่ส่ง: ไม่มีงานส่ง');
select is((select count(*)::integer from pg_temp.rows('list') e where e ->> 'display_name' = 'ห้า ครูดู'), 0, 'ไม่รวมนักเรียนห้องอื่น');
select is((select body -> 'intake' from res where label = 'list'), '"closed"', 'สถานะรับงานของงาน (เลยวันปิดรับ)');
insert into res values ('list2', public.teacher_submission_list('8a000000-0000-4000-8000-000000000002'));
select is((select count(*)::integer from pg_temp.rows('list2')), 3, 'งานที่ยังไม่มีใครส่ง: สมาชิกขณะนี้ 3 คน (ไม่มีคนที่ถูกเอาออก)');

insert into res values ('sum', public.teacher_work_summary('7a000000-0000-4000-8000-000000000001'));
select is((select jsonb_agg(e ->> 'post_id') from res, jsonb_array_elements(body) e where label = 'sum'),
  '["8a000000-0000-4000-8000-000000000002", "8a000000-0000-4000-8000-000000000001"]'::jsonb,
  'T08: เฉพาะการบ้าน เรียงจากโพสต์ล่าสุด');
select is((select e - 'post_id' - 'due_at' - 'close_at' from res, jsonb_array_elements(body) e
            where label = 'sum' and e ->> 'post_id' = '8a000000-0000-4000-8000-000000000001'),
  jsonb_build_object('intake', 'closed', 'solution_published', false, 'total', 4, 'submitted', 2, 'not_submitted', 2,
                     'waiting', 2, 'late', 1),
  'ยอดงานหนึ่ง: ทั้งหมด 4 (สมาชิก 3 + ถูกเอาออกที่ส่งแล้ว 1) ส่งแล้ว 2 ยังไม่ส่ง 2 รอตรวจ 2 ส่งช้า 1');
select is((select e - 'post_id' - 'due_at' - 'close_at' from res, jsonb_array_elements(body) e
            where label = 'sum' and e ->> 'post_id' = '8a000000-0000-4000-8000-000000000002'),
  jsonb_build_object('intake', 'open', 'solution_published', false, 'total', 3, 'submitted', 0, 'not_submitted', 3,
                     'waiting', 0, 'late', 0),
  'ยอดงานสอง: ยังไม่มีคนส่ง');
select throws_ok($$ select public.teacher_submission_list('8a000000-0000-4000-8000-000000000003') $$, 'P0001', 'forbidden',
  'ประกาศ → forbidden');
select throws_ok($$ select public.teacher_submission_list('8a000000-0000-4000-8000-000000000004') $$, 'P0001', 'forbidden',
  'งานห้องของครูคนอื่น → forbidden');
select throws_ok($$ select public.teacher_work_summary('7a000000-0000-4000-8000-000000000002') $$, 'P0001', 'forbidden',
  'ห้องของครูคนอื่น → forbidden');
select throws_ok($$ select public.teacher_work_summary('7a000000-0000-4000-8000-0000000000ff') $$, 'P0001', 'forbidden',
  'ห้องที่ไม่มี → forbidden');

-- ---------------------------------------------------------------------------
-- ข: ผู้ดูแล (ไม่ต้องโหมดผู้ดูแล), นักเรียน, ครูห้องอื่น
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(jsonb_array_length(public.teacher_submission_list('8a000000-0000-4000-8000-000000000001') -> 'rows'), 4,
  'ผู้ดูแลอ่านรายชื่อได้โดยไม่ต้องส่ง admin mode');
select is(jsonb_array_length(public.teacher_work_summary('7a000000-0000-4000-8000-000000000002')), 1, 'ผู้ดูแลอ่านยอดห้องใดก็ได้');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.teacher_submission_list('8a000000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden',
  'ครูห้องอื่นอ่านรายชื่อไม่ได้');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ select public.teacher_submission_list('8a000000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden',
  'นักเรียน (สมาชิกห้อง) อ่านรายชื่อไม่ได้');
select throws_ok($$ select public.teacher_work_summary('7a000000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden',
  'นักเรียนอ่านยอดไม่ได้');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-0000000000ff", "role": "authenticated"}';
select throws_ok($$ select public.teacher_work_summary('7a000000-0000-4000-8000-000000000001') $$, 'P0001', 'forbidden',
  'คนที่ไม่มีบัญชีในระบบ → forbidden');

-- ครูอ่านไฟล์งานส่งผ่าน RLS (ตัวดูไฟล์ใช้ตาราง attachments ตรง) — รวมงานของคนที่ถูกเอาออก
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is((select count(*)::integer from public.attachments where submission_id = '5a000000-0000-4000-8000-000000000001'), 2,
  'ครูเจ้าของห้องอ่านแถวไฟล์ของงานส่งได้ (RLS 0020)');
select is((select count(*)::integer from public.submissions where assignment_id = '8a000000-0000-4000-8000-000000000001'), 2,
  'ครูเห็นงานส่งของคนที่ถูกเอาออกด้วย');

select * from finish();
rollback;
