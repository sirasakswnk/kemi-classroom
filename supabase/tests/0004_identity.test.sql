-- ทดสอบ 0004_identity: ค้นชื่อตัวเอง (search_roster) และยืนยันตัวตน (claim_identity) — L3
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 777xxxxx; ชื่อที่มีช่องว่างกลางคำมาจาก sample-roster-5-2-FAKE) และ rollback ตอนจบ
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

-- ให้เรียก pgTAP ได้ขณะสลับเป็น anon/authenticated (ย้อนเมื่อ rollback)
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

select plan(54);

-- ---------------------------------------------------------------------------
-- A. โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('private', 'roster_claim_refs', 'มี private.roster_claim_refs');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'private.roster_claim_refs'::regclass),
  'roster_claim_refs เปิด RLS');
select is_empty(
  $$ select f from unnest(array['public.search_roster(text)', 'public.claim_identity(uuid)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon ไม่มี EXECUTE บน search_roster/claim_identity'
);
select ok(
  has_function_privilege('authenticated', 'public.search_roster(text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.claim_identity(uuid)', 'EXECUTE'),
  'authenticated เรียกได้ (ตรวจบัญชีนักเรียนภายใน)'
);
select is_empty(
  $$ select f from unnest(array[
       'private.name_key(text)', 'private.strip_name_prefix(text)', 'private.mask_name(text)',
       'private.rate_limit_hit(uuid,text,integer,interval)', 'private.require_student_account()',
       'private.claimed_result(uuid)']) f
      where has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'authenticated เรียกฟังก์ชันช่วยภายในไม่ได้'
);

-- ---------------------------------------------------------------------------
-- B. ทำชื่อเป็นรูปเดียวกัน และชื่อปิดบางส่วน
-- ---------------------------------------------------------------------------
select is(private.name_key(' อนุชา  อิ นทร์แก้ว '), 'อนุชาอินทร์แก้ว', 'name_key ลบช่องว่างทั้งหมด รวมช่องว่างกลางคำ');
select is(private.name_key(E'สมชาย ใจ​ดี\t'), 'สมชายใจดี', 'name_key ลบ NBSP, zero-width และ tab');
select is(private.name_key(E'นํา'), private.name_key(E'นำ'),
  'name_key ทำสระอำแบบแยก (ํ + า) กับแบบตัวเดียวให้ตรงกัน');
select is(private.name_key(null), '', 'name_key(null) เป็นค่าว่าง');
select is(
  array(select private.strip_name_prefix(x)
          from unnest(array['นายสมชาย', 'นางสาวชนิดา', 'นางนวล', 'เด็กชายต้น', 'ด.ญ.ฝน', 'สมชายนาย'])
               with ordinality u(x, i) order by i),
  array['สมชาย', 'ชนิดา', 'นวล', 'ต้น', 'ฝน', 'สมชายนาย'],
  'strip_name_prefix ตัดเฉพาะคำนำหน้าที่ขึ้นต้น'
);
select is(private.mask_name('อนุชา อิ นทร์แก้ว'), 'อนุ•• อิ•• นท••••',
  'mask_name: แต่ละคำแสดง 2 กลุ่มอักษรแรก + • 2–4 ตัว (สระบน/ล่าง วรรณยุกต์ติดตัวหน้า)');
select is(private.mask_name('นำโชค ทองคำ'), 'นำโ•• ทอ••', 'mask_name: สระอำติดพยัญชนะตัวหน้า');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ภาคเรียน บัญชี รายชื่อ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name) values ('41000000-0000-4000-8000-000000000001', 'ภาคเรียนทดสอบผูกชื่อ');
insert into public.term_control (term_id) values ('41000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id;

insert into public.teachers (id, display_name) values ('11000000-0000-4000-8000-000000000001', 'ครูทดสอบผูกชื่อ');
-- 1, 2 ชิงชื่อเดียวกัน · 3 ทดสอบเพดานค้น · 4 ครู · 5 เจ้าของชื่อที่ผูกแล้ว · 6 ทดสอบเพดานยืนยัน
insert into public.accounts (id, auth_user_id, provider, provider_subject, role, teacher_id) values
  ('31000000-0000-4000-8000-000000000001', '21000000-0000-4000-8000-000000000001', 'google', 'g-id-1', 'student', null),
  ('31000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000002', 'google', 'g-id-2', 'student', null),
  ('31000000-0000-4000-8000-000000000003', '21000000-0000-4000-8000-000000000003', 'google', 'g-id-3', 'student', null),
  ('31000000-0000-4000-8000-000000000004', '21000000-0000-4000-8000-000000000004', 'google', 'g-id-4', 'teacher', '11000000-0000-4000-8000-000000000001'),
  ('31000000-0000-4000-8000-000000000005', '21000000-0000-4000-8000-000000000005', 'google', 'g-id-5', 'student', null),
  ('31000000-0000-4000-8000-000000000006', '21000000-0000-4000-8000-000000000006', 'google', 'g-id-6', 'student', null);

insert into public.students (id, student_code, name_prefix, display_name, account_id) values
  ('61000000-0000-4000-8000-000000000001', '77700001', 'นาย', 'อนุชา อิ นทร์แก้ว', null),
  ('61000000-0000-4000-8000-000000000002', '77700002', 'นางสาว', 'ชนิดา ชัยมงคล', null),
  ('61000000-0000-4000-8000-000000000003', '07770003', 'นาย', 'ปิยะ ศรีทดสอบ', null),
  ('61000000-0000-4000-8000-000000000004', '77700004', 'นางสาว', 'นางนวล ดวงดี', null),
  ('61000000-0000-4000-8000-000000000005', '77700005', 'นาย', 'ธนกร นาคสวัสดิ์', '31000000-0000-4000-8000-000000000005'),
  ('61000000-0000-4000-8000-000000000006', '77700006', 'นาย', 'สมชาย ใจดี', null),
  ('61000000-0000-4000-8000-000000000007', '77700007', 'นาย', 'สมชาย ใจดี', null),
  ('61000000-0000-4000-8000-000000000008', '77700008', 'นาย', 'คนเก่า ไม่อยู่ภาคนี้', null);

insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', 'ม.5/2', 6),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', 'ม.5/2', 5),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000003', 'ม.5/3', 18),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000004', 'ม.5/2', 7),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000005', 'ม.5/1', 8),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000006', 'ม.5/1', 1),
  ('41000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000007', 'ม.5/3', 2);

-- ผลค้นของแต่ละบัญชี (ตรวจภายหลังในนาม postgres)
create temp table res (label text primary key, body jsonb not null);
grant select, insert on res to authenticated;
create function pg_temp.picked(p_label text) returns jsonb language sql as $$
  select coalesce(jsonb_agg(m - 'ref' order by o), '[]'::jsonb)
    from res, jsonb_array_elements(res.body -> 'matches') with ordinality e(m, o)
   where res.label = p_label
$$;

-- ---------------------------------------------------------------------------
-- C. ผู้เรียกที่ไม่ใช่นักเรียน
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select public.search_roster('77700001') $$, '42501', null, 'anon ค้นรายชื่อไม่ได้');
select throws_ok($$ select public.claim_identity(gen_random_uuid()) $$, '42501', null, 'anon ยืนยันตัวตนไม่ได้');

set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000099", "role": "authenticated"}';
select throws_ok($$ select public.search_roster('77700001') $$, 'P0001', 'account_required',
  'ผู้ใช้ที่ยังไม่มีบัญชีในระบบค้นไม่ได้');
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.search_roster('77700001') $$, 'P0001', 'forbidden', 'ครูค้นชื่อเพื่อผูกตัวเองไม่ได้');
select throws_ok($$ select public.claim_identity(gen_random_uuid()) $$, 'P0001', 'forbidden', 'ครูผูกชื่อนักเรียนให้ตัวเองไม่ได้');
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select r.ref from private.roster_claim_refs r $$, '42501', null,
  'นักเรียนอ่านตารางรหัสอ้างอิงตรงไม่ได้');

-- ---------------------------------------------------------------------------
-- D. ค้นแบบตรงทั้งค่า (บัญชี 1 ค้นครบ 10 ครั้ง; ครั้งสุดท้ายเก็บรหัสอ้างอิงไว้ผูกชื่อในส่วน F)
-- ---------------------------------------------------------------------------
insert into res values ('a1_code', public.search_roster('77700001'));
insert into res values ('a1_code_part', public.search_roster('7770000'));
insert into res values ('a1_lead_missing', public.search_roster('7770003'));
insert into res values ('a1_lead', public.search_roster('07770003'));
insert into res values ('a1_prefix', public.search_roster(' นาย อนุชา  อิ นทร์แก้ว '));
insert into res values ('a1_first_only', public.search_roster('อนุชา'));
insert into res values ('a1_partial', public.search_roster('อนุชา อินทร์'));
insert into res values ('a1_dup', public.search_roster('สมชาย ใจดี'));
insert into res values ('a1_bound', public.search_roster('ธนกร นาคสวัสดิ์'));
insert into res values ('a1_nospace', public.search_roster('อนุชา อินทร์แก้ว'));
select throws_ok($$ select public.search_roster('77700002') $$, 'P0001', 'rate_limited',
  'ค้นครั้งที่ 11 ภายใน 10 นาทีถูกปฏิเสธ');

set local role postgres;
select is(pg_temp.picked('a1_code'),
  '[{"masked_name": "อนุ•• อิ•• นท••••", "group_name": "ม.5/2", "roll_number": 6}]'::jsonb,
  'ค้นด้วยเลขประจำตัวเต็ม: คืนชื่อปิดบางส่วน ห้อง และเลขที่');
select is((select array_agg(k order by k) from res, jsonb_object_keys(res.body) k where res.label = 'a1_code'),
  array['bound', 'matches', 'remaining'], 'ผลค้นมีแค่ matches, bound, remaining');
select is(
  (select array_agg(k order by k) from res, jsonb_array_elements(res.body -> 'matches') m, jsonb_object_keys(m) k
    where res.label = 'a1_code'),
  array['group_name', 'masked_name', 'ref', 'roll_number'],
  'แต่ละรายการมีแค่ ref ชื่อปิดบางส่วน ห้อง เลขที่ (ไม่มีเลขประจำตัว ชื่อเต็ม หรือข้อมูลบัญชี)');
select is((select body - 'matches' from res where label = 'a1_code'), '{"bound": false, "remaining": 9}'::jsonb,
  'ค้นครั้งแรกเหลืออีก 9 ครั้ง');
select is((select jsonb_agg(body -> 'matches' order by label) from res where label in ('a1_code_part', 'a1_lead_missing')),
  '[[], []]'::jsonb, 'เลขประจำตัวไม่ครบหรือขาดศูนย์นำหน้าไม่พบ (ไม่ค้นบางส่วน)');
select is(pg_temp.picked('a1_lead'),
  '[{"masked_name": "ปิย•• ศรี••••", "group_name": "ม.5/3", "roll_number": 18}]'::jsonb,
  'เลขประจำตัวที่มีศูนย์นำหน้าตรงทุกตัวพบ');
select is(pg_temp.picked('a1_nospace'), pg_temp.picked('a1_code'),
  'ชื่อจากไฟล์ที่มีช่องว่างกลางคำ (อิ นทร์แก้ว) ค้นด้วยชื่อที่พิมพ์ติดกันได้');
select is(pg_temp.picked('a1_prefix'), pg_temp.picked('a1_code'),
  'คำนำหน้าและช่องว่างหัวท้าย/ซ้ำในคำค้นไม่มีผล');
select is((select jsonb_agg(body -> 'matches' order by label) from res where label in ('a1_first_only', 'a1_partial')),
  '[[], []]'::jsonb, 'ชื่ออย่างเดียวหรือนามสกุลไม่ครบไม่พบ (ไม่ค้นบางส่วน)');
select is(pg_temp.picked('a1_dup'),
  '[{"masked_name": "สม••• ใจ••", "group_name": "ม.5/1", "roll_number": 1},
    {"masked_name": "สม••• ใจ••", "group_name": "ม.5/3", "roll_number": 2}]'::jsonb,
  'ชื่อซ้ำคืนทุกคนที่ยังไม่ผูก เรียงตามห้องและเลขที่');
select is((select body from res where label = 'a1_bound'), '{"matches": [], "bound": true, "remaining": 1}'::jsonb,
  'ชื่อที่ผูกแล้ว: บอกแค่ bound ไม่คืนรายการหรือข้อมูลบัญชี');
select is((select (body ->> 'remaining')::integer from res where label = 'a1_nospace'), 0,
  'ค้นครั้งที่ 10 เหลือ 0');

-- ---------------------------------------------------------------------------
-- E. บัญชี 2: ชื่อขึ้นต้นด้วย “นาง”, เลขไทย, รายชื่อนอกภาคเรียนปัจจุบัน
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000002", "role": "authenticated"}';
insert into res values ('a2_nang', public.search_roster('นางนวล ดวงดี'));
insert into res values ('a2_nang_prefix', public.search_roster('นางสาวนางนวล ดวงดี'));
insert into res values ('a2_thai_digits', public.search_roster('๗๗๗๐๐๐๐๒'));
insert into res values ('a2_old_term', public.search_roster('77700008'));
insert into res values ('a2_s1', public.search_roster('อนุชา อิ นทร์แก้ว'));

set local role postgres;
select is(pg_temp.picked('a2_nang'),
  '[{"masked_name": "นา•••• ดว••", "group_name": "ม.5/2", "roll_number": 7}]'::jsonb,
  'ชื่อที่ขึ้นต้นด้วย “นาง” ไม่ถูกตัดเป็นคำนำหน้าจนค้นไม่พบ');
select is(pg_temp.picked('a2_nang_prefix'), pg_temp.picked('a2_nang'), 'พิมพ์คำนำหน้าติดชื่อ (นางสาวนางนวล) ก็พบ');
select is(pg_temp.picked('a2_thai_digits'),
  '[{"masked_name": "ชนิ•• ชัย••••", "group_name": "ม.5/2", "roll_number": 5}]'::jsonb,
  'เลขประจำตัวที่พิมพ์เป็นเลขไทยพบ');
select is(pg_temp.picked('a2_old_term'), '[]'::jsonb, 'รายชื่อที่ไม่อยู่ในภาคเรียนปัจจุบันไม่พบ');
select is((select count(*) from private.roster_claim_refs r where r.account_id = '31000000-0000-4000-8000-000000000002'),
  1::bigint, 'ค้นใหม่แทนที่รหัสอ้างอิงเดิมของบัญชี');

-- ---------------------------------------------------------------------------
-- F. สองบัญชีชิงชื่อเดียวกัน · ผูกแล้วผูกซ้ำไม่ได้
-- ---------------------------------------------------------------------------
-- รหัสอ้างอิงที่ยังใช้ได้ของบัญชี 1 ไปยังอีกชื่อ (บัญชีที่ผูกแล้วค้นไม่ได้ จึงสร้างตรง)
insert into private.roster_claim_refs (ref, account_id, student_id) values
  ('51000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002');

set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'a1_nospace')),
  '{"status": "claimed", "display_name": "อนุชา อิ นทร์แก้ว", "group_name": "ม.5/2", "roll_number": 6}'::jsonb,
  'บัญชี 1 ยืนยันสำเร็จ ได้ชื่อเต็มหลังผูกแล้วเท่านั้น');

set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'a2_s1')),
  '{"status": "name_taken"}'::jsonb, 'บัญชี 2 ยืนยันชื่อเดียวกันทีหลังได้ name_taken (ไม่บอกว่าบัญชีไหน)');

set local role postgres;
select is((select s.account_id from public.students s where s.id = '61000000-0000-4000-8000-000000000001'),
  '31000000-0000-4000-8000-000000000001'::uuid, 'ชื่อที่ชิงกันผูกกับบัญชีเดียว (บัญชีแรก)');

set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'a1_nospace')),
  '{"status": "claimed", "display_name": "อนุชา อิ นทร์แก้ว", "group_name": "ม.5/2", "roll_number": 6}'::jsonb,
  'ส่งซ้ำด้วยรหัสเดิมหลังผูกสำเร็จได้ผลเดิม');
select throws_ok($$ select public.claim_identity('51000000-0000-4000-8000-000000000001') $$, 'P0001', 'already_bound',
  'บัญชีที่ผูกแล้วผูกชื่ออื่นซ้ำไม่ได้ แม้มีรหัสอ้างอิงที่ยังใช้ได้');
select throws_ok($$ select public.search_roster('77700002') $$, 'P0001', 'already_bound', 'บัญชีที่ผูกแล้วค้นรายชื่อไม่ได้');

set local role postgres;
select is((select s.account_id from public.students s where s.id = '61000000-0000-4000-8000-000000000002'), null::uuid,
  'ชื่อที่บัญชีผูกแล้วพยายามผูกซ้ำยังไม่ถูกผูก');

set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000002", "role": "authenticated"}';
insert into res values ('a2_s2', public.search_roster('ชนิดา ชัยมงคล'));
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'a2_s2')),
  '{"status": "claimed", "display_name": "ชนิดา ชัยมงคล", "group_name": "ม.5/2", "roll_number": 5}'::jsonb,
  'บัญชีที่แพ้การชิงชื่อค้นและผูกชื่อของตัวเองต่อได้');

set local role postgres;
select throws_ok(
  $$ update public.students set account_id = '31000000-0000-4000-8000-000000000002'
      where id = '61000000-0000-4000-8000-000000000004' $$,
  '23505', null, 'ฐานข้อมูลกันบัญชีเดียวผูกสองชื่อ (unique account_id)');

-- ---------------------------------------------------------------------------
-- G. รหัสอ้างอิงหมดอายุ/ของคนอื่น และเพดานยืนยัน 5 ครั้งต่อชั่วโมง (บัญชี 6)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000006", "role": "authenticated"}';
insert into res values ('a6_dup', public.search_roster('สมชาย ใจดี'));

set local role postgres;
update private.roster_claim_refs r set expires_at = clock_timestamp() - interval '1 second'
 where r.ref = (select (body #>> '{matches,0,ref}')::uuid from res where label = 'a6_dup');
insert into private.roster_claim_refs (ref, account_id, student_id) values
  ('51000000-0000-4000-8000-000000000002', '31000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000006');

set local role authenticated;
select is(public.claim_identity((select (body #>> '{matches,0,ref}')::uuid from res where label = 'a6_dup')),
  '{"status": "expired"}'::jsonb, 'รหัสอ้างอิงหมดอายุ: ให้ค้นใหม่');
select is(public.claim_identity('51000000-0000-4000-8000-000000000002'),
  '{"status": "expired"}'::jsonb, 'รหัสอ้างอิงของบัญชีอื่นใช้ไม่ได้');
select is((select jsonb_agg(public.claim_identity(gen_random_uuid())) from generate_series(1, 3)),
  '[{"status": "expired"}, {"status": "expired"}, {"status": "expired"}]'::jsonb, 'รหัสอ้างอิงที่ไม่มีอยู่ใช้ไม่ได้');
select throws_ok($$ select public.claim_identity((select (body #>> '{matches,1,ref}')::uuid from res where label = 'a6_dup')) $$,
  'P0001', 'rate_limited', 'ยืนยันครั้งที่ 6 ภายในชั่วโมงถูกปฏิเสธ แม้รหัสอ้างอิงใช้ได้');

set local role postgres;
update private.rate_limits r set window_start = r.window_start - interval '1 hour'
 where r.account_id = '31000000-0000-4000-8000-000000000006' and r.action = 'claim_identity';

set local role authenticated;
select is(public.claim_identity((select (body #>> '{matches,1,ref}')::uuid from res where label = 'a6_dup')),
  '{"status": "claimed", "display_name": "สมชาย ใจดี", "group_name": "ม.5/3", "roll_number": 2}'::jsonb,
  'พ้น 1 ชั่วโมงแล้วยืนยันได้อีก');

-- ---------------------------------------------------------------------------
-- H. เพดานค้น 10 ครั้งต่อ 10 นาที (บัญชี 3)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "21000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(
  (select array_agg((public.search_roster('ไม่มี คนนี้') ->> 'remaining')::integer order by g) from generate_series(1, 10) g),
  array[9, 8, 7, 6, 5, 4, 3, 2, 1, 0], 'บอกจำนวนครั้งค้นที่เหลือทุกครั้ง');
select throws_ok($$ select public.search_roster('ไม่มี คนนี้') $$, 'P0001', 'rate_limited', 'ครั้งที่ 11 ถูกปฏิเสธ');

set local role postgres;
update private.rate_limits r set window_start = r.window_start - interval '10 minutes'
 where r.account_id = '31000000-0000-4000-8000-000000000003' and r.action = 'search_roster';

set local role authenticated;
select is(public.search_roster('ไม่มี คนนี้'), '{"matches": [], "bound": false, "remaining": 9}'::jsonb,
  'พ้น 10 นาทีแล้วค้นได้อีก');
select is(public.search_roster('   '), '{"matches": [], "bound": false, "remaining": 8}'::jsonb,
  'คำค้นว่างไม่พบอะไร');

set local role postgres;
select * from finish();
rollback;
