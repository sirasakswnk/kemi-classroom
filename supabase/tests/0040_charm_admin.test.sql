-- ทดสอบ 0040_charm_admin: ชุดอัปโหลดรูปเครื่องราง, สิทธิ์ขอลิงก์รูป, แคตตาล็อก/อัตรา/เพิ่ม-แก้เครื่องราง (T06)
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

select plan(34);

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ครู T · นักเรียน A (มี X แสดงข้างชื่อ), B (ห้องเดียวกับ A ไม่มีอะไร), C (อีกห้อง ไม่มีอะไร)
-- เครื่องราง X (รูป I1), Y (รูป I2 ไม่มีใครมี) · รูปที่ยังไม่ผูก: I3, I4 (ของ T), I5 (purpose post), I6 (ของบัญชีอื่น)
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40400000-0000-4000-8000-000000000001', 'ภาคทดสอบ T06', 'active');
insert into public.term_control (term_id) values ('40400000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.rarities (id, name, weight) values (1, 'ทั่วไป', 60), (2, 'หายาก', 25), (3, 'พิเศษ', 10), (4, 'ตำนาน', 5)
on conflict (id) do update set weight = excluded.weight;
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('9e400000-0000-4000-8000-00000000000a', 1, 'ชิ้น X ทดสอบ', '', 'X', 9951),
  ('9e400000-0000-4000-8000-00000000000b', 2, 'ชิ้น Y ทดสอบ', '', 'Y', 9952);
insert into public.teachers (id, display_name) values ('10400000-0000-4000-8000-000000000001', 'ครู T06');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30400000-0000-4000-8000-000000000001', '20400000-0000-4000-8000-000000000001', 'google', 'ca-t', 't40@example.com', 'teacher', '10400000-0000-4000-8000-000000000001'),
  ('30400000-0000-4000-8000-00000000000a', '20400000-0000-4000-8000-00000000000a', 'google', 'ca-a', 'a40@example.com', 'student', null),
  ('30400000-0000-4000-8000-00000000000b', '20400000-0000-4000-8000-00000000000b', 'google', 'ca-b', 'b40@example.com', 'student', null),
  ('30400000-0000-4000-8000-00000000000c', '20400000-0000-4000-8000-00000000000c', 'google', 'ca-c', 'c40@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60400000-0000-4000-8000-00000000000a', '940000000001', 'ก T06', '30400000-0000-4000-8000-00000000000a'),
  ('60400000-0000-4000-8000-00000000000b', '940000000002', 'ข T06', '30400000-0000-4000-8000-00000000000b'),
  ('60400000-0000-4000-8000-00000000000c', '940000000003', 'ค T06', '30400000-0000-4000-8000-00000000000c');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70400000-0000-4000-8000-000000000001', '40400000-0000-4000-8000-000000000001', '10400000-0000-4000-8000-000000000001', 'ห้อง T06 หนึ่ง', 'QQQQ42'),
  ('70400000-0000-4000-8000-000000000002', '40400000-0000-4000-8000-000000000001', '10400000-0000-4000-8000-000000000001', 'ห้อง T06 สอง', 'QQQQ43');
insert into public.memberships (classroom_id, student_id) values
  ('70400000-0000-4000-8000-000000000001', '60400000-0000-4000-8000-00000000000a'),
  ('70400000-0000-4000-8000-000000000001', '60400000-0000-4000-8000-00000000000b'),
  ('70400000-0000-4000-8000-000000000002', '60400000-0000-4000-8000-00000000000c');
insert into public.owned_charms (student_id, charm_id)
  values ('60400000-0000-4000-8000-00000000000a', '9e400000-0000-4000-8000-00000000000a');
insert into public.student_equipment (student_id, charm_id)
  values ('60400000-0000-4000-8000-00000000000a', '9e400000-0000-4000-8000-00000000000a');
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
select ('a4000000-0000-4000-8000-00000000000' || n)::uuid,
       case when n = 6 then '30400000-0000-4000-8000-00000000000a' else '30400000-0000-4000-8000-000000000001' end::uuid,
       case when n = 5 then 'post' else 'charm' end, 'staging/t40/0' || n, 'sv-' || n, 'files/t40/0' || n || '.png',
       'image/png', 1000 + n, 'รูป ' || n || '.png'
  from generate_series(1, 6) n;
update public.assets set status = 'ready', version_id = 'v-' || right(id::text, 1), checksum = 'etag', ready_at = clock_timestamp()
 where id::text like 'a4000000-%';
insert into public.attachments (asset_id, charm_id, position) values
  ('a4000000-0000-4000-8000-000000000001', '9e400000-0000-4000-8000-00000000000a', 1),
  ('a4000000-0000-4000-8000-000000000002', '9e400000-0000-4000-8000-00000000000b', 1);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.i(n integer) returns uuid language sql immutable as
  $$ select ('a4000000-0000-4000-8000-00000000000' || n)::uuid $$;
grant execute on function pg_temp.i(integer) to authenticated;
create function pg_temp.png(n integer) returns jsonb language sql immutable as
  $$ select jsonb_build_object('file_name', 'รูป' || n || '.png', 'content_type', 'image/png', 'size_bytes', 1000 + n) $$;
grant execute on function pg_temp.png(integer) to authenticated;
-- อ่านในนาม postgres
create function pg_temp.asset_status(p uuid) returns text language sql stable security definer as
  $$ select status from public.assets where id = p $$;
grant execute on function pg_temp.asset_status(uuid) to authenticated;
create function pg_temp.delete_queued(p uuid) returns boolean language sql stable security definer as
  $$ select exists (select 1 from private.jobs j where j.kind = 'delete_asset' and j.dedupe_key = p::text) $$;
grant execute on function pg_temp.delete_queued(uuid) to authenticated;
create function pg_temp.charm_count() returns integer language sql stable security definer as
  $$ select count(*)::integer from public.charms $$;
grant execute on function pg_temp.charm_count() to authenticated;
create function pg_temp.max_position() returns integer language sql stable security definer as
  $$ select max(position) from public.charms $$;
grant execute on function pg_temp.max_position() to authenticated;
create function pg_temp.weights() returns integer[] language sql stable security definer as
  $$ select array_agg(weight order by id) from public.rarities $$;
grant execute on function pg_temp.weights() to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ก: ชุดอัปโหลดรูปเครื่องราง
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20400000-0000-4000-8000-000000000001');
select is(public.create_upload_batch('charm', null, null, jsonb_build_array(pg_temp.png(1)), gen_random_uuid()) ->> 'purpose',
  'charm', 'ครูขอชุดอัปโหลดรูปเครื่องรางได้ (ไม่มีห้อง)');
select throws_ok($$ select public.create_upload_batch('charm', '70400000-0000-4000-8000-000000000001', null,
                     jsonb_build_array(pg_temp.png(1)), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'รูปเครื่องรางระบุห้องไม่ได้');
select throws_ok($$ select public.create_upload_batch('post', null, null, jsonb_build_array(pg_temp.png(1)), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ไฟล์โพสต์ต้องมีห้องเหมือนเดิม');
select throws_ok($$ select public.create_upload_batch('charm', null, null,
                     jsonb_build_array(pg_temp.png(1), pg_temp.png(2)), gen_random_uuid()) $$,
  'P0001', 'too_many_files', 'รูปเครื่องรางครั้งละ 1 ไฟล์');
select throws_ok($$ select public.create_upload_batch('charm', null, null,
                     '[{"file_name": "ก.pdf", "content_type": "application/pdf", "size_bytes": 100}]', gen_random_uuid()) $$,
  'P0001', 'file_type_not_allowed', 'รูปเครื่องรางรับเฉพาะ JPG/PNG');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.create_upload_batch('charm', null, null, jsonb_build_array(pg_temp.png(1)), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนอัปโหลดรูปเครื่องรางไม่ได้');

-- ---------------------------------------------------------------------------
-- ข: ใครขอลิงก์รูปเครื่องรางได้
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20400000-0000-4000-8000-000000000001');
select is(public.authorize_files(array[pg_temp.i(1), pg_temp.i(2)]), array[pg_temp.i(1), pg_temp.i(2)],
  'ครูขอลิงก์รูปได้ทุกชิ้น');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000a');
select is(public.authorize_files(array[pg_temp.i(1), pg_temp.i(2)]), array[pg_temp.i(1)],
  'นักเรียน A ขอได้เฉพาะรูปชิ้นที่ตัวเองมี');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000b');
select is(public.authorize_files(array[pg_temp.i(1), pg_temp.i(2)]), array[pg_temp.i(1)],
  'นักเรียน B (ห้องเดียวกับ A) ขอได้เฉพาะรูปที่ A เลือกแสดงข้างชื่อ');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000c');
select is(public.authorize_files(array[pg_temp.i(1), pg_temp.i(2)]), '{}'::uuid[],
  'นักเรียน C (คนละห้อง ไม่มีชิ้นใด) ขอไม่ได้เลย');

-- ---------------------------------------------------------------------------
-- ค: แคตตาล็อกและอัตรา
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20400000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.charm_catalog() $$, 'P0001', 'forbidden', 'นักเรียนอ่านแคตตาล็อก T06 ไม่ได้');
select throws_ok($$ select public.save_rarity_weights('[]', 'x') $$, 'P0001', 'forbidden', 'นักเรียนแก้อัตราไม่ได้');
select pg_temp.as_user('20400000-0000-4000-8000-000000000001');
insert into res select 'cat', public.charm_catalog();
select ok((select jsonb_array_length(pg_temp.r('cat') -> 'charms') = pg_temp.charm_count()
              and (select x from jsonb_array_elements(pg_temp.r('cat') -> 'charms') x where x ->> 'id' = '9e400000-0000-4000-8000-00000000000a')
                  @> jsonb_build_object('owners', 1, 'version', 1, 'image_asset_id', pg_temp.i(1))
              and pg_temp.r('cat') -> 'rarities' -> 0 @> '{"id": 1, "weight": 60}'),
  'ครูอ่านแคตตาล็อก: ทุกชิ้น จำนวนผู้มี รุ่น รูป และอัตราตามระดับ');
select throws_ok(format($$ select public.save_rarity_weights(
    '[{"rarity_id": 1, "weight": 60}, {"rarity_id": 2, "weight": 25}, {"rarity_id": 3, "weight": 10}, {"rarity_id": 4, "weight": 4}]', %L) $$,
    pg_temp.r('cat') ->> 'weights_key'),
  'P0001', 'rates_must_total_100', 'อัตรารวม 99 → rates_must_total_100');
select throws_ok(format($$ select public.save_rarity_weights(
    '[{"rarity_id": 1, "weight": 70}, {"rarity_id": 2, "weight": 20}, {"rarity_id": 3, "weight": 10}]', %L) $$,
    pg_temp.r('cat') ->> 'weights_key'),
  'P0001', 'invalid_request', 'ต้องส่งครบทุกระดับ');
select throws_ok(format($$ select public.save_rarity_weights(
    '[{"rarity_id": 1, "weight": 101}, {"rarity_id": 2, "weight": -1}, {"rarity_id": 3, "weight": 0}, {"rarity_id": 4, "weight": 0}]', %L) $$,
    pg_temp.r('cat') ->> 'weights_key'),
  'P0001', 'invalid_request', 'น้ำหนักต้องอยู่ใน 0–100');
select throws_ok($$ select public.save_rarity_weights(
    '[{"rarity_id": 1, "weight": 50}, {"rarity_id": 2, "weight": 30}, {"rarity_id": 3, "weight": 15}, {"rarity_id": 4, "weight": 5}]', 'เก่า') $$,
  'P0001', 'stale_revision', 'อัตราถูกแก้จากหน้าจออื่น → stale_revision');
insert into res select 'w', public.save_rarity_weights(
    '[{"rarity_id": 1, "weight": 50}, {"rarity_id": 2, "weight": 30}, {"rarity_id": 3, "weight": 15}, {"rarity_id": 4, "weight": 5}]',
    pg_temp.r('cat') ->> 'weights_key');
select ok(pg_temp.weights() = array[50, 30, 15, 5] and pg_temp.r('w') ->> 'weights_key' <> pg_temp.r('cat') ->> 'weights_key',
  'บันทึกอัตรา 50/30/15/5 ได้ และรุ่นอัตราเปลี่ยน');

-- ---------------------------------------------------------------------------
-- ง: เพิ่ม/แก้เครื่องราง
-- ---------------------------------------------------------------------------
insert into res select 'k-new', to_jsonb(gen_random_uuid());
insert into res select 'new', public.save_charm('{"name": "ตะเกียงทดสอบ", "description": "ไฟสีฟ้า", "rarity_id": 3}', 0,
                                                 (pg_temp.r('k-new') #>> '{}')::uuid);
select ok(pg_temp.r('new') @> jsonb_build_object('name', 'ตะเกียงทดสอบ', 'symbol', 'ต', 'version', 1, 'owners', 0,
                                                  'position', pg_temp.max_position(), 'image_asset_id', null),
  'เพิ่มเครื่องรางใหม่: ต่อท้ายรายการ รุ่น 1 สัญลักษณ์รูปวาด = ตัวแรกของชื่อ');
select is(public.save_charm('{"name": "ตะเกียงทดสอบ", "description": "ไฟสีฟ้า", "rarity_id": 3}', 0,
                            (pg_temp.r('k-new') #>> '{}')::uuid), pg_temp.r('new'),
  'กดเพิ่มซ้ำด้วย request key เดิม → ผลเดิม ไม่เพิ่มอีกชิ้น');
select throws_ok($$ select public.save_charm('{"name": "ใหม่", "rarity_id": 1}', 1, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'เพิ่มใหม่ต้องส่งรุ่น 0');
select throws_ok($$ select public.save_charm('{"id": "9e400000-0000-4000-8000-00000000000a", "name": "X", "rarity_id": 1}', 7, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'แก้ด้วยรุ่นเก่า → stale_revision');
select throws_ok(format($$ select public.save_charm(%L, 1, gen_random_uuid()) $$,
    jsonb_build_object('id', '9e400000-0000-4000-8000-00000000000a', 'name', repeat('ก', 41), 'rarity_id', 1)),
  'P0001', 'invalid_request', 'ชื่อยาวเกิน 40 ตัว');
select throws_ok(format($$ select public.save_charm(%L, 1, gen_random_uuid()) $$,
    jsonb_build_object('id', '9e400000-0000-4000-8000-00000000000a', 'name', 'X', 'description', repeat('ก', 121), 'rarity_id', 1)),
  'P0001', 'invalid_request', 'คำอธิบายยาวเกิน 120 ตัว');
select throws_ok($$ select public.save_charm('{"id": "9e400000-0000-4000-8000-00000000000a", "name": "X", "rarity_id": 9}', 1, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ระดับที่ไม่มี');
select ok(public.save_charm('{"id": "9e400000-0000-4000-8000-00000000000a", "name": "ชิ้น X แก้แล้ว", "description": "ใหม่", "rarity_id": 2}',
                            1, gen_random_uuid())
            @> jsonb_build_object('name', 'ชิ้น X แก้แล้ว', 'rarity_id', 2, 'version', 2, 'symbol', 'X', 'owners', 1,
                                  'image_asset_id', pg_temp.i(1)),
  'แก้ชื่อ/คำอธิบาย/ระดับ: รหัสเดิม รุ่น +1 คงสัญลักษณ์และรูปเดิม (ไม่ส่ง image_asset_id) ผู้มียังมีอยู่');

-- รูป
select is(public.save_charm(jsonb_build_object('id', pg_temp.r('new') ->> 'id', 'name', 'ตะเกียงทดสอบ', 'rarity_id', 3,
                                               'image_asset_id', pg_temp.i(3)), 1, gen_random_uuid()) ->> 'image_asset_id',
  pg_temp.i(3)::text, 'ใส่รูปที่อัปโหลดแล้วให้ชิ้นใหม่');
insert into res select 'x-img', public.save_charm(jsonb_build_object('id', '9e400000-0000-4000-8000-00000000000a',
    'name', 'ชิ้น X แก้แล้ว', 'rarity_id', 2, 'image_asset_id', pg_temp.i(4)), 2, gen_random_uuid());
-- ตรวจในคำสั่งถัดไป (ฟังก์ชัน stable เห็น snapshot ตอนเริ่มคำสั่ง)
select ok(pg_temp.r('x-img') ->> 'image_asset_id' = pg_temp.i(4)::text
          and pg_temp.asset_status(pg_temp.i(1)) = 'deleting' and pg_temp.delete_queued(pg_temp.i(1)),
  'เปลี่ยนรูป: รูปเดิมเลิกผูก → deleting + เข้าคิวลบ');
select throws_ok(format($$ select public.save_charm(%L, 3, gen_random_uuid()) $$,
    jsonb_build_object('id', '9e400000-0000-4000-8000-00000000000a', 'name', 'X', 'rarity_id', 2, 'image_asset_id', pg_temp.i(5))),
  'P0001', 'invalid_request', 'ไฟล์ purpose อื่นใช้เป็นรูปเครื่องรางไม่ได้');
select throws_ok(format($$ select public.save_charm(%L, 3, gen_random_uuid()) $$,
    jsonb_build_object('id', '9e400000-0000-4000-8000-00000000000a', 'name', 'X', 'rarity_id', 2, 'image_asset_id', pg_temp.i(6))),
  'P0001', 'invalid_request', 'ไฟล์ของบัญชีอื่นใช้ไม่ได้');
insert into res select 'y-img', public.save_charm(
    '{"id": "9e400000-0000-4000-8000-00000000000b", "name": "ชิ้น Y ทดสอบ", "rarity_id": 2, "image_asset_id": null}', 1, gen_random_uuid());
select ok(pg_temp.r('y-img') ->> 'image_asset_id' is null
          and pg_temp.asset_status(pg_temp.i(2)) = 'deleting' and pg_temp.delete_queued(pg_temp.i(2)),
  'เอารูปออก (null) → กลับไปใช้รูปวาด รูปเดิมเข้าคิวลบ');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.save_charm('{"name": "แอบเพิ่ม", "rarity_id": 1}', 0, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนเพิ่มเครื่องรางไม่ได้');

-- ---------------------------------------------------------------------------
-- จ: รูปถึงนักเรียนผ่าน RPC เดิม
-- ---------------------------------------------------------------------------
select is((select x ->> 'image_asset_id' from jsonb_array_elements(public.my_collection() -> 'items') x
            where x ->> 'charm_id' = '9e400000-0000-4000-8000-00000000000a'),
  pg_temp.i(4)::text, 'A: my_collection ส่งรูปใหม่ของชิ้นที่มี');
select pg_temp.as_user('20400000-0000-4000-8000-00000000000b');
select is((select x #>> '{charm,image_asset_id}' from jsonb_array_elements(
             public.classroom_view('70400000-0000-4000-8000-000000000001') -> 'members') x where x ->> 'display_name' = 'ก T06'),
  pg_temp.i(4)::text, 'B: แท็บสมาชิกส่งรูปของชิ้นที่ A เลือกแสดง');

select * from finish();
rollback;
