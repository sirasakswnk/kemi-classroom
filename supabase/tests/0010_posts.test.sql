-- ทดสอบ 0010_posts: โพสต์ งาน เฉลย — constraint (K1, J1), ตัวกันช่องที่ล็อก (N2, I4, J2/L4/K2, K4), ลบตามโพสต์ (N4)
-- และ RLS อ่าน: สมาชิกขณะนี้/ครูเจ้าของห้อง/ผู้ดูแลเท่านั้น คนนอกห้องและนักเรียนที่ถูกเอาออกอ่านไม่ได้ เขียนตรงไม่ได้ทุกบทบาท
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 9100000000000xx, อีเมล @example.com) และ rollback ตอนจบ
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

select plan(71);

-- ---------------------------------------------------------------------------
-- โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('public', 'posts', 'มี public.posts');
select has_table('public', 'assignments', 'มี public.assignments');
select has_table('public', 'solutions', 'มี public.solutions');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.posts'::regclass, 'public.assignments'::regclass, 'public.solutions'::regclass)),
  'ทั้ง 3 ตารางเปิด RLS');
select policies_are('public', 'posts', array['posts_select'], 'posts มีเฉพาะ policy อ่าน');
select policies_are('public', 'assignments', array['assignments_select'], 'assignments มีเฉพาะ policy อ่าน');
select policies_are('public', 'solutions', array['solutions_select'], 'solutions มีเฉพาะ policy อ่าน');
select is_empty(
  $$ select format('%s %s %s', r, t, p)
       from unnest(array['public.posts', 'public.assignments', 'public.solutions']) t,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege(r, t, p)
     union all
     select format('anon %s SELECT', t)
       from unnest(array['public.posts', 'public.assignments', 'public.solutions']) t
      where has_table_privilege('anon', t, 'SELECT') $$,
  'anon ไม่มีสิทธิ์ใด และ authenticated ไม่มีสิทธิ์เขียนบน posts/assignments/solutions');
select ok(
  has_table_privilege('authenticated', 'public.posts', 'SELECT')
  and has_table_privilege('authenticated', 'public.assignments', 'SELECT')
  and has_table_privilege('authenticated', 'public.solutions', 'SELECT'),
  'authenticated มี SELECT (คัดแถวด้วย RLS)');
select ok(
  has_function_privilege('authenticated', 'private.post_access(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.post_access(uuid)', 'EXECUTE'),
  'post_access: authenticated เรียกได้ (ใช้ใน policy) anon ไม่ได้');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน (ห้องละคน), ผู้ดูแล, นักเรียน 3 คน (สมาชิกห้อง 1 สองคน ห้อง 2 หนึ่งคน), บัญชียังไม่ผูก
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4a000000-0000-4000-8000-000000000001', 'ภาคทดสอบโพสต์', 'active');
insert into public.term_control (term_id) values ('4a000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';
insert into public.teachers (id, display_name) values
  ('1a000000-0000-4000-8000-000000000001', 'ครูทดสอบโพสต์หนึ่ง'),
  ('1a000000-0000-4000-8000-000000000002', 'ครูทดสอบโพสต์สอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3a000000-0000-4000-8000-000000000001', '2a000000-0000-4000-8000-000000000001', 'google', 'po-1', 'teacher10a@example.com', 'teacher', '1a000000-0000-4000-8000-000000000001'),
  ('3a000000-0000-4000-8000-000000000002', '2a000000-0000-4000-8000-000000000002', 'google', 'po-2', 'teacher10b@example.com', 'teacher', '1a000000-0000-4000-8000-000000000002'),
  ('3a000000-0000-4000-8000-000000000003', '2a000000-0000-4000-8000-000000000003', 'google', 'po-3', 'admin10@example.com', 'admin', null),
  ('3a000000-0000-4000-8000-000000000004', '2a000000-0000-4000-8000-000000000004', 'google', 'po-4', 'member10@example.com', 'student', null),
  ('3a000000-0000-4000-8000-000000000005', '2a000000-0000-4000-8000-000000000005', 'google', 'po-5', 'outsider10@example.com', 'student', null),
  ('3a000000-0000-4000-8000-000000000006', '2a000000-0000-4000-8000-000000000006', 'google', 'po-6', 'removed10@example.com', 'student', null),
  ('3a000000-0000-4000-8000-000000000007', '2a000000-0000-4000-8000-000000000007', 'google', 'po-7', 'unbound10@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6a000000-0000-4000-8000-000000000001', '910000000000001', 'สมาชิก ห้องโพสต์', '3a000000-0000-4000-8000-000000000004'),
  ('6a000000-0000-4000-8000-000000000002', '910000000000002', 'คนนอก ห้องโพสต์', '3a000000-0000-4000-8000-000000000005'),
  ('6a000000-0000-4000-8000-000000000003', '910000000000003', 'ถูกเอาออก ห้องโพสต์', '3a000000-0000-4000-8000-000000000006');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7a000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000001', 'เคมีทดสอบโพสต์ 1', 'WWWW23'),
  ('7a000000-0000-4000-8000-000000000002', '4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000002', 'เคมีทดสอบโพสต์ 2', 'WWWW24');
insert into public.memberships (classroom_id, student_id) values
  ('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000001'),
  ('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003'),
  ('7a000000-0000-4000-8000-000000000002', '6a000000-0000-4000-8000-000000000002');

-- ห้อง 1: งาน A (เฉลยยังไม่เผยแพร่), ประกาศ B, งาน C (เฉลยเผยแพร่แล้ว) · ห้อง 2: งาน D · Z ใช้ทดสอบการลบ
insert into public.posts (id, classroom_id, kind, title, body) values
  ('8a000000-0000-4000-8000-00000000000a', '7a000000-0000-4000-8000-000000000001', 'homework', 'งาน A สมดุลเคมี', 'คำนวณ K_c ของ H₂ + I₂'),
  ('8a000000-0000-4000-8000-00000000000b', '7a000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ B', null),
  ('8a000000-0000-4000-8000-00000000000c', '7a000000-0000-4000-8000-000000000001', 'homework', 'งาน C', null),
  ('8a000000-0000-4000-8000-00000000000d', '7a000000-0000-4000-8000-000000000002', 'homework', 'งาน D ห้องสอง', null),
  ('8a000000-0000-4000-8000-00000000000f', '7a000000-0000-4000-8000-000000000001', 'homework', 'งาน Z ลบทิ้ง', null);
insert into public.assignments (post_id, full_score, due_at) values
  ('8a000000-0000-4000-8000-00000000000a', 10, '2026-11-01 16:59:00+00'),
  ('8a000000-0000-4000-8000-00000000000c', 10, '2026-11-02 16:59:00+00'),
  ('8a000000-0000-4000-8000-00000000000d', 10, '2026-11-03 16:59:00+00'),
  ('8a000000-0000-4000-8000-00000000000f', 10, '2026-11-04 16:59:00+00');
insert into public.solutions (assignment_id, body, published_at) values
  ('8a000000-0000-4000-8000-00000000000a', 'เฉลย A ยังไม่เผยแพร่', null),
  ('8a000000-0000-4000-8000-00000000000c', 'เฉลย C', '2026-11-03 01:00:00+00'),
  ('8a000000-0000-4000-8000-00000000000f', 'เฉลย Z', null);

-- ---------------------------------------------------------------------------
-- constraint (K1, J1, ส่วน 5)
-- ---------------------------------------------------------------------------
select is(
  (select row(late_penalty_pct, reward_tokens, accept_after_solution, full_score_locked_at, reward_locked_at, close_at)::text
     from public.assignments where post_id = '8a000000-0000-4000-8000-00000000000a'),
  '(50,1,f,,,)',
  'ค่าเริ่มต้น: หักส่งช้า 50% (J1), โทเคน 1, ไม่รับหลังเฉลย, ยังไม่ล็อก, ไม่ตั้งวันปิดรับ');
select throws_ok($$ insert into public.posts (classroom_id, kind, title) values ('7a000000-0000-4000-8000-000000000001', 'quiz', 'x') $$,
  '23514', null, 'ชนิดโพสต์มีแค่ homework/announcement');
select throws_ok($$ insert into public.posts (classroom_id, kind, title) values ('7a000000-0000-4000-8000-000000000001', 'homework', ' ') $$,
  '23514', null, 'ชื่อโพสต์ว่างไม่ได้ (ต้องตัดช่องว่างแล้ว)');
select throws_ok($$ insert into public.posts (classroom_id, kind, title) values ('7a000000-0000-4000-8000-000000000001', 'homework', repeat('ก', 121)) $$,
  '23514', null, 'ชื่อโพสต์ยาวไม่เกิน 120');

insert into public.posts (id, classroom_id, kind, title) values
  ('8a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001', 'homework', 'งานทดสอบ constraint');
select throws_ok($$ insert into public.assignments (post_id, full_score, due_at) values ('8a000000-0000-4000-8000-000000000011', 0, '2026-11-01 16:59:00+00') $$,
  '23514', null, 'K1: คะแนนเต็มต่ำกว่า 1 ไม่ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, due_at) values ('8a000000-0000-4000-8000-000000000011', 1000001, '2026-11-01 16:59:00+00') $$,
  '23514', null, 'คะแนนเต็มเกินเพดานกันค่าล้น (1,000,000) ไม่ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, late_penalty_pct, due_at) values ('8a000000-0000-4000-8000-000000000011', 10, 101, '2026-11-01 16:59:00+00') $$,
  '23514', null, 'J1: % หักเกิน 100 ไม่ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, reward_tokens, due_at) values ('8a000000-0000-4000-8000-000000000011', 10, -1, '2026-11-01 16:59:00+00') $$,
  '23514', null, 'โทเคนรางวัลติดลบไม่ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, due_at) values ('8a000000-0000-4000-8000-000000000011', 10, '2026-11-01 16:59:30+00') $$,
  '23514', null, 'กำหนดส่งต้องเป็นนาทีเต็ม (ส่วน 5)');
select lives_ok($$ insert into public.assignments (post_id, full_score, late_penalty_pct, reward_tokens, due_at) values ('8a000000-0000-4000-8000-000000000011', 150, 0, 0, '2026-11-01 16:59:00+00') $$,
  'K1: คะแนนเต็มเกิน 100 ได้ · หัก 0% และโทเคน 0 ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, due_at) values ('8a000000-0000-4000-8000-00000000000b', 10, '2026-11-01 16:59:00+00') $$,
  'P0001', 'post_not_homework', 'ประกาศมีข้อมูลงานไม่ได้');
select throws_ok($$ insert into public.solutions (assignment_id) values ('8a000000-0000-4000-8000-00000000000b') $$,
  '23503', null, 'ประกาศมีเฉลยไม่ได้ (เฉลยอ้างงาน)');

-- ---------------------------------------------------------------------------
-- ตัวกันช่องที่ล็อก (N2, I4, J2/L4/K2, K4)
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.posts set kind = 'announcement' where id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'N2: เปลี่ยนการบ้านเป็นประกาศไม่ได้');
select throws_ok($$ update public.posts set kind = 'homework' where id = '8a000000-0000-4000-8000-00000000000b' $$,
  'P0001', 'immutable_field', 'N2: เปลี่ยนประกาศเป็นการบ้านไม่ได้');
select throws_ok($$ update public.posts set classroom_id = '7a000000-0000-4000-8000-000000000002' where id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'ย้ายโพสต์ไปห้องอื่นไม่ได้');
select throws_ok($$ update public.posts set published_at = published_at - interval '1 day' where id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'เวลาโพสต์แก้ไม่ได้');
select lives_ok($$ update public.posts set title = 'งาน A (แก้)', body = 'โจทย์ใหม่ Fe³⁺', content_updated_at = clock_timestamp(), version = version + 1
                    where id = '8a000000-0000-4000-8000-00000000000a' $$,
  'N2: ชื่อ รายละเอียด เวลาแก้โจทย์ (N1) และ version แก้ได้ตลอด');

-- ก่อนล็อก: ทุกช่องของงานแก้ได้
select lives_ok($$ update public.assignments
                      set full_score = 20, late_penalty_pct = 30, reward_tokens = 3, accept_after_solution = true,
                          due_at = '2026-11-05 16:59:00+00', close_at = '2026-11-06 17:00:00+00'
                    where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'ก่อนมีการส่ง/คะแนน: คะแนนเต็ม % หัก โทเคน รับหลังเฉลย กำหนดส่ง วันปิดรับ แก้ได้');

-- I4: มีการส่งครั้งแรก (กลุ่ม submissions ตั้ง reward_locked_at)
update public.assignments set reward_locked_at = '2026-11-01 01:00:00+00' where post_id = '8a000000-0000-4000-8000-00000000000a';
select throws_ok($$ update public.assignments set reward_tokens = 5 where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'reward_locked', 'I4: หลังมีการส่งครั้งแรก จำนวนโทเคนรางวัลแก้ไม่ได้');
select throws_ok($$ update public.assignments set reward_locked_at = null where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'I4: ปลดล็อกจำนวนรางวัลไม่ได้');
select throws_ok($$ update public.assignments set reward_locked_at = reward_locked_at + interval '1 hour' where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'I4: เลื่อนเวลาล็อกรางวัลไม่ได้');
select lives_ok($$ update public.assignments set full_score = 25, late_penalty_pct = 40 where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'ล็อกแยกกัน: ล็อกรางวัลแล้วยังแก้คะแนนเต็มและ % หักได้จนบันทึกคะแนนแรก');

-- J2/L4/K2: บันทึกคะแนนที่ทำได้ครั้งแรก (กลุ่ม grading ตั้ง full_score_locked_at)
update public.assignments set full_score_locked_at = '2026-11-07 01:00:00+00' where post_id = '8a000000-0000-4000-8000-00000000000a';
select throws_ok($$ update public.assignments set full_score = 30 where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'full_score_locked', 'J2/L4: หลังบันทึกคะแนนแรก คะแนนเต็มแก้ไม่ได้');
select throws_ok($$ update public.assignments set late_penalty_pct = 0 where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'full_score_locked', 'K2: % หักส่งช้าล็อกพร้อมคะแนนเต็ม');
select throws_ok($$ update public.assignments set full_score_locked_at = null where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'P0001', 'immutable_field', 'ปลดล็อกคะแนนเต็มไม่ได้');
select lives_ok($$ update public.assignments
                      set full_score = 25, late_penalty_pct = 40, reward_tokens = 3,
                          due_at = '2026-11-04 16:59:00+00', close_at = null
                    where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'ล็อกแล้วส่งค่าเดิมของช่องที่ล็อกได้ (ฟอร์มส่งทุกช่อง) และกำหนดส่ง/วันปิดรับยังแก้ได้ (N3)');
select is(
  (select row(full_score, late_penalty_pct, reward_tokens, accept_after_solution)::text
     from public.assignments where post_id = '8a000000-0000-4000-8000-00000000000a'),
  '(25,40,3,t)',
  'ค่าที่ล็อกยังเป็นค่าก่อนล็อก');

-- N2: รับหลังเฉลยแก้ได้จนเผยแพร่เฉลย
select lives_ok($$ update public.assignments set accept_after_solution = false where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  'N2: เฉลยยังไม่เผยแพร่ แก้ "รับงานหลังเผยแพร่เฉลย" ได้');
select throws_ok($$ update public.assignments set accept_after_solution = true where post_id = '8a000000-0000-4000-8000-00000000000c' $$,
  'P0001', 'after_solution_locked', 'N2: เผยแพร่เฉลยแล้ว แก้ "รับงานหลังเผยแพร่เฉลย" ไม่ได้');

-- K4: แก้เฉลยหลังเผยแพร่ได้ แต่คงเวลาเผยแพร่ครั้งแรก
select lives_ok($$ update public.solutions set body = 'เฉลย C (แก้)', updated_at = clock_timestamp(), version = version + 1
                    where assignment_id = '8a000000-0000-4000-8000-00000000000c' $$,
  'K4: แก้ข้อความเฉลยหลังเผยแพร่ได้');
select throws_ok($$ update public.solutions set published_at = clock_timestamp() where assignment_id = '8a000000-0000-4000-8000-00000000000c' $$,
  'P0001', 'immutable_field', 'K4: เวลาเผยแพร่ครั้งแรกเปลี่ยนไม่ได้');
select throws_ok($$ update public.solutions set published_at = null where assignment_id = '8a000000-0000-4000-8000-00000000000c' $$,
  'P0001', 'immutable_field', 'ยกเลิกการเผยแพร่เฉลยไม่ได้');

-- N4: ลบโพสต์แล้วงานและเฉลยหายตาม
delete from public.posts where id = '8a000000-0000-4000-8000-00000000000f';
select ok(
  not exists (select 1 from public.assignments where post_id = '8a000000-0000-4000-8000-00000000000f')
  and not exists (select 1 from public.solutions where assignment_id = '8a000000-0000-4000-8000-00000000000f'),
  'N4: ลบโพสต์แล้วข้อมูลงานและเฉลยถูกลบตาม');

-- ---------------------------------------------------------------------------
-- RLS อ่าน
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select * from public.posts $$, '42501', null, 'anon อ่าน posts ไม่ได้');

set local role authenticated;
-- สมาชิกห้อง 1
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select set_eq($$ select id from public.posts $$,
  array['8a000000-0000-4000-8000-00000000000a', '8a000000-0000-4000-8000-00000000000b',
        '8a000000-0000-4000-8000-00000000000c', '8a000000-0000-4000-8000-000000000011']::uuid[],
  'สมาชิกเห็นโพสต์ของห้องตัวเองทั้งงานและประกาศ ไม่เห็นห้องอื่น');
select set_eq($$ select post_id from public.assignments $$,
  array['8a000000-0000-4000-8000-00000000000a', '8a000000-0000-4000-8000-00000000000c',
        '8a000000-0000-4000-8000-000000000011']::uuid[],
  'สมาชิกเห็นข้อมูลงานของห้องตัวเอง');
select set_eq($$ select assignment_id from public.solutions $$,
  array['8a000000-0000-4000-8000-00000000000c']::uuid[],
  'สมาชิกเห็นเฉพาะเฉลยที่เผยแพร่แล้ว');
select throws_ok($$ select private.post_access('8a000000-0000-4000-8000-00000000000a') $$, '42501', null,
  'เรียก private.post_access ตรง ๆ ไม่ได้ (ไม่มี USAGE บน private)');

-- คนนอกห้อง (สมาชิกห้อง 2)
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select set_eq($$ select id from public.posts $$, array['8a000000-0000-4000-8000-00000000000d']::uuid[],
  'คนนอกห้องไม่เห็นโพสต์ของห้อง 1 (เห็นเฉพาะห้องที่ตนเป็นสมาชิก)');
select is_empty($$ select post_id from public.assignments where post_id <> '8a000000-0000-4000-8000-00000000000d'
                    union all select assignment_id from public.solutions $$,
  'คนนอกห้องไม่เห็นข้อมูลงานหรือเฉลยของห้อง 1');
select is((select count(*)::integer from public.posts where id = '8a000000-0000-4000-8000-00000000000a'), 0,
  'คนนอกห้องอ่านโพสต์ด้วย id ตรง ๆ ก็ไม่ได้');

-- บัญชีนักเรียนที่ยังไม่ผูกชื่อ
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is_empty($$ select id from public.posts union all select post_id from public.assignments
                    union all select assignment_id from public.solutions $$,
  'ยังไม่ผูกชื่อ: ไม่เห็นโพสต์ งาน หรือเฉลย');

-- ครูเจ้าของห้อง 1
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select set_eq($$ select id from public.posts $$,
  array['8a000000-0000-4000-8000-00000000000a', '8a000000-0000-4000-8000-00000000000b',
        '8a000000-0000-4000-8000-00000000000c', '8a000000-0000-4000-8000-000000000011']::uuid[],
  'ครูเห็นโพสต์ของห้องตัวเองเท่านั้น');
select set_eq($$ select assignment_id from public.solutions $$,
  array['8a000000-0000-4000-8000-00000000000a', '8a000000-0000-4000-8000-00000000000c']::uuid[],
  'ครูเห็นเฉลยทั้งที่ยังไม่เผยแพร่และเผยแพร่แล้ว');
-- ครูห้อง 2
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select set_eq($$ select id from public.posts $$, array['8a000000-0000-4000-8000-00000000000d']::uuid[],
  'ครูอีกคนไม่เห็นโพสต์ของห้องที่ไม่ได้สอน');
select is_empty($$ select assignment_id from public.solutions $$, 'ครูอีกคนไม่เห็นเฉลยของห้องที่ไม่ได้สอน');
-- ผู้ดูแล (อ่านได้โดยไม่ต้องอยู่ในโหมดผู้ดูแล เหมือน classrooms — การเขียนตรวจโหมดใน RPC)
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is((select count(*)::integer from public.posts where classroom_id in ('7a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000002')),
  5, 'ผู้ดูแลอ่านโพสต์ได้ทุกห้อง');

-- นักเรียนที่ถูกเอาออก: อ่านได้ระหว่างเป็นสมาชิก แล้วอ่านไม่ได้ทันทีหลังครูเอาออก
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is((select count(*)::integer from public.posts), 4, 'ก่อนถูกเอาออก: เห็นโพสต์ของห้อง 1');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select lives_ok($$ select public.remove_member('7a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003') $$,
  'ครูเอานักเรียนออกจากห้อง 1');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is_empty($$ select id from public.posts union all select post_id from public.assignments
                    union all select assignment_id from public.solutions $$,
  'ถูกเอาออกแล้ว: ไม่เห็นโพสต์ งาน หรือเฉลย (รวมเฉลยที่เผยแพร่แล้ว) ทันที');

-- ---------------------------------------------------------------------------
-- เขียนตรงไม่ได้ (เขียนผ่าน RPC เท่านั้น)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ insert into public.posts (classroom_id, kind, title) values ('7a000000-0000-4000-8000-000000000001', 'announcement', 'นักเรียนโพสต์') $$,
  '42501', null, 'นักเรียนเพิ่ม posts ตรงไม่ได้');
select throws_ok($$ update public.posts set title = 'แก้' where id = '8a000000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'นักเรียนแก้ posts ตรงไม่ได้');
select throws_ok($$ delete from public.posts where id = '8a000000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'นักเรียนลบ posts ตรงไม่ได้');
select throws_ok($$ insert into public.assignments (post_id, full_score, due_at) values ('8a000000-0000-4000-8000-00000000000b', 10, '2026-11-01 16:59:00+00') $$,
  '42501', null, 'นักเรียนเพิ่ม assignments ตรงไม่ได้');
select throws_ok($$ update public.assignments set reward_tokens = 100 where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'นักเรียนแก้ assignments ตรงไม่ได้ (เช่นเพิ่มโทเคนรางวัล)');
select throws_ok($$ delete from public.assignments where post_id = '8a000000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'นักเรียนลบ assignments ตรงไม่ได้');
select throws_ok($$ insert into public.solutions (assignment_id, published_at) values ('8a000000-0000-4000-8000-000000000011', clock_timestamp()) $$,
  '42501', null, 'นักเรียนเพิ่ม solutions ตรงไม่ได้');
select throws_ok($$ update public.solutions set published_at = clock_timestamp() where assignment_id = '8a000000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'นักเรียนแก้ solutions ตรงไม่ได้ (เช่นเผยแพร่เฉลยเอง)');
select throws_ok($$ delete from public.solutions where assignment_id = '8a000000-0000-4000-8000-00000000000c' $$,
  '42501', null, 'นักเรียนลบ solutions ตรงไม่ได้');
set local request.jwt.claims to '{"sub": "2a000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ insert into public.posts (classroom_id, kind, title) values ('7a000000-0000-4000-8000-000000000001', 'announcement', 'ครูเขียนตรง') $$,
  '42501', null, 'ครูก็เขียน posts ตรงไม่ได้ (ต้องผ่าน RPC)');
select throws_ok($$ update public.assignments set full_score = 99 where post_id = '8a000000-0000-4000-8000-00000000000c' $$,
  '42501', null, 'ครูก็แก้ assignments ตรงไม่ได้ (ต้องผ่าน RPC)');

select * from finish();
rollback;
