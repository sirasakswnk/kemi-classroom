-- ทดสอบ 0035_grade_reward: ให้รางวัลใน transaction เดียวกับผลตรวจ (TECHNICAL_DESIGN ส่วน 6 ข้อ 6–7)
-- ครั้งเดียว/ตรวจซ้ำ/คำขอซ้ำ, ผ่าน→ไม่ผ่าน→ผ่าน (I3), ส่งช้า/ส่งแรกหลังเฉลย/งาน 0 โทเคน, งานเทอมเก่า (I5),
-- จบภาคเรียนแล้วยังให้ (K5), เปลี่ยนกำหนดส่งสองทิศ (N3), แก้เฉลยหลังเผยแพร่ (K4), ลบงาน (N4)
-- การตรวจพร้อมกันจริงสองการเชื่อมต่อ: ops/concurrency/grade-reward.mjs (ฐานข้อมูลในเครื่องเท่านั้น)
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

select plan(24);

-- ข้อมูลสมมติ: เทอมกระเป๋า T1 + เทอมเก่า T0; ครู 1 คน ห้อง C1 (T1) และ C0 (T0)
-- H1 (C1, 2 โทเคน, กำหนด 30 ก.ย. 20:00 น.): S1 N1 ทัน · S2 N2 สาย · S3 N3 ส่งแรกหลังเฉลย · S4 N4 ทัน · S5 N5 สาย (ยังไม่ตรวจ)
-- H0 (C0, 2): S6 N1 ทัน · HZ (C1, 0 โทเคน): S7 N2 ทัน · H2 (C1, 1): S10 N3 ทัน
-- HK (C1, 1): S9 N6 ทัน (เฉลย) · HN (C1, 3): S8 N6 ทัน (ลบงาน)
insert into public.terms (id, name, status) values ('40350000-0000-4000-8000-000000000001', 'ภาคทดสอบให้รางวัล', 'active');
insert into public.terms (id, name, status, ended_at, superseded_at) values
  ('40350000-0000-4000-8000-000000000002', 'ภาคเก่าทดสอบให้รางวัล', 'superseded', '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z');
insert into public.term_control (term_id) values ('40350000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10350000-0000-4000-8000-000000000001', 'ครูให้รางวัล');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30350000-0000-4000-8000-000000000001', '20350000-0000-4000-8000-000000000001', 'google', 'gr-1', 't35@example.com', 'teacher', '10350000-0000-4000-8000-000000000001');
insert into public.students (id, student_code, display_name)
select ('60350000-0000-4000-8000-00000000000' || n)::uuid, '93500000000035' || n, 'นักเรียนรางวัล ' || n
  from generate_series(1, 6) n;
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70350000-0000-4000-8000-000000000001', '40350000-0000-4000-8000-000000000001', '10350000-0000-4000-8000-000000000001', 'เคมีให้รางวัล', 'ZZZZ35'),
  ('70350000-0000-4000-8000-000000000002', '40350000-0000-4000-8000-000000000002', '10350000-0000-4000-8000-000000000001', 'เคมีเทอมเก่า', 'ZZZZ36');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80350000-0000-4000-8000-000000000001', '70350000-0000-4000-8000-000000000001', 'homework', 'H1', '2026-09-20T01:00:00Z'),
  ('80350000-0000-4000-8000-000000000002', '70350000-0000-4000-8000-000000000002', 'homework', 'H0', '2026-04-20T01:00:00Z'),
  ('80350000-0000-4000-8000-000000000003', '70350000-0000-4000-8000-000000000001', 'homework', 'HZ', '2026-09-20T01:00:00Z'),
  ('80350000-0000-4000-8000-000000000004', '70350000-0000-4000-8000-000000000001', 'homework', 'H2', '2026-09-20T01:00:00Z'),
  ('80350000-0000-4000-8000-000000000005', '70350000-0000-4000-8000-000000000001', 'homework', 'HK', '2026-09-20T01:00:00Z'),
  ('80350000-0000-4000-8000-000000000006', '70350000-0000-4000-8000-000000000001', 'homework', 'HN', '2026-09-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, reward_tokens) values
  ('80350000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z', 2),
  ('80350000-0000-4000-8000-000000000002', 10, '2026-04-30T13:00:00Z', 2),
  ('80350000-0000-4000-8000-000000000003', 10, '2026-09-30T13:00:00Z', 0),
  ('80350000-0000-4000-8000-000000000004', 10, '2026-09-30T13:00:00Z', 1),
  ('80350000-0000-4000-8000-000000000005', 10, '2026-09-30T13:00:00Z', 1),
  ('80350000-0000-4000-8000-000000000006', 10, '2026-09-30T13:00:00Z', 3);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, first_after_solution) values
  ('50350000-0000-4000-8000-000000000001', '80350000-0000-4000-8000-000000000001', '60350000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000002', '80350000-0000-4000-8000-000000000001', '60350000-0000-4000-8000-000000000002', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000003', '80350000-0000-4000-8000-000000000001', '60350000-0000-4000-8000-000000000003', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', true),
  ('50350000-0000-4000-8000-000000000004', '80350000-0000-4000-8000-000000000001', '60350000-0000-4000-8000-000000000004', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000005', '80350000-0000-4000-8000-000000000001', '60350000-0000-4000-8000-000000000005', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000006', '80350000-0000-4000-8000-000000000002', '60350000-0000-4000-8000-000000000001', '2026-04-29T01:00:00Z', '2026-04-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000007', '80350000-0000-4000-8000-000000000003', '60350000-0000-4000-8000-000000000002', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000008', '80350000-0000-4000-8000-000000000006', '60350000-0000-4000-8000-000000000006', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000009', '80350000-0000-4000-8000-000000000005', '60350000-0000-4000-8000-000000000006', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false),
  ('50350000-0000-4000-8000-000000000010', '80350000-0000-4000-8000-000000000004', '60350000-0000-4000-8000-000000000003', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- ตรวจด้วย request key ใหม่ (ไฟล์รุ่น 1) ตามรุ่นผลตรวจที่มีตอนนี้
create function pg_temp.g(p_sub text, p_raw integer, p_pass boolean) returns jsonb language sql as $$
  select public.grade_submission(p_sub::uuid, p_raw, p_pass, null, null, 1,
           coalesce((select g.version from public.grades g where g.submission_id = p_sub::uuid), 0), gen_random_uuid())
$$;
grant execute on function pg_temp.g(text, integer, boolean) to authenticated;
-- ผลด้านรางวัลของคำตอบ: [reward_tokens_granted, wallet_balance, reward_granted]
create function pg_temp.rw(p jsonb) returns jsonb language sql immutable as
  $$ select jsonb_build_array(p -> 'reward_tokens_granted', p -> 'wallet_balance', p -> 'reward_granted') $$;
grant execute on function pg_temp.rw(jsonb) to authenticated;
-- ยอดในเทอม T1 ของนักเรียน n (ไม่มีแถว = null)
create function pg_temp.bal(n integer) returns integer language sql stable as $$
  select w.balance from public.wallets w
   where w.student_id = ('60350000-0000-4000-8000-00000000000' || n)::uuid and w.term_id = '40350000-0000-4000-8000-000000000001'
$$;
grant execute on function pg_temp.bal(integer) to authenticated;

set local role authenticated;
select pg_temp.as_user('20350000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- ก: ให้ครั้งเดียว — ตรวจซ้ำ, คำขอซ้ำ, ผ่าน→ไม่ผ่าน→ผ่าน (I3)
-- ---------------------------------------------------------------------------
insert into res values ('s1', public.grade_submission('50350000-0000-4000-8000-000000000001', 9, true, null, null, 1, 0,
                                                      'c0350000-0000-4000-8000-000000000001'));
select is(pg_temp.rw(pg_temp.r('s1')), '[2, 2, true]'::jsonb, 'ส่งทัน + ผ่าน: ได้โทเคนตามงาน (2) ยอดเป็น 2');
select is((select jsonb_build_array(w.balance, w.version) from public.wallets w
            where w.student_id = '60350000-0000-4000-8000-000000000001' and w.term_id = '40350000-0000-4000-8000-000000000001'),
  '[2, 1]'::jsonb, 'สร้างแถวกระเป๋าของเทอมปัจจุบันเมื่อได้โทเคนครั้งแรก');
select is((select jsonb_build_array(s.reward_granted, s.reward_effect_seen) from public.submissions s
            where s.id = '50350000-0000-4000-8000-000000000001'),
  '[true, false]'::jsonb, 'reward_granted = true และเอฟเฟกต์ค้างไว้ให้นักเรียนดู (ไม่มีแจ้งเตือน)');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000001', 10, true)), '[0, null, true]'::jsonb,
  'ตรวจซ้ำ (ผ่านอีก) ไม่ได้ซ้ำ');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000001', 10, false)), '[0, null, true]'::jsonb,
  'I3: ผ่าน → ไม่ผ่าน ไม่ถอนโทเคน');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000001', 10, true)), '[0, null, true]'::jsonb,
  'ผ่าน → ไม่ผ่าน → ผ่าน ไม่ได้ซ้ำ');
select is(public.grade_submission('50350000-0000-4000-8000-000000000001', 9, true, null, null, 1, 0,
                                  'c0350000-0000-4000-8000-000000000001'), pg_temp.r('s1'),
  'คำขอซ้ำด้วย request key เดิมคืนผลเดิม');
select is(pg_temp.bal(1), 2, 'หลังตรวจซ้ำ/ไม่ผ่าน/คำขอซ้ำ ยอดยังเป็น 2');

-- ไม่ผ่านก่อนแล้วค่อยผ่าน: ได้ตอนผ่าน
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000004', 8, false)), '[0, null, false]'::jsonb,
  'ไม่ผ่าน: ยังไม่ให้');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000004', 8, true)), '[2, 2, true]'::jsonb,
  'ไม่ผ่าน → ผ่าน: ได้ตอนผ่าน');

-- ---------------------------------------------------------------------------
-- ข: ไม่เข้าเกณฑ์ — สาย, ส่งแรกหลังเฉลย, งาน 0 โทเคน, งานเทอมเก่า (I5)
-- ---------------------------------------------------------------------------
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000002', 10, true)) || coalesce(to_jsonb(pg_temp.bal(2)), 'null'),
  '[0, null, false, null]'::jsonb, 'ส่งช้า: ไม่ได้โทเคน ไม่มีแถวกระเป๋า');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000003', 10, true)), '[0, null, false]'::jsonb,
  'ส่งแรกหลังเฉลย (สายเสมอ): ไม่ได้โทเคน');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000007', 10, true)), '[0, null, false]'::jsonb,
  'งาน 0 โทเคน: ไม่ตั้ง reward_granted (ไม่มีเอฟเฟกต์)');
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000006', 10, true))
          || to_jsonb((select count(*)::integer from public.wallets w where w.term_id = '40350000-0000-4000-8000-000000000002'))
          || to_jsonb(pg_temp.bal(1)),
  '[0, null, false, 0, 2]'::jsonb, 'I5: งานเทอมเก่าไม่ให้โทเคนเข้าเทอมใหม่ (และไม่สร้างกระเป๋าเทอมเก่า)');

-- ---------------------------------------------------------------------------
-- ค: K5 — จบภาคเรียนแล้ว (ยังไม่เปิดเทอมใหม่) งานเข้าเกณฑ์ยังได้โทเคน
-- ---------------------------------------------------------------------------
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000010', 7, true)), '[1, 1, true]'::jsonb,
  'K5: จบภาคเรียนแล้วครูตรวจผ่าน งานทันยังได้โทเคน');
set local role postgres;
update public.term_control set status = 'active', ended_at = null where singleton;
set local role authenticated;

-- ---------------------------------------------------------------------------
-- ง: N3 — เลื่อนกำหนดส่งสองทิศ
-- ---------------------------------------------------------------------------
-- ขยาย: S5 (ยังไม่ตรวจ) สาย → ทัน แล้วตรวจผ่านได้โทเคน
insert into res values ('due_later', public.change_due('80350000-0000-4000-8000-000000000001', '2026-10-02T13:00:00Z',
  '{50350000-0000-4000-8000-000000000005}', '{}', gen_random_uuid()));
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000005', 9, true)), '[2, 2, true]'::jsonb,
  'N3: ขยายกำหนดจนงานที่ยังไม่ตรวจกลายเป็นทัน → ตรวจผ่านได้โทเคน');
-- เร็วขึ้น: ทุกคนตรวจแล้ว (ไม่มีรายชื่อที่เปลี่ยน) โทเคนที่ให้แล้วคงอยู่; ตรวจใหม่ตอนนับเป็นสายไม่ถอน
insert into res values ('due_earlier', public.change_due('80350000-0000-4000-8000-000000000001', '2026-09-28T13:00:00Z',
  '{}', '{}', gen_random_uuid()));
select is(jsonb_build_array(pg_temp.bal(1), pg_temp.bal(4), pg_temp.bal(5)), '[2, 2, 2]'::jsonb,
  'N3: เลื่อนกำหนดเร็วขึ้นแล้วงานที่ตรวจแล้วคงโทเคน');
insert into res values ('s1_late', pg_temp.g('50350000-0000-4000-8000-000000000001', 9, true));
select is(pg_temp.rw(pg_temp.r('s1_late')) || (pg_temp.r('s1_late') -> 'timing') || to_jsonb(pg_temp.bal(1)),
  '[0, null, true, "late", 2]'::jsonb, 'N3: ตรวจใหม่หลังกลายเป็นสาย ไม่ถอนโทเคน');

-- ---------------------------------------------------------------------------
-- จ: K4 — แก้เฉลยหลังเผยแพร่ โทเคนไม่เปลี่ยน
-- ---------------------------------------------------------------------------
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000009', 10, true)), '[1, 1, true]'::jsonb,
  'ตรวจผ่านก่อนเผยแพร่เฉลย: ได้โทเคน');
insert into res values ('k4_close', public.close_assignment('80350000-0000-4000-8000-000000000005', null, gen_random_uuid()));
insert into res values ('k4_save', public.save_solution('80350000-0000-4000-8000-000000000005', 'เฉลยข้อ 1', null, 0, gen_random_uuid()));
insert into res values ('k4_pub', public.publish_solution('80350000-0000-4000-8000-000000000005',
  (select s.version from public.solutions s where s.assignment_id = '80350000-0000-4000-8000-000000000005'), gen_random_uuid()));
insert into res values ('k4_edit', public.save_solution('80350000-0000-4000-8000-000000000005', 'เฉลยข้อ 1 (แก้)', null,
  (select s.version from public.solutions s where s.assignment_id = '80350000-0000-4000-8000-000000000005'), gen_random_uuid()));
select is(jsonb_build_array(pg_temp.r('k4_edit') ->> 'body', pg_temp.bal(6),
            (select s.reward_granted from public.submissions s where s.id = '50350000-0000-4000-8000-000000000009')),
  '["เฉลยข้อ 1 (แก้)", 1, true]'::jsonb, 'K4: เผยแพร่แล้วแก้เฉลย โทเคนและ reward_granted ไม่เปลี่ยน');

-- ---------------------------------------------------------------------------
-- ฉ: N4 — ลบการบ้านที่ให้โทเคนไปแล้ว ยอดคงเดิม
-- ---------------------------------------------------------------------------
select is(pg_temp.rw(pg_temp.g('50350000-0000-4000-8000-000000000008', 10, true)), '[3, 4, true]'::jsonb,
  'ตรวจผ่านงานที่จะลบ: ได้ 3 โทเคน (ยอดรวม 4)');
insert into res values ('n4', public.delete_post('80350000-0000-4000-8000-000000000006',
  '{"submissions": 1, "grades": 1, "comments": 0, "files": 0}', gen_random_uuid()));
select is(jsonb_build_array(pg_temp.bal(6),
            (select count(*)::integer from public.submissions s where s.id = '50350000-0000-4000-8000-000000000008')),
  '[4, 0]'::jsonb, 'N4: ลบงานแล้วงานส่งหายแต่ยอดโทเคนคงเดิม');

-- ---------------------------------------------------------------------------
-- ช: ภาพรวม
-- ---------------------------------------------------------------------------
select is((select sum(w.balance)::integer from public.wallets w where w.term_id = '40350000-0000-4000-8000-000000000001'
            and w.student_id::text like '60350000-%'),
  11, 'ยอดรวมเทอม T1 = 2 (N1) + 1 (N3) + 2 (N4) + 2 (N5) + 4 (N6)');
set local role postgres;
select is(
  (select array_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosrc ~* 'public\.wallets'),
  array['grade_submission(uuid,integer,boolean,integer,text,integer,integer,uuid,boolean)'],
  'มีแค่ grade_submission ที่แตะ wallets (เปลี่ยนกำหนด/เฉลย/ลบงานไม่แตะ) — RPC ใหม่ที่เขียนยอดต้องเพิ่มที่นี่');

select * from finish();
rollback;
