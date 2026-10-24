-- ทดสอบ 0037_draw: สถิติการสุ่ม (gen_random_bytes, น้ำหนักระดับ, ชิ้นในระดับเท่ากัน), อัตราจริง K6,
-- สุ่มไม่ซ้ำ/หักยอด/คำขอซ้ำ/อัตราเปลี่ยน, completed/unavailable ไม่หักยอด, K5 สุ่มได้หลังจบภาคเรียน, สวมใส่
-- (TECHNICAL_DESIGN ส่วน 8) — ข้อมูลสมมติ rollback ตอนจบ (ผู้ใช้กำหนด 19 ต.ค. 2026: ทดสอบสถิติแบบ rollback ทุกครั้ง)
-- ขอบเขตสถิติ = ±5 ส่วนเบี่ยงเบนมาตรฐานของการแจกแจงทวินาม (โอกาสล้มโดยบังเอิญต่อข้อ < 1 ใน 10^5)
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

select plan(49);

-- ---------------------------------------------------------------------------
-- ก: สถิติ (ฟังก์ชันช่วยใน private เรียกในนาม postgres)
-- ---------------------------------------------------------------------------
select throws_ok($$ select private.random_below(0) $$, 'P0001', 'invalid_request', 'random_below(0) ปฏิเสธ');
select is((select count(*) from generate_series(1, 500) where private.random_below(1) <> 0), 0::bigint,
  'random_below(1) = 0 เสมอ');
select is((select count(*) from generate_series(1, 3000) where private.random_below(7) not between 0 and 6), 0::bigint,
  'random_below(7) อยู่ใน 0–6 เสมอ');

-- ลูกเต๋า 6 หน้า 12,000 ครั้ง: แต่ละหน้า 2,000 ± 5σ (σ ≈ 40.8)
create temp table dice on commit drop as
  select private.random_below(6) as v from generate_series(1, 12000);
select is((select count(distinct v) from dice), 6::bigint, 'random_below(6) ออกครบ 6 ค่า');
select ok((select bool_and(abs(n - 2000) <= 204) from (select count(*) n from dice group by v) x),
  'random_below(6) แต่ละค่าออก 2,000 ± 204 ครั้งจาก 12,000 (ไม่เอียง)');

-- ชุดสุ่มสมมติ (รูปแบบเดียวกับ private.draw_pool): ระดับ 60/25/10/5 ของเหลือ 3/2/1/1 ชิ้น
create function pg_temp.pool(p_w integer[], p_ids text[]) returns jsonb language sql immutable as $$
  select jsonb_agg(jsonb_build_object('rarity_id', i, 'name', 'ระดับ ' || i, 'weight', p_w[i], 'total', 3,
                                      'remaining_ids', coalesce(to_jsonb(string_to_array(p_ids[i], ',')), '[]'::jsonb))
                   order by i)
    from generate_series(1, 4) i
$$;
create temp table pick_a on commit drop as
  select private.draw_pick(pg_temp.pool(array[60, 25, 10, 5],
           array['00000000-0000-4000-8000-0000000000a1,00000000-0000-4000-8000-0000000000a2,00000000-0000-4000-8000-0000000000a3',
                 '00000000-0000-4000-8000-0000000000b1,00000000-0000-4000-8000-0000000000b2',
                 '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000d1'])) as id
    from generate_series(1, 20000);
select ok((select count(*) = 20000 and count(id) = 20000 from pick_a), 'draw_pick ได้ผลทุกครั้ง');
-- ระดับ: 12,000 ± 346 / 5,000 ± 306 / 2,000 ± 212 / 1,000 ± 154
select ok((select abs(count(*) filter (where id::text like '%a_') - 12000) <= 346
              and abs(count(*) filter (where id::text like '%b_') - 5000) <= 306
              and abs(count(*) filter (where id::text like '%c1') - 2000) <= 212
              and abs(count(*) filter (where id::text like '%d1') - 1000) <= 154 from pick_a),
  'สัดส่วนระดับตามน้ำหนัก 60/25/10/5 (±5σ จาก 20,000 ครั้ง)');
-- ในระดับเดียวกันโอกาสเท่ากัน (K6): 3 ชิ้นของระดับ 1 ชิ้นละ 4,000 ± 283 และ 2 ชิ้นของระดับ 2 ชิ้นละ 2,500 ± 234
select ok((select bool_and(abs(n - 4000) <= 283) and count(*) = 3
             from (select count(*) n from pick_a where id::text like '%a_' group by id) x)
          and (select bool_and(abs(n - 2500) <= 234) and count(*) = 2
             from (select count(*) n from pick_a where id::text like '%b_' group by id) x),
  'K6: ชิ้นที่ยังไม่มีในระดับเดียวกันโอกาสเท่ากัน');

-- ระดับ 1 สะสมครบ: ตัดออกแล้วปรับตามสัดส่วน 25/40, 10/40, 5/40 → 12,500 ± 342 / 5,000 ± 306 / 2,500 ± 234
create temp table pick_b on commit drop as
  select private.draw_pick(pg_temp.pool(array[60, 25, 10, 5],
           array['', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000c1',
                 '00000000-0000-4000-8000-0000000000d1'])) as id
    from generate_series(1, 20000);
select ok((select count(*) filter (where id::text like '%a_') = 0
              and abs(count(*) filter (where id::text like '%b1') - 12500) <= 342
              and abs(count(*) filter (where id::text like '%c1') - 5000) <= 306
              and abs(count(*) filter (where id::text like '%d1') - 2500) <= 234 from pick_b),
  'ระดับที่ครบถูกตัดออก ส่วนที่เหลือปรับตามสัดส่วน (62.5/25/12.5)');

-- ระดับที่น้ำหนัก 0 ไม่ออกแม้มีของเหลือ; เหลือแต่น้ำหนัก 0 = ไม่มีผล
select is((select count(*) from generate_series(1, 2000)
            where private.draw_pick(pg_temp.pool(array[0, 0, 7, 0],
                    array['00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1',
                          '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000d1']))
                  <> '00000000-0000-4000-8000-0000000000c1'), 0::bigint,
  'ระดับน้ำหนัก 0 ไม่ออก (มีแค่ระดับที่มีน้ำหนักออก)');
select is(private.draw_pick(pg_temp.pool(array[0, 0, 7, 0],
            array['00000000-0000-4000-8000-0000000000a1', '', '', ''])), null,
  'ของที่เหลือน้ำหนัก 0 ทั้งหมด → ไม่มีผล');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: เทอมกระเป๋า T1 + เทอมเก่า T0; อัตรา 60/25/10/5; เพิ่มเครื่องรางทดสอบระดับละ 1 ชิ้น (ทุกระดับมีของ)
-- N1 ยอด 100 (+ ยอดเทอมเก่า 7) · N2 ไม่มีแถวกระเป๋า · N3 ยอด 5 มีครบระดับ 1–2 · N4 ยอด 5 มีครบทุกชิ้น
-- U = บัญชีนักเรียนที่ยังไม่เลือกชื่อ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('40370000-0000-4000-8000-000000000001', 'ภาคทดสอบสุ่ม', 'active');
insert into public.terms (id, name, status, ended_at, superseded_at) values
  ('40370000-0000-4000-8000-000000000002', 'ภาคเก่าทดสอบสุ่ม', 'superseded', '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z');
insert into public.term_control (term_id) values ('40370000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.rarities (id, name, weight) values (1, 'ทั่วไป', 60), (2, 'หายาก', 25), (3, 'พิเศษ', 10), (4, 'ตำนาน', 5)
on conflict (id) do update set weight = excluded.weight;
insert into public.charms (id, rarity_id, name, description, symbol, position) values
  ('9e370000-0000-4000-8000-000000000001', 1, 'ชิ้นสุ่มทดสอบ 1', '', 'D1', 9001),
  ('9e370000-0000-4000-8000-000000000002', 2, 'ชิ้นสุ่มทดสอบ 2', '', 'D2', 9002),
  ('9e370000-0000-4000-8000-000000000003', 3, 'ชิ้นสุ่มทดสอบ 3', '', 'D3', 9003),
  ('9e370000-0000-4000-8000-000000000004', 4, 'ชิ้นสุ่มทดสอบ 4', '', 'D4', 9004);
insert into public.teachers (id, display_name) values ('10370000-0000-4000-8000-000000000001', 'ครูสุ่ม');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30370000-0000-4000-8000-000000000001', '20370000-0000-4000-8000-000000000001', 'google', 'dr-1', 't37@example.com', 'teacher', '10370000-0000-4000-8000-000000000001'),
  ('30370000-0000-4000-8000-000000000009', '20370000-0000-4000-8000-000000000009', 'google', 'dr-9', 'u37@example.com', 'student', null);
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id)
  select ('30370000-0000-4000-8000-00000000001' || n)::uuid, ('20370000-0000-4000-8000-00000000001' || n)::uuid,
         'google', 'dr-1' || n, 's' || n || '-37@example.com', 'student', null
    from generate_series(1, 4) n;
insert into public.students (id, student_code, display_name, account_id)
  select ('60370000-0000-4000-8000-00000000000' || n)::uuid, '9370000000037' || n, 'นักเรียนสุ่ม ' || n,
         ('30370000-0000-4000-8000-00000000001' || n)::uuid
    from generate_series(1, 4) n;
insert into public.wallets (student_id, term_id, balance) values
  ('60370000-0000-4000-8000-000000000001', '40370000-0000-4000-8000-000000000001', 100),
  ('60370000-0000-4000-8000-000000000001', '40370000-0000-4000-8000-000000000002', 7),
  ('60370000-0000-4000-8000-000000000003', '40370000-0000-4000-8000-000000000001', 5),
  ('60370000-0000-4000-8000-000000000004', '40370000-0000-4000-8000-000000000001', 5);
insert into public.owned_charms (student_id, charm_id)
  select '60370000-0000-4000-8000-000000000003', c.id from public.charms c where c.rarity_id in (1, 2);
insert into public.owned_charms (student_id, charm_id)
  select '60370000-0000-4000-8000-000000000004', c.id from public.charms c;

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- นักเรียน n (บัญชี 2037…001n)
create function pg_temp.as_st(n integer) returns void language sql as
  $$ select pg_temp.as_user('20370000-0000-4000-8000-00000000001' || n) $$;
grant execute on function pg_temp.as_st(integer) to authenticated;
create function pg_temp.st(n integer) returns uuid language sql immutable as
  $$ select ('60370000-0000-4000-8000-00000000000' || n)::uuid $$;
grant execute on function pg_temp.st(integer) to authenticated;
-- สุ่มด้วยอัตราที่เพิ่งโหลด (เหมือนหน้าเว็บ) และ request key ใหม่
create function pg_temp.draw() returns jsonb language sql as $$
  select public.draw_charm(public.get_draw_options() ->> 'rates_key', gen_random_uuid())
$$;
grant execute on function pg_temp.draw() to authenticated;
create function pg_temp.pcts(p jsonb) returns jsonb language sql immutable as
  $$ select jsonb_path_query_array(p, '$.levels[*].pct') $$;
grant execute on function pg_temp.pcts(jsonb) to authenticated;
-- ยอด [balance, version] ในเทอมกระเป๋า T1 (ไม่มีแถว = null) — อ่านในนาม postgres
create function pg_temp.w(n integer) returns jsonb language sql stable security definer as $$
  select jsonb_build_array(w.balance, w.version) from public.wallets w
   where w.student_id = pg_temp.st(n) and w.term_id = '40370000-0000-4000-8000-000000000001'
$$;
grant execute on function pg_temp.w(integer) to authenticated;
create function pg_temp.w_old(n integer) returns integer language sql stable security definer as $$
  select w.balance from public.wallets w
   where w.student_id = pg_temp.st(n) and w.term_id = '40370000-0000-4000-8000-000000000002'
$$;
grant execute on function pg_temp.w_old(integer) to authenticated;
create function pg_temp.owned(n integer) returns bigint language sql stable security definer as
  $$ select count(*) from public.owned_charms o where o.student_id = pg_temp.st(n) $$;
grant execute on function pg_temp.owned(integer) to authenticated;
create function pg_temp.catalog() returns integer language sql stable security definer as
  $$ select count(*)::integer from public.charms $$;
grant execute on function pg_temp.catalog() to authenticated;
-- นักเรียนอ่าน charms ตรงไม่ได้ (0039) — เทียบผลสุ่มกับแคตตาล็อกในนาม postgres
create function pg_temp.charm_matches(p jsonb) returns boolean language sql stable security definer as
  $$ select c.name = p #>> '{charm,name}' and r.name = p #>> '{charm,rarity_name}'
       from public.charms c join public.rarities r on r.id = c.rarity_id
      where c.id = (p #>> '{charm,id}')::uuid $$;
grant execute on function pg_temp.charm_matches(jsonb) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ข: สิทธิ์
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20370000-0000-4000-8000-000000000001');
select throws_ok($$ select public.get_draw_options() $$, 'P0001', 'forbidden', 'ครูเรียก get_draw_options ไม่ได้');
select throws_ok($$ select public.draw_charm(md5('x'), gen_random_uuid()) $$, 'P0001', 'forbidden', 'ครูสุ่มไม่ได้');
select throws_ok($$ select public.set_equipment(null) $$, 'P0001', 'forbidden', 'ครูตั้งสวมใส่ไม่ได้');
select pg_temp.as_user('20370000-0000-4000-8000-000000000009');
select throws_ok($$ select public.get_draw_options() $$, 'P0001', 'identity_required',
  'บัญชีนักเรียนที่ยังไม่เลือกชื่อ: identity_required');
select throws_ok($$ select public.draw_charm(md5('x'), gen_random_uuid()) $$, 'P0001', 'identity_required',
  'บัญชีที่ยังไม่เลือกชื่อสุ่มไม่ได้');

-- ---------------------------------------------------------------------------
-- ค: อัตราจริงและสถานะ (K6)
-- ---------------------------------------------------------------------------
select pg_temp.as_st(1);
insert into res values ('o1', public.get_draw_options());
select is(jsonb_build_array(pg_temp.r('o1') -> 'status', pg_temp.r('o1') -> 'balance', pg_temp.r('o1') -> 'owned',
                            (pg_temp.r('o1') ->> 'total')::integer),
  jsonb_build_array('ok', 100, 0, pg_temp.catalog()), 'N1: ok ยอด 100 ยังไม่มีสักชิ้น ชิ้นทั้งหมด = รายการเครื่องราง');
select is(pg_temp.pcts(pg_temp.r('o1')), '[60, 25, 10, 5]'::jsonb, 'N1: ยังไม่มีอะไร → อัตราตั้งต้น 60/25/10/5');
select is(pg_temp.r('o1') -> 'levels' -> 0 -> 'pct_each',
  to_jsonb(round(60.0 / (pg_temp.r('o1') -> 'levels' -> 0 ->> 'remaining')::integer, 2)),
  'N1: โอกาสต่อชิ้นในระดับ = อัตราระดับ / จำนวนที่ยังไม่มี');

select pg_temp.as_st(3);
select is(pg_temp.pcts(public.get_draw_options()), '[0, 0, 66.67, 33.33]'::jsonb,
  'N3 มีครบระดับ 1–2: ตัดออกแล้วปรับ 10:5 → 66.67/33.33');
select is(public.get_draw_options() -> 'levels' -> 0 -> 'remaining', '0'::jsonb, 'N3: ระดับ 1 เหลือ 0');

select pg_temp.as_st(2);
select is(jsonb_build_array(public.get_draw_options() -> 'status', public.get_draw_options() -> 'balance'),
  '["insufficient", 0]'::jsonb, 'N2 ไม่มีแถวกระเป๋า: insufficient ยอด 0');
select pg_temp.as_st(4);
select is(public.get_draw_options() -> 'status', '"completed"'::jsonb, 'N4 มีครบทุกชิ้น: completed (แม้มียอด)');

-- ของที่เหลือของ N3 (ระดับ 3–4) น้ำหนัก 0 ทั้งหมด → unavailable แยกจาก completed
set local role postgres;
update public.rarities set weight = case id when 1 then 50 when 2 then 50 else 0 end;
set local role authenticated;
select pg_temp.as_st(3);
select is(public.get_draw_options() -> 'status', '"unavailable"'::jsonb, 'K6: ของที่เหลือน้ำหนัก 0 ทั้งหมด → unavailable');
select throws_ok($$ select pg_temp.draw() $$, 'P0001', 'draw_unavailable', 'unavailable: สุ่มไม่ได้');
select is(pg_temp.w(3), '[5, 1]'::jsonb, 'unavailable: ไม่หักยอด');
set local role postgres;
update public.rarities set weight = case id when 1 then 60 when 2 then 25 when 3 then 10 else 5 end;
set local role authenticated;

-- ---------------------------------------------------------------------------
-- ง: สุ่ม
-- ---------------------------------------------------------------------------
select pg_temp.as_st(1);
select throws_ok($$ select public.draw_charm(pg_temp.r('o1') ->> 'rates_key', null) $$, 'P0001', 'request_key_required',
  'ไม่มี request key: request_key_required');
select throws_ok($$ select public.draw_charm('not-a-key', gen_random_uuid()) $$, 'P0001', 'invalid_request',
  'rates_key ผิดรูปแบบ: invalid_request');
select throws_ok($$ select public.draw_charm(md5('อัตราเก่า'), gen_random_uuid()) $$, 'P0001', 'stale_revision',
  'rates_key ไม่ตรงชุดล่าสุด: stale_revision (ไม่สุ่มด้วยอัตราที่ไม่ได้แสดง)');
select is(pg_temp.w(1), '[100, 1]'::jsonb, 'stale_revision: ไม่หักยอด');

insert into res values ('k1', to_jsonb(gen_random_uuid()));
insert into res values ('d1', public.draw_charm(pg_temp.r('o1') ->> 'rates_key', (pg_temp.r('k1') #>> '{}')::uuid));
select is(jsonb_build_array(pg_temp.r('d1') -> 'balance', pg_temp.r('d1') -> 'version', pg_temp.w(1), pg_temp.owned(1)),
  '[99, 2, [99, 2], 1]'::jsonb, 'สุ่มสำเร็จ: หัก 1 โทเคน รุ่นยอด +1 ได้ของ 1 ชิ้น');
select ok((select o.charm_id = (pg_temp.r('d1') #>> '{charm,id}')::uuid
             and o.obtained_at = (pg_temp.r('d1') ->> 'obtained_at')::timestamptz
             from public.owned_charms o where o.student_id = pg_temp.st(1)),
  'ผลสุ่มตรงกับแถวที่บันทึก (หน้าเว็บเล่นเอฟเฟกต์จากผลที่บันทึกแล้ว)');
select ok(pg_temp.charm_matches(pg_temp.r('d1')),
  'ผลมีชื่อและระดับของชิ้นที่ได้');
select is(public.draw_charm(pg_temp.r('o1') ->> 'rates_key', (pg_temp.r('k1') #>> '{}')::uuid), pg_temp.r('d1'),
  'คำขอซ้ำ (response หาย): คืนผลเดิม');
select is(jsonb_build_array(pg_temp.w(1), pg_temp.owned(1)), '[[99, 2], 1]'::jsonb, 'คำขอซ้ำไม่หักยอดหรือสุ่มเพิ่ม');
select throws_ok(format($$ select public.draw_charm(%L, %L) $$, public.get_draw_options() ->> 'rates_key', pg_temp.r('k1') #>> '{}'),
  'P0001', 'request_key_conflict', 'request key เดิมกับอัตราชุดอื่น: request_key_conflict');
select throws_ok($$ select public.draw_charm(pg_temp.r('o1') ->> 'rates_key', gen_random_uuid()) $$, 'P0001', 'stale_revision',
  'แท็บที่ยังแสดงอัตราก่อนสุ่ม (ของที่เหลือเปลี่ยน): stale_revision ต้องโหลดอัตราใหม่');

-- สุ่มต่อจนครบ: ไม่มีของซ้ำ หักครั้งละ 1
do $$
begin
  for i in 2 .. pg_temp.catalog() loop
    perform pg_temp.draw();
  end loop;
end
$$;
select is(jsonb_build_array(pg_temp.owned(1), pg_temp.w(1) -> 0),
  jsonb_build_array(pg_temp.catalog(), 100 - pg_temp.catalog()), 'สุ่มจนครบ: ได้ครบทุกชิ้นไม่ซ้ำ หักเท่าจำนวนครั้ง');
select is(public.get_draw_options() -> 'status', '"completed"'::jsonb, 'ครบแล้ว: completed');
select throws_ok($$ select pg_temp.draw() $$, 'P0001', 'draw_completed', 'ครบแล้ว: สุ่มไม่ได้');
select is(pg_temp.w(1) -> 0, to_jsonb(100 - pg_temp.catalog()), 'ครบแล้ว: ไม่หักยอด');

select pg_temp.as_st(2);
select throws_ok($$ select pg_temp.draw() $$, 'P0001', 'insufficient_balance', 'ยอด 0: insufficient_balance');
select is(pg_temp.w(2), null, 'ยอดไม่พอ: ไม่สร้างแถวกระเป๋า');

-- K5: จบภาคเรียนแล้ว (ยังไม่เริ่มเทอมใหม่) นักเรียนสุ่มด้วยยอดที่เหลือได้; N3 ได้เฉพาะระดับ 3–4
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select pg_temp.as_st(3);
insert into res values ('d3', pg_temp.draw());
select ok((pg_temp.r('d3') #>> '{charm,rarity_id}')::integer in (3, 4) and pg_temp.w(3) = '[4, 2]'::jsonb,
  'K5: หลังจบภาคเรียนสุ่มได้ หักยอด และไม่ออกระดับที่สะสมครบแล้ว');
select is(pg_temp.w_old(1), 7, 'ยอดเทอมเก่าไม่ถูกแตะ');

-- ---------------------------------------------------------------------------
-- จ: แสดงข้างชื่อ
-- ---------------------------------------------------------------------------
select pg_temp.as_st(3);
select is(public.set_equipment((pg_temp.r('d3') #>> '{charm,id}')::uuid),
  jsonb_build_object('charm_id', pg_temp.r('d3') #>> '{charm,id}'), 'สวมชิ้นที่มี: สำเร็จ');
select is((select e.charm_id from public.student_equipment e where e.student_id = pg_temp.st(3)),
  (pg_temp.r('d3') #>> '{charm,id}')::uuid, 'บันทึกชิ้นที่แสดงข้างชื่อแล้ว');
select pg_temp.as_st(2);
select throws_ok($$ select public.set_equipment('9e370000-0000-4000-8000-000000000001') $$, 'P0001', 'invalid_request',
  'ชิ้นที่ไม่มี (N2 ยังไม่มีสักชิ้น): invalid_request');
select pg_temp.as_st(3);
select is(public.set_equipment(null) -> 'charm_id', 'null'::jsonb, 'เลือกไม่แสดง (null) ได้');

select * from finish();
rollback;
