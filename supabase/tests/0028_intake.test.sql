-- ทดสอบ 0028_intake: สถานะรับงาน (ปิดรับทันที / ตั้งเวลา / ช่วงรับหลังเฉลยและการปิดช่วงนี้), เปลี่ยนกำหนดส่งสองทิศ
-- (preview + ตรวจซ้ำตอนบันทึก, I2 ผลตรวจคงเดิม), close_assignment, สิทธิ์ทุกบทบาท — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(40);

select is_empty(
  $$ select r || ' ' || f from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.assignment_event(uuid,text,jsonb)', 'private.due_change_effects(uuid,timestamp with time zone,timestamp with time zone)',
                         'private.due_change_check(public.assignments,timestamp with time zone)', 'private.assignment_intake(uuid,timestamp with time zone)']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: ครู 1 (ห้อง 1), ครู 2, ผู้ดูแล; ห้อง 1 สมาชิก N1–N4 (N1 มีบัญชี), N5 ส่งแล้วถูกเอาออก
-- H1 กำหนด 1 ต.ค. 13:00Z: N1 ส่งทัน 12:00 (ยังไม่ตรวจ) · N2 ส่งช้า 14:00 (ยังไม่ตรวจ) · N3 ส่งช้า 15:00 (ตรวจแล้ว)
--   · N4 ส่งแรกหลังเฉลย 12:30 · N5 ส่งช้า 16:00 (ยังไม่ตรวจ, ออกจากห้องแล้ว)
-- H2 กำหนด 2099 ไม่มีวันปิดรับ (ทดสอบปิดรับ) · H3 กำหนด 2099 รับหลังเฉลย (ทดสอบช่วงหลังเฉลย)
insert into public.terms (id, name, status) values ('4c000000-0000-4000-8000-000000000001', 'ภาคทดสอบรับงาน', 'active');
insert into public.term_control (term_id) values ('4c000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1c000000-0000-4000-8000-000000000001', 'ครูรับงานหนึ่ง'), ('1c000000-0000-4000-8000-000000000002', 'ครูรับงานสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3c000000-0000-4000-8000-000000000001', '2c000000-0000-4000-8000-000000000001', 'google', 'in-1', 't28a@example.com', 'teacher', '1c000000-0000-4000-8000-000000000001'),
  ('3c000000-0000-4000-8000-000000000002', '2c000000-0000-4000-8000-000000000002', 'google', 'in-2', 't28b@example.com', 'teacher', '1c000000-0000-4000-8000-000000000002'),
  ('3c000000-0000-4000-8000-000000000003', '2c000000-0000-4000-8000-000000000003', 'google', 'in-3', 'a28@example.com', 'admin', null),
  ('3c000000-0000-4000-8000-000000000011', '2c000000-0000-4000-8000-000000000011', 'google', 'in-11', 's28a@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6c000000-0000-4000-8000-000000000001', '928000000000281', 'หนึ่ง รับงาน', '3c000000-0000-4000-8000-000000000011'),
  ('6c000000-0000-4000-8000-000000000002', '928000000000282', 'สอง รับงาน', null),
  ('6c000000-0000-4000-8000-000000000003', '928000000000283', 'สาม รับงาน', null),
  ('6c000000-0000-4000-8000-000000000004', '928000000000284', 'สี่ รับงาน', null),
  ('6c000000-0000-4000-8000-000000000005', '928000000000285', 'ห้า รับงาน', null);
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('4c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000002', 'ม.5/1', 2),
  ('4c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000005', 'ม.5/1', 1);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000001', 'เคมีรับงาน 1', 'ZZZZ79');
insert into public.memberships (classroom_id, student_id)
select '7c000000-0000-4000-8000-000000000001', s.id from public.students s
 where s.id::text like '6c000000-%' and s.id <> '6c000000-0000-4000-8000-000000000005';
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8c000000-0000-4000-8000-000000000001', '7c000000-0000-4000-8000-000000000001', 'homework', 'งานรับหนึ่ง', '2026-09-20T01:00:00Z'),
  ('8c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000001', 'homework', 'งานรับสอง', '2026-09-21T01:00:00Z'),
  ('8c000000-0000-4000-8000-000000000003', '7c000000-0000-4000-8000-000000000001', 'homework', 'งานรับสาม', '2026-09-22T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, close_at, accept_after_solution) values
  ('8c000000-0000-4000-8000-000000000001', 10, '2026-10-01T13:00:00Z', '2026-10-10T13:00:00Z', false),
  ('8c000000-0000-4000-8000-000000000002', 10, '2099-10-01T13:00:00Z', null, false),
  ('8c000000-0000-4000-8000-000000000003', 10, '2099-10-01T13:00:00Z', null, true);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, first_after_solution) values
  ('5c000000-0000-4000-8000-000000000001', '8c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', '2026-10-01T12:00:00Z', '2026-10-01T12:00:00Z', false),
  ('5c000000-0000-4000-8000-000000000002', '8c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000002', '2026-10-01T14:00:00Z', '2026-10-01T14:00:00Z', false),
  ('5c000000-0000-4000-8000-000000000003', '8c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000003', '2026-10-01T15:00:00Z', '2026-10-01T15:00:00Z', false),
  ('5c000000-0000-4000-8000-000000000004', '8c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000004', '2026-10-01T12:30:00Z', '2026-10-01T12:30:00Z', true),
  ('5c000000-0000-4000-8000-000000000005', '8c000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000005', '2026-10-01T16:00:00Z', '2026-10-01T16:00:00Z', false),
  ('5c000000-0000-4000-8000-000000000021', '8c000000-0000-4000-8000-000000000002', '6c000000-0000-4000-8000-000000000001', '2026-10-05T01:00:00Z', '2026-10-05T01:00:00Z', false);
insert into public.grades (submission_id, raw_score, passed, timing, timing_due_at, timing_basis_at, timing_i1,
                           applied_penalty_pct, deduction, net_score, graded_revision, graded_at, graded_by_account_id)
values ('5c000000-0000-4000-8000-000000000003', 8, true, 'late', '2026-10-01T13:00:00Z', '2026-10-01T15:00:00Z', false,
        50, 4, 4, 1, '2026-10-02T01:00:00Z', '3c000000-0000-4000-8000-000000000001');

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- id ของรายชื่อในผล (ตามลำดับที่คืน)
create function pg_temp.ids(p jsonb) returns uuid[] language sql immutable as
  $$ select coalesce(array_agg((e ->> 'submission_id')::uuid order by n), '{}') from jsonb_array_elements(p) with ordinality x(e, n) $$;
grant execute on function pg_temp.ids(jsonb) to authenticated;
create function pg_temp.intake(p uuid) returns text language sql security definer set search_path = '' as
  $$ select private.assignment_intake(p, clock_timestamp()) $$;
grant execute on function pg_temp.intake(uuid) to authenticated;

set local role authenticated;
select pg_temp.as_user('2c000000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- ก: preview เปลี่ยนกำหนดส่ง
-- ---------------------------------------------------------------------------
insert into res values ('later', public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T15:00:00Z'));
select is(pg_temp.ids(pg_temp.r('later') -> 'to_on_time'),
  '{5c000000-0000-4000-8000-000000000002}'::uuid[],
  'เลื่อนช้าลง: งานยังไม่ตรวจที่ส่งช้าก่อนกำหนดใหม่กลายเป็นทัน (ไม่รวมคนที่ตรวจแล้ว/ส่งหลังเฉลย/ยังสายอยู่)');
select is(pg_temp.r('later') -> 'to_late', '[]'::jsonb, 'เลื่อนช้าลง: ไม่มีใครกลายเป็นสาย');
select is(pg_temp.r('later') -> 'graded_count', '1'::jsonb, 'นับคนที่ตรวจแล้ว (ผลคงเดิม)');
select is((pg_temp.r('later') -> 'to_on_time' -> 0) - 'submission_id',
  '{"student_id": "6c000000-0000-4000-8000-000000000002", "roll_number": 2, "display_name": "สอง รับงาน"}'::jsonb,
  'รายชื่อมีเลขที่และชื่อ');
insert into res values ('much_later', public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T17:00:00Z'));
select is(pg_temp.ids(pg_temp.r('much_later') -> 'to_on_time'),
  '{5c000000-0000-4000-8000-000000000005,5c000000-0000-4000-8000-000000000002}'::uuid[],
  'รวมคนที่ออกจากห้องแล้วแต่มีงานส่ง เรียงเลขที่ (1, 2)');
insert into res values ('earlier', public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T11:00:00Z'));
select is(pg_temp.ids(pg_temp.r('earlier') -> 'to_late'), '{5c000000-0000-4000-8000-000000000001}'::uuid[],
  'เลื่อนเร็วขึ้น: งานยังไม่ตรวจที่ส่งหลังกำหนดใหม่กลายเป็นสาย');
select is(pg_temp.r('earlier') -> 'to_on_time', '[]'::jsonb, 'เลื่อนเร็วขึ้น: ไม่มีใครกลายเป็นทัน');
select throws_ok($$ select public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T13:00:30Z') $$,
  'P0001', 'due_at_invalid', 'กำหนดต้องเป็นนาทีเต็ม');
select throws_ok($$ select public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T13:00:00Z') $$,
  'P0001', 'invalid_request', 'กำหนดใหม่ต้องต่างจากเดิม');
select throws_ok($$ select public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-11T13:00:00Z') $$,
  'P0001', 'close_before_due', 'กำหนดใหม่หลังวันปิดรับที่ตั้งไว้ → close_before_due');

-- ---------------------------------------------------------------------------
-- ข: บันทึกเปลี่ยนกำหนดส่ง
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T15:00:00Z', '{}', '{}', gen_random_uuid()) $$,
  'P0001', 'preview_changed', 'รายชื่อที่ส่งมาไม่ตรงกับผลจริง → preview_changed');
select is((select due_at from public.assignments where post_id = '8c000000-0000-4000-8000-000000000001'), '2026-10-01T13:00:00Z'::timestamptz,
  'ถูกปฏิเสธแล้วกำหนดไม่เปลี่ยน');
insert into res values ('chg', public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T15:00:00Z',
  '{5c000000-0000-4000-8000-000000000002}', '{}', 'c8000000-0000-4000-8000-000000000001'));
select is(jsonb_build_array(pg_temp.r('chg') -> 'due_at', pg_temp.r('chg') -> 'previous_due_at'),
  '["2026-10-01T15:00:00+00:00", "2026-10-01T13:00:00+00:00"]'::jsonb, 'รายชื่อตรง: บันทึกกำหนดใหม่');
select is(public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T15:00:00Z',
  '{5c000000-0000-4000-8000-000000000002}', '{}', 'c8000000-0000-4000-8000-000000000001'), pg_temp.r('chg'),
  'กดซ้ำด้วย request key เดิมคืนผลเดิม');
select is((select jsonb_build_array(g.timing, g.net_score, g.timing_due_at) from public.grades g
            where g.submission_id = '5c000000-0000-4000-8000-000000000003'),
  '["late", 4, "2026-10-01T13:00:00+00:00"]'::jsonb, 'I2: ผลตรวจที่บันทึกแล้วคงเดิม (ทัน/สาย คะแนน กำหนดที่ใช้)');
-- หลังเปลี่ยน N3 (ส่ง 15:00 ตรวจแล้ว) ตรงกำหนดใหม่พอดี — รายชื่อ T03 คิดทัน/สายจากกำหนดปัจจุบัน
select is((select e -> 'timing' from jsonb_array_elements(public.teacher_submission_list('8c000000-0000-4000-8000-000000000001') -> 'rows') e
            where e ->> 'student_id' = '6c000000-0000-4000-8000-000000000002'), '"on_time"', 'T03 แสดงงานที่ยังไม่ตรวจตามกำหนดใหม่');

-- สองทิศ: เลื่อนกลับเร็วขึ้น — ส่วนที่ทันจากกำหนดใหม่กลับเป็นสาย
insert into res values ('back', public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T11:00:00Z',
  '{}', '{5c000000-0000-4000-8000-000000000001,5c000000-0000-4000-8000-000000000002}', gen_random_uuid()));
select is(pg_temp.ids(pg_temp.r('back') -> 'to_late'),
  '{5c000000-0000-4000-8000-000000000002,5c000000-0000-4000-8000-000000000001}'::uuid[],
  'เลื่อนเร็วขึ้นหลังขยาย: คืนรายชื่อที่กลายเป็นสาย (ลำดับที่ส่งมาไม่สำคัญ)');

-- สิทธิ์
select pg_temp.as_user('2c000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T17:00:00Z') $$,
  'P0001', 'forbidden', 'ครูห้องอื่นดู preview ไม่ได้');
select throws_ok($$ select public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T17:00:00Z', '{}', '{}', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นเปลี่ยนกำหนดไม่ได้');
select pg_temp.as_user('2c000000-0000-4000-8000-000000000011');
select throws_ok($$ select public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T17:00:00Z') $$,
  'P0001', 'forbidden', 'นักเรียนดู preview ไม่ได้');
select throws_ok($$ select public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T17:00:00Z', '{}', '{}', gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนเปลี่ยนกำหนดไม่ได้');
select pg_temp.as_user('2c000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T12:00:00Z', '{}', '{}', gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลเปลี่ยนกำหนดไม่ได้');
select is(public.preview_due_change('8c000000-0000-4000-8000-000000000001', '2026-10-01T11:30:00Z') -> 'to_on_time', '[]'::jsonb,
  'ผู้ดูแลดู preview ได้โดยไม่ต้องโหมดผู้ดูแล');
select is(public.change_due('8c000000-0000-4000-8000-000000000001', '2026-10-01T11:30:00Z', '{}', '{}', gen_random_uuid(), true) -> 'due_at',
  '"2026-10-01T11:30:00+00:00"', 'ผู้ดูแลในโหมดผู้ดูแลเปลี่ยนกำหนดได้');

-- ---------------------------------------------------------------------------
-- ค: ปิดรับ
-- ---------------------------------------------------------------------------
select pg_temp.as_user('2c000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.close_assignment('8c000000-0000-4000-8000-000000000002', clock_timestamp() - interval '1 minute', gen_random_uuid()) $$,
  'P0001', 'close_at_invalid', 'ตั้งเวลาปิดรับในอดีตไม่ได้');
select throws_ok($$ select public.close_assignment('8c000000-0000-4000-8000-000000000002', '2099-09-01T13:00:00Z', gen_random_uuid()) $$,
  'P0001', 'close_before_due', 'ตั้งเวลาปิดรับก่อนกำหนดส่งไม่ได้');
insert into res values ('sched', public.close_assignment('8c000000-0000-4000-8000-000000000002', '2099-10-02T13:00:00Z', gen_random_uuid()));
select is(pg_temp.r('sched') - 'assignment_id',
  '{"intake": "open", "close_at": "2099-10-02T13:00:00+00:00", "closed_at": null, "after_solution_closed_at": null}'::jsonb,
  'ตั้งเวลาปิดรับ: ยังเปิดรับจนถึงเวลานั้น');

-- ปิดทันที (ก่อนกำหนดส่งก็ได้): นักเรียนที่ยังไม่ส่งส่งไม่ได้ คนที่มีสิทธิ์แก้ค้างยังส่งแก้ได้ (แถว 7)
insert into res values ('now', public.close_assignment('8c000000-0000-4000-8000-000000000002', null, gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('now') -> 'intake', pg_temp.r('now') -> 'closed_at' <> 'null'::jsonb),
  '["closed", true]'::jsonb, 'ปิดรับทันที: สถานะปิดรับ บันทึกเวลาปิด');
select is(public.close_assignment('8c000000-0000-4000-8000-000000000002', null, gen_random_uuid()) -> 'closed_at',
  pg_temp.r('now') -> 'closed_at', 'กดปิดซ้ำคืนสถานะเดิม (เวลาปิดไม่เปลี่ยน)');
select throws_ok($$ select public.close_assignment('8c000000-0000-4000-8000-000000000002', '2099-10-03T13:00:00Z', gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'ปิดแล้วตั้งเวลาปิดรับใหม่ไม่ได้ (หน้าจอเห็นสถานะเก่า)');

select pg_temp.as_user('2c000000-0000-4000-8000-000000000011');
select is(public.submission_status('8c000000-0000-4000-8000-000000000003') -> 'outcome', '"first_on_time"',
  'งานที่ยังไม่ปิด: ส่งครั้งแรกได้ตามปกติ');
select is(public.submission_status('8c000000-0000-4000-8000-000000000002') -> 'blocked', '"submission_closed"',
  'ปิดรับแล้ว: N1 ที่เคยส่งแต่ไม่มีสิทธิ์แก้ ส่งไม่ได้');
set local role postgres;
insert into public.revision_permissions (submission_id, opened_by_account_id)
values ('5c000000-0000-4000-8000-000000000021', '3c000000-0000-4000-8000-000000000001');
set local role authenticated;
select is(public.submission_status('8c000000-0000-4000-8000-000000000002') -> 'outcome', '"resubmit_permission"',
  'แถว 7: ปิดรับแล้วแต่มีสิทธิ์แก้ค้าง → ส่งแก้ได้');

-- ช่วงรับหลังเฉลย (เผยแพร่ตรงในเทสต์ — คำสั่งเผยแพร่มากับ P4-03b) แล้วครูปิดช่วงนี้
set local role postgres;
update public.assignments set closed_at = clock_timestamp() where post_id = '8c000000-0000-4000-8000-000000000003';
insert into public.solutions (assignment_id, body, published_at) values ('8c000000-0000-4000-8000-000000000003', 'เฉลย', clock_timestamp());
set local role authenticated;
select is(pg_temp.intake('8c000000-0000-4000-8000-000000000003'), 'after_solution', 'เผยแพร่เฉลย + รับหลังเฉลย → ช่วงรับหลังเฉลย');
select is(public.submission_status('8c000000-0000-4000-8000-000000000003') -> 'outcome', '"first_after_solution"',
  'ช่วงรับหลังเฉลย: ส่งครั้งแรกได้ (สาย ไม่มีโทเคน)');
select pg_temp.as_user('2c000000-0000-4000-8000-000000000001');
insert into res values ('as_close', public.close_assignment('8c000000-0000-4000-8000-000000000003', null, gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('as_close') -> 'intake', pg_temp.r('as_close') -> 'after_solution_closed_at' <> 'null'::jsonb),
  '["closed", true]'::jsonb, 'ครูปิดช่วงรับหลังเฉลยได้');
select pg_temp.as_user('2c000000-0000-4000-8000-000000000011');
select is(public.submission_status('8c000000-0000-4000-8000-000000000003') -> 'blocked', '"submission_closed"',
  'ปิดช่วงหลังเฉลยแล้ว: ส่งครั้งแรกไม่ได้');

-- ตัวกัน: ปิดแล้วเปิดใหม่ไม่ได้
set local role postgres;
select throws_ok($$ update public.assignments set closed_at = null where post_id = '8c000000-0000-4000-8000-000000000002' $$,
  'P0001', 'immutable_field', 'ปิดรับแล้วล้าง closed_at ไม่ได้');
select throws_ok($$ update public.assignments set after_solution_closed_at = null where post_id = '8c000000-0000-4000-8000-000000000003' $$,
  'P0001', 'immutable_field', 'ปิดช่วงหลังเฉลยแล้วล้างไม่ได้');

select * from finish();
rollback;
