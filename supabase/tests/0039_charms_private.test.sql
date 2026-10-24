-- ทดสอบ 0039_charms_private: นักเรียนอ่าน charms ตรงไม่ได้ ได้ข้อมูลผ่าน RPC เท่านั้น และชิ้นที่ยังไม่มีไม่หลุดผ่าน RPC ใด
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

select plan(12);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ห้องเดียว สมาชิก A (มีชิ้นเปิด แสดงข้างชื่อ, ยอด 3) และ B (ไม่มีอะไร ยอด 1); ชิ้นลับไม่มีใครได้
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40390000-0000-4000-8000-000000000001', 'ภาคทดสอบปิดแคตตาล็อก', 'active');
insert into public.term_control (term_id) values ('40390000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.rarities (id, name, weight) values (1, 'ทั่วไป', 60), (2, 'หายาก', 25), (3, 'พิเศษ', 10), (4, 'ตำนาน', 5)
on conflict (id) do update set weight = excluded.weight;
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('9e390000-0000-4000-8000-000000000001', 1, 'ชิ้นเปิดทดสอบ', 'คำอธิบายเปิด', 'P1', 9901),
  ('9e390000-0000-4000-8000-000000000002', 4, 'ชิ้นลับปิดแคตตาล็อก', 'คำอธิบายลับปิดแคตตาล็อก', 'ZQ', 9902);
insert into public.teachers (id, display_name) values ('10390000-0000-4000-8000-000000000001', 'ครูปิดแคตตาล็อก');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30390000-0000-4000-8000-000000000001', '20390000-0000-4000-8000-000000000001', 'google', 'cp-t', 't39@example.com', 'teacher', '10390000-0000-4000-8000-000000000001'),
  ('30390000-0000-4000-8000-00000000000a', '20390000-0000-4000-8000-00000000000a', 'google', 'cp-a', 'a39@example.com', 'student', null),
  ('30390000-0000-4000-8000-00000000000b', '20390000-0000-4000-8000-00000000000b', 'google', 'cp-b', 'b39@example.com', 'student', null),
  ('30390000-0000-4000-8000-000000000009', '20390000-0000-4000-8000-000000000009', 'google', 'cp-u', 'u39@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60390000-0000-4000-8000-00000000000a', '939000000001', 'ก ปิดแคตตาล็อก', '30390000-0000-4000-8000-00000000000a'),
  ('60390000-0000-4000-8000-00000000000b', '939000000002', 'ข ปิดแคตตาล็อก', '30390000-0000-4000-8000-00000000000b');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70390000-0000-4000-8000-000000000001', '40390000-0000-4000-8000-000000000001', '10390000-0000-4000-8000-000000000001', 'ห้องปิดแคตตาล็อก', 'QQQQ39');
insert into public.memberships (classroom_id, student_id) values
  ('70390000-0000-4000-8000-000000000001', '60390000-0000-4000-8000-00000000000a'),
  ('70390000-0000-4000-8000-000000000001', '60390000-0000-4000-8000-00000000000b');
insert into public.owned_charms (student_id, charm_id)
  values ('60390000-0000-4000-8000-00000000000a', '9e390000-0000-4000-8000-000000000001');
insert into public.student_equipment (student_id, charm_id)
  values ('60390000-0000-4000-8000-00000000000a', '9e390000-0000-4000-8000-000000000001');
insert into public.wallets (student_id, term_id, balance) values
  ('60390000-0000-4000-8000-00000000000a', '40390000-0000-4000-8000-000000000001', 3),
  ('60390000-0000-4000-8000-00000000000b', '40390000-0000-4000-8000-000000000001', 1);

create temp table catalog_size on commit drop as select count(*)::integer as n from public.charms;
grant select on catalog_size to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- ผลของทุก RPC ที่นักเรียนเรียกได้และเกี่ยวกับเครื่องราง รวมเป็นข้อความเดียว
create function pg_temp.student_rpcs() returns text language sql as $$
  select concat_ws(' | ', public.my_collection()::text, public.get_draw_options()::text,
                   public.classroom_view('70390000-0000-4000-8000-000000000001')::text, public.reward_effects()::text)
$$;
grant execute on function pg_temp.student_rpcs() to authenticated;

select ok(not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'charms'
                       and policyname = 'charms_select_all'),
  'ไม่มี policy เปิดอ่าน charms ทุกคนแล้ว');
select is((select array_agg(policyname::text) from pg_policies where schemaname = 'public' and tablename = 'charms'),
  array['charms_select_staff'], 'charms มี policy อ่านของครู/ผู้ดูแลเท่านั้น');

set local role authenticated;

-- ---------------------------------------------------------------------------
-- อ่านตรง
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20390000-0000-4000-8000-00000000000a');
select is((select count(*)::integer from public.charms), 0, 'นักเรียน A select charms ได้ 0 แถว (แม้ชิ้นที่ตัวเองมี)');
select is((select count(c.id)::integer from public.owned_charms o left join public.charms c on c.id = o.charm_id), 0,
  'นักเรียน A ต่อ owned_charms → charms ไม่ได้รายละเอียด (embed ผ่าน RLS ได้ null)');
select pg_temp.as_user('20390000-0000-4000-8000-00000000000b');
select is((select count(*)::integer from public.charms), 0, 'นักเรียน B select charms ได้ 0 แถว');
select pg_temp.as_user('20390000-0000-4000-8000-000000000009');
select is((select count(*)::integer from public.charms), 0, 'บัญชีนักเรียนที่ยังไม่เลือกชื่อ select charms ได้ 0 แถว');
select pg_temp.as_user('20390000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.charms), (select n from catalog_size), 'ครูอ่าน charms ได้ทุกแถว');
reset role;
set local role anon;
select throws_ok($$ select count(*) from public.charms $$, '42501', null, 'anon อ่าน charms ไม่ได้');
reset role;
set local role authenticated;

-- ---------------------------------------------------------------------------
-- ผ่าน RPC: ได้เฉพาะชิ้นที่มี/ชิ้นที่เพื่อนเลือกแสดง — ชิ้นลับไม่หลุด
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20390000-0000-4000-8000-00000000000a');
select ok(pg_temp.student_rpcs() ~ 'ชิ้นเปิดทดสอบ', 'A ยังเห็นชิ้นที่ตัวเองมีผ่าน RPC');
select ok(pg_temp.student_rpcs() !~ 'ชิ้นลับปิดแคตตาล็อก|คำอธิบายลับปิดแคตตาล็อก|ZQ|9e390000-0000-4000-8000-000000000002',
  'A: ชิ้นที่ยังไม่มีไม่หลุดผ่าน my_collection/get_draw_options/classroom_view/reward_effects');
select pg_temp.as_user('20390000-0000-4000-8000-00000000000b');
select ok(pg_temp.student_rpcs() ~ 'ชิ้นเปิดทดสอบ' and pg_temp.student_rpcs() !~ 'คำอธิบายเปิด',
  'B เห็นชิ้นที่ A เลือกแสดงข้างชื่อ (ชื่อ) แต่ไม่เห็นคำอธิบาย');
select ok(pg_temp.student_rpcs() !~ 'ชิ้นลับปิดแคตตาล็อก|คำอธิบายลับปิดแคตตาล็อก|ZQ|9e390000-0000-4000-8000-000000000002',
  'B: ชิ้นที่ยังไม่มีไม่หลุดผ่าน RPC ใด');

select * from finish();
rollback;
