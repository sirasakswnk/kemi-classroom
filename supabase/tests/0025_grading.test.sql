-- ทดสอบ 0025_grading: สูตรคะแนน (ชุดร่วมกับหน้าเว็บ), grade_submission (K1, K2, L2, L4, J3, I1–I3, รุ่นไฟล์/รุ่นผลตรวจ,
-- คำขอซ้ำ, สิทธิ์), RLS ของ grades/comments, และผลต่อ "รุ่นล่าสุดมีผลตรวจแล้ว" (ตารางรับการส่งแถว 5/6, รอตรวจของครู)
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

select plan(53);

-- ---------------------------------------------------------------------------
-- ก: โครงและสิทธิ์
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select r || ' ' || f from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.grade_net_score(integer,integer)', 'private.submission_latest_graded(uuid)']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'สูตรคะแนนและ submission_latest_graded ใช้ภายในเท่านั้น');
select is_empty(
  $$ select c.relname from pg_class c
      where c.oid in ('public.grades'::regclass, 'public.comments'::regclass) and not c.relrowsecurity $$,
  'grades และ comments เปิด RLS');
select is_empty(
  $$ select tablename || ' ' || cmd from pg_policies
      where schemaname = 'public' and tablename in ('grades', 'comments') and cmd <> 'SELECT' $$,
  'ไม่มี policy เขียน (เขียนผ่าน RPC เท่านั้น)');
select is_empty(
  $$ select r || ' ' || t || ' ' || p
       from unnest(array['anon', 'authenticated']) r,
            unnest(array['public.grades', 'public.comments']) t,
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p
      where has_table_privilege(r, t, p) $$,
  'anon/authenticated ไม่มีสิทธิ์เขียนตาราง');

-- ---------------------------------------------------------------------------
-- ข: ชุดสูตรคะแนน — ข้อความ JSON ใน dollar quote ชื่อ cases ต้องตรงกับ supabase/tests/fixtures/score_cases.json
--    (Vitest web/src/features/grading/score.test.ts ตรวจว่าตรงกัน)
-- ---------------------------------------------------------------------------
select is_empty(
  format($q$ select c from jsonb_array_elements(%L::jsonb) c
              where private.grade_net_score((c ->> 'raw')::integer, (c ->> 'pct')::integer) <> (c ->> 'net')::integer $q$,
  $cases$[
  { "raw": 7, "pct": 50, "net": 4, "note": "ค่าเริ่มต้น 50%: 3.5 → 4" },
  { "raw": 9, "pct": 50, "net": 5, "note": "4.5 → 5" },
  { "raw": 7, "pct": 30, "net": 5, "note": "4.9 → 5" },
  { "raw": 7, "pct": 20, "net": 6, "note": "ปรับรายคน 20%: 5.6 → 6" },
  { "raw": 7, "pct": 0, "net": 7, "note": "0% = ยกเว้น" },
  { "raw": 149, "pct": 50, "net": 75, "note": "คะแนนเต็ม 150 (K1): 74.5 → 75" },
  { "raw": 8, "pct": 50, "net": 4, "note": "ลงตัวไม่ปัดเพิ่ม" },
  { "raw": 0, "pct": 50, "net": 0, "note": "ศูนย์คะแนน" },
  { "raw": 10, "pct": 100, "net": 0, "note": "หักทั้งหมด" },
  { "raw": 1, "pct": 99, "net": 1, "note": "0.01 → 1" },
  { "raw": 999999, "pct": 33, "net": 670000, "note": "669999.33 → 670000" },
  { "raw": 1000000, "pct": 1, "net": 990000, "note": "เพดานกันพิมพ์ผิด ไม่ล้น integer" }
]$cases$),
  'ชุดสูตรคะแนนร่วม: (raw × (100 − pct) + 99) / 100 ตรงทุกแถว');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 1 (ห้อง 1), ครู 2 (ห้อง 2), ผู้ดูแล; นักเรียน N1 (บัญชี), N2 (บัญชี), N4, N5 สมาชิกห้อง 1
-- H1 เต็ม 10 หัก 50% กำหนดผ่านแล้ว: N1 ส่งทัน · N2 ส่งช้า · N4 ส่งแรกทัน ส่งแก้หลังกำหนด (I1) · N5 ส่งแรกหลังเฉลย
-- H2 เต็ม 150 กำหนดอนาคต: N1 ส่งแล้ว (ยังแก้ได้จนถูกตรวจ — แถว 5)
-- H3 เต็ม 150 หัก 50% กำหนดผ่านแล้ว: N2 ส่งช้า
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4e000000-0000-4000-8000-000000000001', 'ภาคทดสอบตรวจงาน', 'active');
insert into public.term_control (term_id) values ('4e000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e000000-0000-4000-8000-000000000001', 'ครูตรวจหนึ่ง'), ('1e000000-0000-4000-8000-000000000002', 'ครูตรวจสอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e000000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'google', 'gr-1', 't25a@example.com', 'teacher', '1e000000-0000-4000-8000-000000000001'),
  ('3e000000-0000-4000-8000-000000000002', '2e000000-0000-4000-8000-000000000002', 'google', 'gr-2', 't25b@example.com', 'teacher', '1e000000-0000-4000-8000-000000000002'),
  ('3e000000-0000-4000-8000-000000000003', '2e000000-0000-4000-8000-000000000003', 'google', 'gr-3', 'a25@example.com', 'admin', null),
  ('3e000000-0000-4000-8000-000000000011', '2e000000-0000-4000-8000-000000000011', 'google', 'gr-11', 's25a@example.com', 'student', null),
  ('3e000000-0000-4000-8000-000000000012', '2e000000-0000-4000-8000-000000000012', 'google', 'gr-12', 's25b@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e000000-0000-4000-8000-000000000001', '925000000000251', 'หนึ่ง ตรวจ', '3e000000-0000-4000-8000-000000000011'),
  ('6e000000-0000-4000-8000-000000000002', '925000000000252', 'สอง ตรวจ', '3e000000-0000-4000-8000-000000000012'),
  ('6e000000-0000-4000-8000-000000000004', '925000000000254', 'สี่ ตรวจ', null),
  ('6e000000-0000-4000-8000-000000000005', '925000000000255', 'ห้า ตรวจ', null);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000001', 'เคมีตรวจ 1', 'ZZZZ74'),
  ('7e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000002', 'เคมีตรวจ 2', 'ZZZZ75');
insert into public.memberships (classroom_id, student_id)
select '7e000000-0000-4000-8000-000000000001', s.id from public.students s where s.id::text like '6e000000-%';
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8e000000-0000-4000-8000-000000000001', '7e000000-0000-4000-8000-000000000001', 'homework', 'งานตรวจหนึ่ง', '2026-09-20T01:00:00Z'),
  ('8e000000-0000-4000-8000-000000000002', '7e000000-0000-4000-8000-000000000001', 'homework', 'งานตรวจสอง', '2026-09-21T01:00:00Z'),
  ('8e000000-0000-4000-8000-000000000003', '7e000000-0000-4000-8000-000000000001', 'homework', 'งานตรวจสาม', '2026-09-22T01:00:00Z');
insert into public.assignments (post_id, full_score, late_penalty_pct, due_at) values
  ('8e000000-0000-4000-8000-000000000001', 10, 50, '2026-09-30T13:00:00Z'),
  ('8e000000-0000-4000-8000-000000000002', 150, 50, '2099-10-10T13:00:00Z'),
  ('8e000000-0000-4000-8000-000000000003', 150, 50, '2026-09-30T13:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, content_revision, first_after_solution) values
  ('5e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', 1, false),
  ('5e000000-0000-4000-8000-000000000002', '8e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000002', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', 1, false),
  ('5e000000-0000-4000-8000-000000000004', '8e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000004', '2026-09-29T01:00:00Z', '2026-10-02T01:00:00Z', 2, false),
  ('5e000000-0000-4000-8000-000000000005', '8e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000005', '2026-09-29T02:00:00Z', '2026-09-29T02:00:00Z', 1, true),
  ('5e000000-0000-4000-8000-000000000006', '8e000000-0000-4000-8000-000000000002', '6e000000-0000-4000-8000-000000000001', '2026-10-10T01:00:00Z', '2026-10-10T01:00:00Z', 1, false),
  ('5e000000-0000-4000-8000-000000000007', '8e000000-0000-4000-8000-000000000003', '6e000000-0000-4000-8000-000000000002', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', 1, false);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
-- ผลตรวจแบบสั้นเพื่อเทียบ: [raw, passed, timing, pct, deduction, net, override, version]
create function pg_temp.brief(p jsonb) returns jsonb language sql immutable as
  $$ select jsonb_build_array(p -> 'raw_score', p -> 'passed', p -> 'timing', p -> 'applied_penalty_pct',
                              p -> 'deduction', p -> 'net_score', p -> 'penalty_override_pct', p -> 'version') $$;
grant execute on function pg_temp.brief(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- ค: นักเรียนก่อนถูกตรวจ — แถว 5 (ส่งแก้ได้เพราะยังไม่ถึงกำหนดและยังไม่มีผลตรวจ)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select is(public.submission_status('8e000000-0000-4000-8000-000000000002') -> 'outcome', '"resubmit"',
  'แถว 5: ก่อนถูกตรวจ ส่งแก้ได้โดยไม่ใช้สิทธิ์');

-- ---------------------------------------------------------------------------
-- ง: ครูเจ้าของห้อง
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000001", "role": "authenticated"}';

-- L4: บันทึกเฉพาะผ่าน ไม่ล็อกคะแนนเต็ม
insert into res values ('h2_pass', public.grade_submission('5e000000-0000-4000-8000-000000000006', null, true, null, null, 1, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h2_pass')), '[null, true, "on_time", 0, null, null, null, 1]'::jsonb,
  'บันทึกเฉพาะผ่าน: ไม่มีคะแนน ไม่หัก');
select is((select full_score_locked_at from public.assignments where post_id = '8e000000-0000-4000-8000-000000000002'), null,
  'L4: บันทึกเฉพาะผ่านไม่ล็อกคะแนนเต็ม/% หัก');
select is((pg_temp.r('h2_pass') -> 'full_score_locked'), 'false'::jsonb, 'ผลบอกว่ายังไม่ล็อก');

-- K1: คะแนนดิบ 0–คะแนนเต็ม
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 11, false, null, null, 1, 0, gen_random_uuid()) $$,
  'P0001', 'score_invalid', 'คะแนนเกินเต็มถูกปฏิเสธ');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', -1, false, null, null, 1, 0, gen_random_uuid()) $$,
  'P0001', 'score_invalid', 'คะแนนติดลบถูกปฏิเสธ');
select is((select full_score_locked_at from public.assignments where post_id = '8e000000-0000-4000-8000-000000000001'), null,
  'บันทึกที่ถูกปฏิเสธไม่ล็อกคะแนนเต็ม');

-- งานสาย: หักตาม % ของงาน + ล็อก (L4/K2)
insert into res values ('h1_late', public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, false, null, null, 1, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h1_late')), '[7, false, "late", 50, 3, 4, null, 1]'::jsonb,
  'ส่งช้า 7 คะแนน หัก 50% → 4');
select isnt((select full_score_locked_at from public.assignments where post_id = '8e000000-0000-4000-8000-000000000001'), null,
  'L4: คะแนนดิบแรกล็อกคะแนนเต็มและ % หัก');
select is((pg_temp.r('h1_late') -> 'full_score_locked'), 'true'::jsonb, 'ผลบอกว่าล็อกแล้ว');
select is((pg_temp.r('h1_late') -> 'reward_granted'), 'false'::jsonb, 'งานสายไม่ได้รางวัล');

insert into res values ('h3', public.grade_submission('5e000000-0000-4000-8000-000000000007', 149, true, null, null, 1, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h3')), '[149, true, "late", 50, 74, 75, null, 1]'::jsonb,
  'K1: คะแนนเต็ม 150 ใช้ได้ (149 หัก 50% → 75)');

-- L2/J3: ปรับรายคนต้องมีเหตุผล
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, false, 20, null, 1, 1, gen_random_uuid()) $$,
  'P0001', 'reason_required', 'ปรับรายคนไม่มีเหตุผลบันทึกไม่ได้');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, false, 20, '   ', 1, 1, gen_random_uuid()) $$,
  'P0001', 'reason_required', 'เหตุผลที่เป็นช่องว่างล้วนนับว่าไม่มี');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, false, 101, 'x', 1, 1, gen_random_uuid()) $$,
  'P0001', 'late_penalty_invalid', '% หักรายคนเกิน 100 ถูกปฏิเสธ');
insert into res values ('h1_ovr', public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, false, 20, '  ป่วยมีใบรับรองแพทย์  ', 1, 1, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h1_ovr')), '[7, false, "late", 20, 1, 6, 20, 2]'::jsonb,
  'ปรับเฉพาะคน 20%: 7 → 6');
select is((select jsonb_build_array(c.body, c.author_account_id, c.student_id, c.assignment_id) from public.comments c
            where c.id = (pg_temp.r('h1_ovr') ->> 'override_comment_id')::uuid),
  '["ป่วยมีใบรับรองแพทย์", "3e000000-0000-4000-8000-000000000001", "6e000000-0000-4000-8000-000000000002", "8e000000-0000-4000-8000-000000000001"]'::jsonb,
  'J3: เหตุผลเป็นความคิดเห็นส่วนตัวของครูในช่องของนักเรียนคนนั้น (ตัดช่องว่างหัวท้าย)');
insert into res values ('h1_same', public.grade_submission('5e000000-0000-4000-8000-000000000002', 8, false, 20, null, 1, 2, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h1_same')) || (pg_temp.r('h1_same') -> 'override_comment_id'),
  '[8, false, "late", 20, 1, 7, 20, 3]'::jsonb || (pg_temp.r('h1_ovr') -> 'override_comment_id'),
  'แก้คะแนนโดยคง % เดิม: ไม่ต้องมีเหตุผลใหม่ เหตุผลเดิมยังผูกอยู่ (J2 แก้คะแนนได้ตลอด)');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 8, false, 20, 'ซ้ำ', 1, 3, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ส่งเหตุผลมาโดยไม่ได้เปลี่ยน % ถูกปฏิเสธ (ไม่สร้างความคิดเห็นเกิน)');
insert into res values ('h1_exempt', public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, true, 0, 'ยกเว้นเพราะระบบล่ม', 1, 3, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('h1_exempt')), '[7, true, "late", 0, 0, 7, 0, 4]'::jsonb, 'L2: 0% = ยกเว้น');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000002', 7, true, null, null, 1, 4, gen_random_uuid()) $$,
  'P0001', 'reason_required', 'ล้างการปรับรายคนต้องมีเหตุผล');
select is((select count(*)::integer from public.comments where student_id = '6e000000-0000-4000-8000-000000000002'), 2,
  'สร้างความคิดเห็นเฉพาะตอนตั้ง/เปลี่ยน % (2 ครั้ง)');

-- งานที่ทัน: ปรับรายคนไม่ได้
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, true, 0, 'x', 1, 0, gen_random_uuid()) $$,
  'P0001', 'penalty_not_late', 'งานที่ส่งทันปรับการหักรายคนไม่ได้');

-- I1: ส่งแรกทัน ส่งแก้หลังกำหนดตามสิทธิ์ — ไม่หัก
insert into res values ('i1', public.grade_submission('5e000000-0000-4000-8000-000000000004', 8, true, null, null, 2, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('i1')) || (pg_temp.r('i1') -> 'timing_i1'), '[8, true, "on_time", 0, 0, 8, null, 1, true]'::jsonb,
  'I1: ไม่หักเพราะเวลาส่งแก้ (ฐานเวลา = ส่งครั้งแรก)');
-- ส่งแรกหลังเฉลย = สายเสมอ
insert into res values ('after_sol', public.grade_submission('5e000000-0000-4000-8000-000000000005', 7, true, null, null, 1, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('after_sol')), '[7, true, "late", 50, 3, 4, null, 1]'::jsonb,
  'ส่งครั้งแรกหลังเฉลยนับเป็นสายแม้ส่งก่อนกำหนด');

-- รุ่นไฟล์และรุ่นผลตรวจ
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, true, null, null, 0, 0, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'บันทึกบนรุ่นไฟล์ที่ไม่ตรง → stale_revision');
insert into res values ('n1', public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, true, null, null, 1, 0, 'c5000000-0000-4000-8000-000000000001'));
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 10, true, null, null, 1, 0, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'หน้าจออื่นบันทึกไปก่อน (version ไม่ตรง) → stale_revision');

-- คำขอซ้ำ
select is(public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, true, null, null, 1, 0, 'c5000000-0000-4000-8000-000000000001'),
  pg_temp.r('n1'), 'กดซ้ำด้วย request key เดิมคืนผลเดิม');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 10, true, null, null, 1, 0, 'c5000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมกับข้อมูลอื่น → request_key_conflict');

-- I3: ผ่าน → ไม่ผ่านได้ (รางวัลจากการตรวจผ่านครั้งก่อนไม่ถูกถอน — 0035; ชุดเต็มของโทเคนอยู่ใน 0035_grade_reward.test.sql)
insert into res values ('n1_fail', public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, false, null, null, 1, 1, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('n1_fail')) || (pg_temp.r('n1_fail') -> 'reward_granted'), '[9, false, "on_time", 0, 0, 9, null, 2, true]'::jsonb,
  'I3: เปลี่ยนผ่านเป็นไม่ผ่านได้ (reward_granted คงเป็น true)');

-- ยอดรอตรวจและสถานะรายคนของครู (P3-09)
select is((select (e -> 'waiting') from jsonb_array_elements(public.teacher_work_summary('7e000000-0000-4000-8000-000000000001')) e
            where e ->> 'post_id' = '8e000000-0000-4000-8000-000000000001'), '0'::jsonb, 'H1 ตรวจครบ: รอตรวจ 0');
select is((select e -> 'graded' from jsonb_array_elements(public.teacher_submission_list('8e000000-0000-4000-8000-000000000002') -> 'rows') e
            where e ->> 'student_id' = '6e000000-0000-4000-8000-000000000001'), 'true'::jsonb, 'รายชื่อ T03: graded = true');

-- ---------------------------------------------------------------------------
-- จ: สิทธิ์ของบทบาทอื่น
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 9, true, null, null, 1, 2, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นตรวจไม่ได้');
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-0000000000ff', 9, true, null, null, 1, 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'งานส่งที่ไม่มี → forbidden');
select is((select count(*)::integer from public.grades g where g.submission_id::text like '5e000000-%'), 0, 'RLS: ครูห้องอื่นไม่เห็นผลตรวจ');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 10, true, null, null, 1, 2, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนตรวจไม่ได้');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000001', 10, true, null, null, 1, 2, gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลตรวจไม่ได้');
select is(public.grade_submission('5e000000-0000-4000-8000-000000000001', 10, true, null, null, 1, 2, gen_random_uuid(), true) -> 'net_score',
  '10'::jsonb, 'ผู้ดูแลในโหมดผู้ดูแลตรวจได้');

-- ---------------------------------------------------------------------------
-- ฉ: RLS ของนักเรียน + ตารางรับการส่งแถว 6/5 เมื่อมีผลตรวจจริง
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000012", "role": "authenticated"}';
select is((select jsonb_agg(g.net_score order by g.net_score) from public.grades g), '[7, 75]'::jsonb,
  'RLS: นักเรียนเห็นผลตรวจของตัวเองเท่านั้น');
select is((select jsonb_agg(c.body order by c.created_at) from public.comments c),
  '["ป่วยมีใบรับรองแพทย์", "ยกเว้นเพราะระบบล่ม"]'::jsonb, 'RLS: นักเรียนเห็นเหตุผลการปรับในความคิดเห็นของตัวเอง');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select is((select count(*)::integer from public.comments), 0, 'RLS: นักเรียนอื่นไม่เห็นความคิดเห็นของเพื่อน');
select is(public.submission_status('8e000000-0000-4000-8000-000000000002') -> 'blocked', '"resubmit_not_allowed"',
  'แถว 6: รุ่นล่าสุดมีผลตรวจแล้ว ส่งแก้ต้องมีสิทธิ์ (แม้ยังไม่ถึงกำหนด)');

set local role postgres;
insert into public.revision_permissions (submission_id, opened_by_account_id)
values ('5e000000-0000-4000-8000-000000000006', '3e000000-0000-4000-8000-000000000001');
set local role authenticated;
select is(public.submission_status('8e000000-0000-4000-8000-000000000002') -> 'outcome', '"resubmit_permission"',
  'แถว 6: มีสิทธิ์แก้ค้าง → ส่งแก้ได้โดยใช้สิทธิ์');

-- นักเรียนส่งแก้แล้ว (จำลองผลของ submit_assignment): ผลเดิมเป็นของรุ่นก่อน → รอตรวจใหม่
set local role postgres;
update public.submissions set content_revision = 2, last_submitted_at = '2026-10-11T01:00:00Z'
 where id = '5e000000-0000-4000-8000-000000000006';
update public.revision_permissions set status = 'used', used_at = '2026-10-11T01:00:00Z', used_revision = 2
 where submission_id = '5e000000-0000-4000-8000-000000000006';
set local role authenticated;
select is(public.submission_status('8e000000-0000-4000-8000-000000000002') -> 'outcome', '"resubmit"',
  'แถว 5: รุ่นใหม่ยังไม่มีผลตรวจ ยังไม่ถึงกำหนด → ส่งแก้ได้อีกโดยไม่ใช้สิทธิ์');
select is((select jsonb_build_array(g.graded_revision, g.passed) from public.grades g
            where g.submission_id = '5e000000-0000-4000-8000-000000000006'), '[1, true]'::jsonb,
  'ผลเดิมยังอยู่ (ของรุ่น 1) ไม่ถูกลบ');

-- ครูที่ยังเปิดหน้ารุ่น 1 อยู่บันทึกไม่ได้ (ไฟล์เปลี่ยนแล้ว) และรายการแสดงรอตรวจ
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.grade_submission('5e000000-0000-4000-8000-000000000006', 120, true, null, null, 1, 1, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'นักเรียนส่งใหม่ระหว่างครูตรวจรุ่นเก่า → stale_revision');
select is((select e -> 'graded' from jsonb_array_elements(public.teacher_submission_list('8e000000-0000-4000-8000-000000000002') -> 'rows') e
            where e ->> 'student_id' = '6e000000-0000-4000-8000-000000000001'), 'false'::jsonb,
  'หลังส่งแก้ T03 แสดงรอตรวจ (graded = false)');

-- K5: ภาคเรียนจบแล้วครูยังตรวจได้
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select is(public.grade_submission('5e000000-0000-4000-8000-000000000006', 120, true, null, null, 2, 1, gen_random_uuid()) -> 'graded_revision',
  '2'::jsonb, 'K5: ภาคเรียนจบแล้วครูยังตรวจได้ (ตรวจรุ่นล่าสุด)');

select * from finish();
rollback;
