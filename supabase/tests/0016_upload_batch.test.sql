-- ทดสอบ 0016_upload_batch: create_upload_batch — สิทธิ์, request key, เพดานไฟล์ (J4–J6), ภาคเรียน, จองพื้นที่,
-- เพดานครั้ง — ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ; ยอดพื้นที่เทียบเป็นส่วนต่าง
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

select plan(43);

select ok(
  has_function_privilege('authenticated', 'public.create_upload_batch(text,uuid,uuid,jsonb,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.create_upload_batch(text,uuid,uuid,jsonb,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.upload_limits()', 'EXECUTE'),
  'create_upload_batch: authenticated เรียกได้ (ตรวจสิทธิ์ภายใน) anon ไม่ได้; upload_limits ใช้ภายใน');

-- ข้อมูลสมมติ
insert into public.terms (id, name, status) values
  ('4e000000-0000-4000-8000-000000000001', 'ภาคทดสอบอัปโหลด', 'active'),
  ('4e000000-0000-4000-8000-000000000002', 'ภาคทดสอบอัปโหลดเก่า', 'superseded');
insert into public.term_control (term_id) values ('4e000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e000000-0000-4000-8000-000000000001', 'ครูทดสอบอัปโหลด'),
  ('1e000000-0000-4000-8000-000000000002', 'ครูทดสอบห้องอื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e000000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'google', 'ub-1', 'teacher16a@example.com', 'teacher', '1e000000-0000-4000-8000-000000000001'),
  ('3e000000-0000-4000-8000-000000000002', '2e000000-0000-4000-8000-000000000002', 'google', 'ub-2', 'teacher16b@example.com', 'teacher', '1e000000-0000-4000-8000-000000000002'),
  ('3e000000-0000-4000-8000-000000000003', '2e000000-0000-4000-8000-000000000003', 'google', 'ub-3', 'admin16@example.com', 'admin', null),
  ('3e000000-0000-4000-8000-000000000004', '2e000000-0000-4000-8000-000000000004', 'google', 'ub-4', 'student16@example.com', 'student', null);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000001', 'เคมีทดสอบอัปโหลด', 'VVVV23'),
  ('7e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000002', '1e000000-0000-4000-8000-000000000001', 'เคมีภาคเก่า', 'VVVV24'),
  ('7e000000-0000-4000-8000-000000000003', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000002', 'เคมีห้องอื่น', 'VVVV25');
insert into public.posts (id, classroom_id, kind, title) values
  ('8e000000-0000-4000-8000-00000000000a', '7e000000-0000-4000-8000-000000000001', 'homework', 'งานมีเฉลย'),
  ('8e000000-0000-4000-8000-00000000000b', '7e000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศ'),
  ('8e000000-0000-4000-8000-00000000000c', '7e000000-0000-4000-8000-000000000002', 'announcement', 'ประกาศภาคเก่า'),
  ('8e000000-0000-4000-8000-00000000000d', '7e000000-0000-4000-8000-000000000003', 'announcement', 'ประกาศห้องอื่น');
insert into public.assignments (post_id, full_score, due_at) values ('8e000000-0000-4000-8000-00000000000a', 10, '2026-11-10 13:00:00+00');
update public.posts set version = 4 where id = '8e000000-0000-4000-8000-00000000000a';

create temp table base on commit drop as select private.storage_used_bytes() as used;
create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.files(p_extra jsonb default '[]') returns jsonb language sql as $$
  select '[{"file_name": "แบบฝึกหัด Kc.pdf", "content_type": "application/pdf", "size_bytes": 640000},
           {"file_name": "รูปโจทย์.jpg", "content_type": "image/jpeg", "size_bytes": 300000}]'::jsonb || p_extra
$$;
create function pg_temp.one(p_type text, p_size bigint, p_name text default 'ไฟล์.pdf') returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('file_name', p_name, 'content_type', p_type, 'size_bytes', p_size))
$$;
grant execute on function pg_temp.files(jsonb), pg_temp.one(text, bigint, text) to authenticated;

set local role anon;
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  '42501', null, 'anon เรียก create_upload_batch ไม่ได้');

-- ---------------------------------------------------------------------------
-- ครูเจ้าของห้อง: ไฟล์โจทย์ของโพสต์ใหม่
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('post', public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), 'b2000000-0000-4000-8000-000000000001'));
select ok((select (body ->> 'reserved_bytes')::bigint = 940000 and body ->> 'purpose' = 'post'
                  and jsonb_array_length(body -> 'files') = 2 from res where label = 'post'),
  'batch ไฟล์โจทย์: จองขนาดรวม 940,000 ไบต์ 2 ไฟล์');
select is_empty($$ select f ->> 'staging_key' from res, jsonb_array_elements(body -> 'files') f
                    where label = 'post'
                      and (f ->> 'staging_key') !~ ('^staging/' || (body ->> 'batch_id') || '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
                      or (f ->> 'staging_key') is null $$,
  'staging key ต่อไฟล์อยู่ใต้ staging/{batch_id}/{uuid}');
select is((select string_agg(f ->> 'file_name' || ':' || (f ->> 'content_type') || ':' || (f ->> 'size_bytes'), ' | ' order by f ->> 'size_bytes' desc)
             from res, jsonb_array_elements(body -> 'files') f where label = 'post'),
  'แบบฝึกหัด Kc.pdf:application/pdf:640000 | รูปโจทย์.jpg:image/jpeg:300000', 'คืนชื่อ ชนิด และขนาดของแต่ละไฟล์');
set local role postgres;
select results_eq(
  $$ select owner_account_id, purpose, classroom_id, post_id, status, reserved_bytes, expires_at between clock_timestamp() + interval '119 minutes' and clock_timestamp() + interval '121 minutes',
            files = (select body -> 'files' from res where label = 'post')
       from public.upload_batches where id = ((select body from res where label = 'post') ->> 'batch_id')::uuid $$,
  $$ values ('3e000000-0000-4000-8000-000000000001'::uuid, 'post', '7e000000-0000-4000-8000-000000000001'::uuid, null::uuid, 'open', 940000::bigint, true, true) $$,
  'บันทึก batch: เจ้าของ วัตถุประสงค์ ห้อง สถานะ open จอง 940,000 หมดอายุใน 2 ชม. และรายการไฟล์ตรงกับที่คืน');
select is(private.storage_used_bytes() - (select used from base), 940000::bigint, 'ยอดพื้นที่รวมส่วนที่จองไว้');
set local role authenticated;

select is(public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), 'b2000000-0000-4000-8000-000000000001'),
  (select body from res where label = 'post'), 'กดซ้ำด้วย request key เดิมได้ batch เดิม (key ไฟล์เดิม)');
set local role postgres;
select is((select count(*)::integer from public.upload_batches where owner_account_id = '3e000000-0000-4000-8000-000000000001'), 1,
  'กดซ้ำไม่สร้าง batch ใหม่และไม่จองเพิ่ม');
set local role authenticated;
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/png', 5000), 'b2000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่รายการไฟล์ต่าง → request_key_conflict');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), null) $$,
  'P0001', 'request_key_required', 'ไม่มี request key ไม่ได้');

-- แก้โพสต์เดิม / ไฟล์เฉลย
insert into res values ('edit', public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-00000000000b', pg_temp.one('image/png', 1000, 'ภาพ.png'), gen_random_uuid()));
insert into res values ('sol', public.create_upload_batch('solution', '7e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-00000000000a', pg_temp.one('application/pdf', 2000, 'เฉลย.pdf'), gen_random_uuid()));
set local role postgres;
select results_eq(
  $$ select purpose, post_id, base_version from public.upload_batches
      where id in (((select body from res where label = 'edit') ->> 'batch_id')::uuid, ((select body from res where label = 'sol') ->> 'batch_id')::uuid)
      order by purpose $$,
  $$ values ('post', '8e000000-0000-4000-8000-00000000000b'::uuid, 1), ('solution', '8e000000-0000-4000-8000-00000000000a'::uuid, 4) $$,
  'batch ของโพสต์เดิม/เฉลยเก็บโพสต์และ version ที่เริ่มแก้');
set local role authenticated;
select throws_ok($$ select public.create_upload_batch('solution', '7e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-00000000000b', pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ไฟล์เฉลยของประกาศไม่ได้ (เฉลยมีเฉพาะงาน)');
select throws_ok($$ select public.create_upload_batch('solution', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ไฟล์เฉลยต้องระบุงาน');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-00000000000d', pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'โพสต์ของห้องอื่นใช้กับห้องนี้ไม่ได้');
select throws_ok($$ select public.create_upload_batch('submission', '7e000000-0000-4000-8000-000000000001', '8e000000-0000-4000-8000-00000000000a', pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'งานส่ง (submission) ยังไม่เปิดในรอบนี้ (P3-07)');
select throws_ok($$ select public.create_upload_batch('charm', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'รูปเครื่องราง (charm) ยังไม่เปิด (ระยะ 5)');

-- ---------------------------------------------------------------------------
-- เพดานไฟล์ J4–J6
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null,
                    (select jsonb_agg(jsonb_build_object('file_name', 'p' || g || '.png', 'content_type', 'image/png', 'size_bytes', 1000)) from generate_series(1, 11) g), gen_random_uuid()) $$,
  'P0001', 'too_many_files', 'เกิน 10 ไฟล์ไม่ได้');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null,
                   (select jsonb_agg(jsonb_build_object('file_name', 'p' || g || '.png', 'content_type', 'image/png', 'size_bytes', 1000)) from generate_series(1, 10) g), gen_random_uuid()) $$,
  '10 ไฟล์พอดีได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/jpeg', 2097153, 'ใหญ่.jpg'), gen_random_uuid()) $$,
  'P0001', 'file_too_large', 'รูปเกิน 2 MB ไม่ได้');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/jpeg', 2097152, 'พอดี.jpg'), gen_random_uuid()) $$,
  'รูป 2 MB พอดีได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('application/pdf', 10485761), gen_random_uuid()) $$,
  'P0001', 'file_too_large', 'PDF เกิน 10 MB ไม่ได้');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('application/pdf', 10485760), gen_random_uuid()) $$,
  'PDF 10 MB พอดีได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null,
                    (select jsonb_agg(jsonb_build_object('file_name', 'p' || g || '.pdf', 'content_type', 'application/pdf', 'size_bytes', 7340032)) from generate_series(1, 3) g), gen_random_uuid()) $$,
  'P0001', 'batch_too_large', 'รวมเกิน 20 MB ต่อชุดไม่ได้ (J6)');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/heic', 1000, 'ภาพ.heic'), gen_random_uuid()) $$,
  'P0001', 'file_type_not_allowed', 'HEIC ดิบไม่รับ (แปลงเป็น JPEG บนเครื่องก่อน — J4)');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('application/pdf', 0), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ไฟล์ขนาด 0 ไม่ได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('application/pdf', 100, '../อื่น/x.pdf'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ชื่อไฟล์มีตัวแบ่งโฟลเดอร์ไม่ได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, '[]', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'รายการไฟล์ว่างไม่ได้');
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null,
                    '[{"file_name": "a.pdf", "content_type": "application/pdf", "size_bytes": 10, "staging_key": "files/x"}]', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'กำหนด key เองไม่ได้ (คีย์ที่ไม่รู้จัก)');

-- ---------------------------------------------------------------------------
-- สิทธิ์และภาคเรียน
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนขอ batch ไฟล์โจทย์ไม่ได้');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นขอ batch ของห้องนี้ไม่ได้');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลที่ไม่ส่ง p_admin_mode ไม่ได้');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid(), true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลขอ batch แทนครูได้');
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000002', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ไฟล์ของโพสต์ใหม่ในห้องภาคก่อนไม่ได้ (โพสต์ใหม่ไม่ได้อยู่แล้ว — K5)');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000002', '8e000000-0000-4000-8000-00000000000c', pg_temp.files(), gen_random_uuid()) $$,
  'ไฟล์ของโพสต์เดิมในห้องภาคก่อนได้ (N2 แก้โพสต์ได้ตลอด)');
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp();
set local role authenticated;
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'จบภาคเรียนแล้วครูยังขอ batch ไฟล์โจทย์/ประกาศได้ (K5 ปิดเฉพาะฝั่งนักเรียน)');
set local role postgres;
update public.term_control set status = 'active', ended_at = null;

-- ---------------------------------------------------------------------------
-- พื้นที่เต็ม (J10.2) และเพดานครั้ง
-- ---------------------------------------------------------------------------
update public.storage_settings set quota_bytes = private.storage_used_bytes() + hard_stop_margin_bytes + 500000;
set local role authenticated;
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'storage_full', 'จองเกิน quota − margin → storage_full');
select lives_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/png', 500000, 'พอดี.png'), gen_random_uuid()) $$,
  'จองพอดีพื้นที่ที่เหลือได้');
set local role postgres;
create temp table count_before on commit drop as select count(*)::integer as n from public.upload_batches;
grant select on count_before to authenticated;
set local role authenticated;
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.one('image/png', 1, 'x.png'), gen_random_uuid()) $$,
  'P0001', 'storage_full', 'เต็มแล้ว 1 ไบต์ก็ไม่ได้');
set local role postgres;
select is((select count(*)::integer from public.upload_batches), (select n from count_before), 'storage_full ไม่สร้าง batch');
update public.storage_settings set quota_bytes = 500000000;

-- เพดานครั้ง: ใช้ครบ 30 ครั้งใน 10 นาที → rate_limited
delete from private.rate_limits where account_id = '3e000000-0000-4000-8000-000000000001' and action = 'upload_batch';
insert into private.rate_limits (account_id, action, window_start, hits)
values ('3e000000-0000-4000-8000-000000000001', 'upload_batch', date_bin('1 minute', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00'), 30);
set local role authenticated;
select throws_ok($$ select public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), gen_random_uuid()) $$,
  'P0001', 'rate_limited', 'ขอ batch เกิน 30 ครั้งใน 10 นาที → rate_limited');
select is(public.create_upload_batch('post', '7e000000-0000-4000-8000-000000000001', null, pg_temp.files(), 'b2000000-0000-4000-8000-000000000001'),
  (select body from res where label = 'post'), 'กดซ้ำด้วย request key เดิมยังได้ผลเดิม (ไม่นับเพดานครั้ง)');
set local role postgres;
select is((select count(*)::integer from private.rate_limits where account_id = '3e000000-0000-4000-8000-000000000001' and action = 'upload_batch' and hits > 0) > 0, true,
  'การขอ batch นับใน rate_limits');

select * from finish();
rollback;
