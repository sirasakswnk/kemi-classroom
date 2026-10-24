-- ทดสอบ 0038_collection: ตู้สะสมส่วนตัว (my_collection) และชิ้นที่แสดงข้างชื่อในแท็บสมาชิก (classroom_view)
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

select plan(17);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ห้องเดียว สมาชิก A (มีชิ้นทดสอบ 1 และ 2, แสดงชิ้น 1) และ B (ยังไม่มีอะไร), บัญชี U ยังไม่เลือกชื่อ
-- ชิ้นทดสอบ 3 ไม่มีใครได้ — ชื่อ/สัญลักษณ์/คำอธิบายต้องไม่หลุดไปถึงใคร
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40380000-0000-4000-8000-000000000001', 'ภาคทดสอบตู้', 'active');
insert into public.term_control (term_id) values ('40380000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.rarities (id, name, weight) values (1, 'ทั่วไป', 60), (2, 'หายาก', 25), (3, 'พิเศษ', 10), (4, 'ตำนาน', 5)
on conflict (id) do update set weight = excluded.weight;
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('9e380000-0000-4000-8000-000000000001', 1, 'ชิ้นตู้ทดสอบหนึ่ง', 'คำอธิบายหนึ่ง', 'T1', 9801),
  ('9e380000-0000-4000-8000-000000000002', 2, 'ชิ้นตู้ทดสอบสอง', '', 'T2', 9802),
  ('9e380000-0000-4000-8000-000000000003', 4, 'ชิ้นลับทดสอบ', 'คำอธิบายลับทดสอบ', 'QZ', 9803);
insert into public.teachers (id, display_name) values ('10380000-0000-4000-8000-000000000001', 'ครูตู้');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30380000-0000-4000-8000-000000000001', '20380000-0000-4000-8000-000000000001', 'google', 'col-t', 't38@example.com', 'teacher', '10380000-0000-4000-8000-000000000001'),
  ('30380000-0000-4000-8000-00000000000a', '20380000-0000-4000-8000-00000000000a', 'google', 'col-a', 'a38@example.com', 'student', null),
  ('30380000-0000-4000-8000-00000000000b', '20380000-0000-4000-8000-00000000000b', 'google', 'col-b', 'b38@example.com', 'student', null),
  ('30380000-0000-4000-8000-000000000009', '20380000-0000-4000-8000-000000000009', 'google', 'col-u', 'u38@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60380000-0000-4000-8000-00000000000a', '938000000001', 'ก ตู้ทดสอบ', '30380000-0000-4000-8000-00000000000a'),
  ('60380000-0000-4000-8000-00000000000b', '938000000002', 'ข ตู้ทดสอบ', '30380000-0000-4000-8000-00000000000b');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('40380000-0000-4000-8000-000000000001', '60380000-0000-4000-8000-00000000000a', 'ม.5/1', 1),
  ('40380000-0000-4000-8000-000000000001', '60380000-0000-4000-8000-00000000000b', 'ม.5/1', 2);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70380000-0000-4000-8000-000000000001', '40380000-0000-4000-8000-000000000001', '10380000-0000-4000-8000-000000000001', 'ห้องตู้ทดสอบ', 'QQQQ38');
insert into public.memberships (classroom_id, student_id) values
  ('70380000-0000-4000-8000-000000000001', '60380000-0000-4000-8000-00000000000a'),
  ('70380000-0000-4000-8000-000000000001', '60380000-0000-4000-8000-00000000000b');
insert into public.owned_charms (student_id, charm_id, obtained_at) values
  ('60380000-0000-4000-8000-00000000000a', '9e380000-0000-4000-8000-000000000001', '2026-10-20T03:00:00Z'),
  ('60380000-0000-4000-8000-00000000000a', '9e380000-0000-4000-8000-000000000002', '2026-10-21T03:00:00Z');
insert into public.student_equipment (student_id, charm_id)
  values ('60380000-0000-4000-8000-00000000000a', '9e380000-0000-4000-8000-000000000001');

create temp table catalog_size on commit drop as select count(*)::integer as n from public.charms;
grant select on catalog_size to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- ช่องของชิ้นทดสอบใน my_collection (ตาม position)
create function pg_temp.slot(p jsonb, p_position integer) returns jsonb language sql immutable as
  $$ select x from jsonb_array_elements(p -> 'items') x where (x ->> 'position')::integer = p_position $$;
grant execute on function pg_temp.slot(jsonb, integer) to authenticated;
-- สมาชิกตามชื่อใน classroom_view
create function pg_temp.member(p jsonb, p_name text) returns jsonb language sql immutable as
  $$ select x from jsonb_array_elements(p -> 'members') x where x ->> 'display_name' = p_name $$;
grant execute on function pg_temp.member(jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.my_collection()', 'EXECUTE')
          and has_function_privilege('authenticated', 'public.my_collection()', 'EXECUTE'),
  'my_collection: anon เรียกไม่ได้ authenticated เรียกได้');

set local role authenticated;
select pg_temp.as_user('20380000-0000-4000-8000-000000000001');
select throws_ok($$ select public.my_collection() $$, 'P0001', 'forbidden', 'ครูเรียก my_collection ไม่ได้');
select pg_temp.as_user('20380000-0000-4000-8000-000000000009');
select throws_ok($$ select public.my_collection() $$, 'P0001', 'identity_required',
  'บัญชีที่ยังไม่เลือกชื่อเรียก my_collection ไม่ได้');

-- ---------------------------------------------------------------------------
-- ตู้ของ A
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20380000-0000-4000-8000-00000000000a');
select is(public.my_collection() - 'items',
  jsonb_build_object('total', (select n from catalog_size), 'owned', 2,
                     'equipped_charm_id', '9e380000-0000-4000-8000-000000000001'),
  'A: ทุกช่องในแคตตาล็อก, มี 2 ชิ้น, แสดงชิ้นที่ 1');
select is(jsonb_array_length(public.my_collection() -> 'items'), (select n from catalog_size),
  'A: จำนวนช่อง = จำนวนเครื่องรางทั้งหมด');
select ok((select bool_and(p < p2) from (
             select (x ->> 'position')::integer p, lead((x ->> 'position')::integer) over (order by o) p2
               from jsonb_array_elements(public.my_collection() -> 'items') with ordinality t(x, o)) z
           where p2 is not null),
'A: ช่องเรียงตาม position');
select is(pg_temp.slot(public.my_collection(), 9801),
  '{"position": 9801, "rarity_id": 1, "rarity_name": "ทั่วไป", "owned": true,
    "charm_id": "9e380000-0000-4000-8000-000000000001", "name": "ชิ้นตู้ทดสอบหนึ่ง",
    "description": "คำอธิบายหนึ่ง", "symbol": "T1", "obtained_at": "2026-10-20T03:00:00+00:00",
    "image_asset_id": null}'::jsonb,
  'A: ช่องที่ได้รับแล้วมีชื่อ คำอธิบาย สัญลักษณ์ วันที่ได้รับ');
select is(pg_temp.slot(public.my_collection(), 9803),
  '{"position": 9803, "rarity_id": 4, "rarity_name": "ตำนาน", "owned": false}'::jsonb,
  'A: ช่องที่ยังไม่ได้รับมีแค่ลำดับและระดับ');
select ok(public.my_collection()::text !~ 'ชิ้นลับทดสอบ|คำอธิบายลับทดสอบ|QZ|9e380000-0000-4000-8000-000000000003',
  'A: ชื่อ สัญลักษณ์ คำอธิบาย และรหัสของชิ้นที่ยังไม่ได้รับไม่หลุดมา');

-- ---------------------------------------------------------------------------
-- ตู้ของ B (ยังไม่มีอะไร) และความเป็นส่วนตัวของตู้ A
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20380000-0000-4000-8000-00000000000b');
select is(public.my_collection() - 'items',
  jsonb_build_object('total', (select n from catalog_size), 'owned', 0, 'equipped_charm_id', null),
  'B: ยังไม่มีชิ้นใด ไม่ได้เลือกแสดง');
select ok((select bool_and(not (x ->> 'owned')::boolean and not x ? 'name')
             from jsonb_array_elements(public.my_collection() -> 'items') x),
  'B: ทุกช่องปิดไว้ — ไม่เห็นของในตู้ A');

-- ---------------------------------------------------------------------------
-- แท็บสมาชิก: เพื่อนเห็นเฉพาะชิ้นที่แสดงข้างชื่อ
-- ---------------------------------------------------------------------------
select is(pg_temp.member(public.classroom_view('70380000-0000-4000-8000-000000000001'), 'ก ตู้ทดสอบ'),
  '{"display_name": "ก ตู้ทดสอบ", "roll_number": 1, "is_me": false,
    "charm": {"name": "ชิ้นตู้ทดสอบหนึ่ง", "symbol": "T1", "rarity_id": 1, "image_asset_id": null}}'::jsonb,
  'B เห็นชิ้นที่ A แสดงข้างชื่อ (ชื่อ สัญลักษณ์ ระดับ)');
select is(pg_temp.member(public.classroom_view('70380000-0000-4000-8000-000000000001'), 'ข ตู้ทดสอบ') -> 'charm',
  'null'::jsonb, 'B ไม่ได้เลือกแสดง → charm = null');
select ok(public.classroom_view('70380000-0000-4000-8000-000000000001')::text
            !~ 'ชิ้นตู้ทดสอบสอง|คำอธิบายหนึ่ง|9e380000|2026-10-2',
  'แท็บสมาชิกไม่เปิดตู้: ไม่มีชิ้นอื่นของ A คำอธิบาย รหัส หรือวันที่ได้รับ');

-- A เลือกไม่แสดง → เพื่อนเห็น null; A เลือกชิ้น 2 → เพื่อนเห็นชิ้น 2
select pg_temp.as_user('20380000-0000-4000-8000-00000000000a');
select public.set_equipment(null);
select pg_temp.as_user('20380000-0000-4000-8000-00000000000b');
select is(pg_temp.member(public.classroom_view('70380000-0000-4000-8000-000000000001'), 'ก ตู้ทดสอบ') -> 'charm',
  'null'::jsonb, 'A เลือกไม่แสดง → เพื่อนไม่เห็นเครื่องราง');
select pg_temp.as_user('20380000-0000-4000-8000-00000000000a');
select public.set_equipment('9e380000-0000-4000-8000-000000000002');
select is(public.my_collection() -> 'equipped_charm_id', '"9e380000-0000-4000-8000-000000000002"'::jsonb,
  'A เปลี่ยนชิ้นที่แสดง → my_collection บอกชิ้นใหม่');
select is(pg_temp.member(public.classroom_view('70380000-0000-4000-8000-000000000001'), 'ก ตู้ทดสอบ') #>> '{charm,name}',
  'ชิ้นตู้ทดสอบสอง', 'A เห็นชิ้นที่ตัวเองแสดงในแท็บสมาชิก');

select * from finish();
rollback;
