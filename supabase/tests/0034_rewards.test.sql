-- ทดสอบ 0034_rewards: โครง/สิทธิ์ของ wallets, rarities, charms, owned_charms, student_equipment,
-- seed ระดับ/เครื่องราง 12 ชิ้น (เฉพาะเมื่อมี seed — kemi-dev ใส่ seed แยก), ตัวกัน และ RLS
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

-- ---------------------------------------------------------------------------
-- ก: โครงและสิทธิ์
-- ---------------------------------------------------------------------------
create temp table reward_tables (t regclass primary key) on commit drop;
insert into reward_tables values
  ('public.rarities'), ('public.charms'), ('public.wallets'), ('public.owned_charms'), ('public.student_equipment');

select is_empty(
  $$ select c.relname from pg_class c join reward_tables r on r.t = c.oid where not c.relrowsecurity $$,
  'ตารางกลุ่ม rewards เปิด RLS ทุกตาราง');
select is_empty(
  $$ select tablename || ' ' || cmd from pg_policies
      where schemaname = 'public' and tablename in ('rarities', 'charms', 'wallets', 'owned_charms', 'student_equipment')
        and cmd <> 'SELECT' $$,
  'ไม่มี policy เขียน (เขียนผ่าน RPC เท่านั้น)');
select is_empty(
  $$ select r.t || ' ' || p from reward_tables r,
            unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege('anon', r.t, p) $$,
  'anon ไม่มีสิทธิ์ใด ๆ บนตารางกลุ่ม rewards');
select is_empty(
  $$ select r.t || ' ' || p from reward_tables r,
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege('authenticated', r.t, p) $$,
  'authenticated มีแค่ SELECT');
select is_empty(
  $$ select r || ' ' || f from unnest(array['anon', 'authenticated', 'service_role']) r,
            unnest(array['private.rarities_total_weight()', 'private.charms_guard()', 'private.wallets_guard()',
                         'private.owned_charms_guard()', 'private.submissions_guard()']) f
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันตัวกันใช้ภายในเท่านั้น');
select col_default_is('public', 'submissions', 'reward_effect_seen', 'false', 'submissions.reward_effect_seen เริ่มที่ false');

-- ---------------------------------------------------------------------------
-- ข: seed (ในเครื่องมาจาก db:reset; kemi-dev ใส่ seed แยก — ไม่มีให้ข้าม)
-- ---------------------------------------------------------------------------
select coalesce(
  (select is((select jsonb_agg(jsonb_build_array(r.id, r.name, r.weight) order by r.id) from public.rarities r),
             '[[1, "ทั่วไป", 60], [2, "หายาก", 25], [3, "พิเศษ", 10], [4, "ตำนาน", 5]]'::jsonb,
             'seed: ระดับ 4 ระดับ อัตรา 60/25/10/5')
    where exists (select 1 from public.rarities)),
  skip('ยังไม่มี seed ระดับในฐานข้อมูลนี้', 1));
select coalesce(
  (select is((select jsonb_build_array(
                (select jsonb_agg(n order by rarity_id) from (select rarity_id, count(*)::integer n from public.charms
                                                              where position <= 12 group by rarity_id) x),
                (select jsonb_agg(position order by position) from public.charms where position <= 12),
                (select name from public.charms where position = 12))),
             '[[5, 4, 2, 1], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "พญาเคมี"]'::jsonb,
             'seed: เครื่องราง 12 ชิ้น ทั่วไป 5 · หายาก 4 · พิเศษ 2 · ตำนาน 1 ตามร่าง UX ส่วน 11')
    where exists (select 1 from public.charms)),
  skip('ยังไม่มี seed เครื่องรางในฐานข้อมูลนี้', 1));

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 1, นักเรียน N1 (บัญชี) N2 (บัญชี), การบ้าน 1 งาน N1 ส่งแล้ว, เครื่องรางทดสอบ 2 ชิ้น
-- ---------------------------------------------------------------------------
insert into public.rarities (id, name, weight) values
  (1, 'ทั่วไป', 60), (2, 'หายาก', 25), (3, 'พิเศษ', 10), (4, 'ตำนาน', 5)
on conflict (id) do nothing;
insert into public.terms (id, name, status) values ('4e000000-0000-4000-8000-000000000001', 'ภาคทดสอบรางวัล', 'active');
insert into public.teachers (id, display_name) values ('1e000000-0000-4000-8000-000000000001', 'ครูรางวัล');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e000000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'google', 'rw-1', 't34@example.com', 'teacher', '1e000000-0000-4000-8000-000000000001'),
  ('3e000000-0000-4000-8000-000000000011', '2e000000-0000-4000-8000-000000000011', 'google', 'rw-11', 's34a@example.com', 'student', null),
  ('3e000000-0000-4000-8000-000000000012', '2e000000-0000-4000-8000-000000000012', 'google', 'rw-12', 's34b@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e000000-0000-4000-8000-000000000001', '934000000000341', 'หนึ่ง รางวัล', '3e000000-0000-4000-8000-000000000011'),
  ('6e000000-0000-4000-8000-000000000002', '934000000000342', 'สอง รางวัล', '3e000000-0000-4000-8000-000000000012');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000001', 'เคมีรางวัล', 'ZZZZ34');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8e000000-0000-4000-8000-000000000001', '7e000000-0000-4000-8000-000000000001', 'homework', 'งานรางวัล', '2026-09-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at) values
  ('8e000000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z');
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('9e000000-0000-4000-8000-000000000001', 1, 'ชิ้นทดสอบหนึ่ง', 'คำอธิบายสมมติ', 'T1', 1001),
  ('9e000000-0000-4000-8000-000000000002', 4, 'ชิ้นทดสอบสอง', '', 'T2', 1002);
insert into public.wallets (student_id, term_id, balance) values
  ('6e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', 3),
  ('6e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000001', 1);
insert into public.owned_charms (student_id, charm_id) values
  ('6e000000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001'),
  ('6e000000-0000-4000-8000-000000000002', '9e000000-0000-4000-8000-000000000002');
insert into public.student_equipment (student_id, charm_id) values
  ('6e000000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001'),
  ('6e000000-0000-4000-8000-000000000002', '9e000000-0000-4000-8000-000000000002');

create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;

-- ---------------------------------------------------------------------------
-- ค: ตัวกันและข้อบังคับ
-- ---------------------------------------------------------------------------
-- ผลรวมน้ำหนัก = 100 ตรวจตอนจบ transaction (ทดสอบด้วย set constraints immediate)
create temp table w0 on commit drop as select weight from public.rarities where id = 1;
update public.rarities set weight = case when weight < 100 then weight + 1 else weight - 1 end where id = 1;
select throws_ok($$ set constraints public.rarities_total_weight immediate $$,
  'P0001', 'rates_must_total_100', 'ผลรวมน้ำหนักไม่เท่า 100 → rates_must_total_100 ตอนจบ transaction');
set constraints public.rarities_total_weight deferred;
update public.rarities set weight = (select weight from w0) where id = 1;
select lives_ok($$ set constraints public.rarities_total_weight immediate $$, 'รวม 100 แล้วผ่าน');
set constraints public.rarities_total_weight deferred;
select throws_ok($$ update public.rarities set weight = 101 where id = 1 $$, '23514', null, 'น้ำหนักเกิน 100 ต่อระดับไม่ได้');

select throws_ok($$ update public.charms set description = repeat('ก', 121) where id = '9e000000-0000-4000-8000-000000000001' $$,
  '23514', null, 'คำอธิบายเกิน 120 ตัวไม่ได้');
select lives_ok($$ update public.charms set description = repeat('ก', 120) where id = '9e000000-0000-4000-8000-000000000001' $$,
  'คำอธิบาย 120 ตัวพอดีได้');
select throws_ok($$ update public.charms set symbol = ' ' where id = '9e000000-0000-4000-8000-000000000001' $$,
  '23514', null, 'สัญลักษณ์ว่างไม่ได้');
select throws_ok($$ update public.charms set position = 1002 where id = '9e000000-0000-4000-8000-000000000001' $$,
  '23505', null, 'ลำดับซ้ำไม่ได้');
select throws_ok($$ update public.charms set id = gen_random_uuid() where id = '9e000000-0000-4000-8000-000000000002' $$,
  'P0001', 'immutable_field', 'รหัสเครื่องรางคงที่');
select lives_ok($$ update public.charms set name = 'ชื่อใหม่', rarity_id = 2 where id = '9e000000-0000-4000-8000-000000000002' $$,
  'แก้ชื่อและระดับได้ รหัสเดิม');
select throws_ok($$ delete from public.charms where id = '9e000000-0000-4000-8000-000000000001' $$,
  '23503', null, 'ลบเครื่องรางที่มีคนสะสมแล้วไม่ได้');

select throws_ok($$ update public.wallets set balance = -1 where student_id = '6e000000-0000-4000-8000-000000000002' $$,
  '23514', null, 'ยอดติดลบไม่ได้');
update public.wallets set version = 2 where student_id = '6e000000-0000-4000-8000-000000000002';
select throws_ok($$ update public.wallets set version = 1 where student_id = '6e000000-0000-4000-8000-000000000002' $$,
  'P0001', 'immutable_field', 'รุ่นยอดถอยหลังไม่ได้');

select throws_ok($$ insert into public.owned_charms (student_id, charm_id)
                    values ('6e000000-0000-4000-8000-000000000001', '9e000000-0000-4000-8000-000000000001') $$,
  '23505', null, 'ของซ้ำไม่ได้ (student_id, charm_id)');
select throws_ok($$ update public.owned_charms set obtained_at = clock_timestamp()
                     where student_id = '6e000000-0000-4000-8000-000000000001' $$,
  'P0001', 'immutable_field', 'ของที่ได้แล้วแก้ไม่ได้');
select throws_ok($$ update public.student_equipment set charm_id = '9e000000-0000-4000-8000-000000000002'
                     where student_id = '6e000000-0000-4000-8000-000000000001' $$,
  '23503', null, 'สวมเครื่องรางที่ไม่ได้เป็นเจ้าของไม่ได้');
select lives_ok($$ update public.student_equipment set charm_id = null where student_id = '6e000000-0000-4000-8000-000000000001' $$,
  'ถอดเครื่องราง (ว่าง) ได้');

select throws_ok($$ update public.submissions set reward_effect_seen = true where id = '5e000000-0000-4000-8000-000000000001' $$,
  '23514', null, 'ดูเอฟเฟกต์แล้วได้เฉพาะงานที่ให้รางวัลแล้ว');
select lives_ok($$ update public.submissions set reward_granted = true, reward_effect_seen = true
                    where id = '5e000000-0000-4000-8000-000000000001' $$,
  'ให้รางวัลแล้วตั้งว่าดูเอฟเฟกต์แล้วได้');
select throws_ok($$ update public.submissions set reward_effect_seen = false where id = '5e000000-0000-4000-8000-000000000001' $$,
  'P0001', 'immutable_field', 'ดูเอฟเฟกต์แล้วย้อนกลับไม่ได้ (แสดงครั้งเดียว)');

-- ---------------------------------------------------------------------------
-- ง: RLS — ยอด ตู้ และการสวมเป็นของเจ้าของ (ครูเห็นทั้งหมด); ชุดเครื่องรางทุกคนอ่านได้
-- ---------------------------------------------------------------------------
update public.student_equipment set charm_id = '9e000000-0000-4000-8000-000000000001'
 where student_id = '6e000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.as_user('2e000000-0000-4000-8000-000000000011');
select is((select jsonb_agg(jsonb_build_array(student_id, balance)) from public.wallets),
  '[["6e000000-0000-4000-8000-000000000001", 3]]'::jsonb, 'นักเรียนเห็นยอดของตัวเองเท่านั้น');
select is((select jsonb_agg(charm_id) from public.owned_charms),
  '["9e000000-0000-4000-8000-000000000001"]'::jsonb, 'นักเรียนเห็นตู้ของตัวเองเท่านั้น');
select is((select jsonb_agg(jsonb_build_array(student_id, charm_id)) from public.student_equipment),
  '[["6e000000-0000-4000-8000-000000000001", "9e000000-0000-4000-8000-000000000001"]]'::jsonb,
  'นักเรียนเห็นการสวมของตัวเองเท่านั้น (เพื่อนเห็นผ่าน RPC แท็บสมาชิก)');
select is((select count(*)::integer from public.charms where position > 1000), 2,
  'นักเรียนอ่านชุดเครื่องรางได้ รวมชิ้นที่ยังไม่มี');
select throws_ok($$ insert into public.wallets (student_id, term_id, balance)
                    values ('6e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', 99) $$,
  '42501', null, 'นักเรียนเขียนตารางตรงไม่ได้');
select pg_temp.as_user('2e000000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.wallets where term_id = '4e000000-0000-4000-8000-000000000001'), 2,
  'ครูเห็นยอดของนักเรียนทุกคน');
set local role anon;
select throws_ok($$ select count(*) from public.wallets $$, '42501', null, 'anon อ่านยอดไม่ได้');

select * from finish();
rollback;
