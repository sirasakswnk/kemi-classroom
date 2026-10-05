-- ทดสอบ 0017_upload_complete: ขั้น complete (ยืนยันเจ้าของด้วย JWT + เขียนผลด้วย service_role) และตัวนับงบ B2 รายวัน
-- ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ; ยอดพื้นที่/ตัวนับเทียบเป็นส่วนต่าง
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
    execute format('grant execute on function %s to anon, authenticated, service_role', f);
  end loop;
end
$$;

select plan(49);

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
select ok(
  has_function_privilege('authenticated', 'public.upload_complete_target(uuid,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.upload_complete_target(uuid,integer)', 'EXECUTE'),
  'upload_complete_target: authenticated เรียกได้ anon ไม่ได้');
select ok(
  (select bool_and(has_function_privilege('service_role', f, 'EXECUTE')
                   and not has_function_privilege('authenticated', f, 'EXECUTE')
                   and not has_function_privilege('anon', f, 'EXECUTE'))
     from unnest(array['public.upload_complete_begin(uuid,uuid,integer,text,bigint,text,integer)',
                       'public.upload_complete_finish(uuid,text,text)',
                       'public.upload_complete_abort(uuid)',
                       'public.record_b2_usage(text,integer,bigint,bigint)']::regprocedure[]) f),
  'begin/finish/abort/record_b2_usage: service_role เท่านั้น');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.b2_daily_usage'::regclass)
  and not has_table_privilege('authenticated', 'public.b2_daily_usage', 'SELECT')
  and not has_table_privilege('anon', 'public.b2_daily_usage', 'SELECT'),
  'b2_daily_usage: เปิด RLS และผู้ใช้อ่าน/เขียนไม่ได้');
select results_eq(
  $$ select daily_view_budget_bytes, daily_view_budget_requests from public.storage_settings $$,
  $$ values (750000000::bigint, 1800) $$,
  'ค่างบเปิดดูรายวันเริ่มต้นอยู่ในแถว storage_settings (750 MB / 1,800 คำขอ)');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4f000000-0000-4000-8000-000000000001', 'ภาคทดสอบ complete', 'active');
insert into public.term_control (term_id) values ('4f000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1f000000-0000-4000-8000-000000000001', 'ครูทดสอบ complete'),
  ('1f000000-0000-4000-8000-000000000002', 'ครูทดสอบ complete อื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3f000000-0000-4000-8000-000000000001', '2f000000-0000-4000-8000-000000000001', 'google', 'uc-1', 'teacher17a@example.com', 'teacher', '1f000000-0000-4000-8000-000000000001'),
  ('3f000000-0000-4000-8000-000000000002', '2f000000-0000-4000-8000-000000000002', 'google', 'uc-2', 'teacher17b@example.com', 'teacher', '1f000000-0000-4000-8000-000000000002');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000001', 'เคมีทดสอบ complete', 'WWWW23'),
  ('7f000000-0000-4000-8000-000000000002', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000002', 'เคมีห้องอื่น complete', 'WWWW24');

-- batch เปิด (2 ไฟล์), batch หมดอายุ, batch ของครูอีกคน — ใส่ตรงแทน create_upload_batch (ทดสอบแล้วใน 0016)
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, files, reserved_bytes, created_at, expires_at) values
  ('9f000000-0000-4000-8000-000000000001', '3f000000-0000-4000-8000-000000000001', 'post', '7f000000-0000-4000-8000-000000000001',
   '[{"staging_key": "staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000001", "file_name": "โจทย์ Kc.pdf", "content_type": "application/pdf", "size_bytes": 1000},
     {"staging_key": "staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000002", "file_name": "รูปตาราง.jpg", "content_type": "image/jpeg", "size_bytes": 500}]',
   1500, clock_timestamp(), clock_timestamp() + interval '2 hours'),
  ('9f000000-0000-4000-8000-000000000002', '3f000000-0000-4000-8000-000000000001', 'post', '7f000000-0000-4000-8000-000000000001',
   '[{"staging_key": "staging/9f000000-0000-4000-8000-000000000002/a1000000-0000-4000-8000-000000000003", "file_name": "เก่า.png", "content_type": "image/png", "size_bytes": 100}]',
   100, clock_timestamp() - interval '3 hours', clock_timestamp() - interval '1 hour'),
  ('9f000000-0000-4000-8000-000000000003', '3f000000-0000-4000-8000-000000000002', 'post', '7f000000-0000-4000-8000-000000000002',
   '[{"staging_key": "staging/9f000000-0000-4000-8000-000000000003/a1000000-0000-4000-8000-000000000004", "file_name": "ของครูอื่น.pdf", "content_type": "application/pdf", "size_bytes": 10}]',
   10, clock_timestamp(), clock_timestamp() + interval '2 hours');

create temp table base on commit drop as
  select private.storage_used_bytes() as used,
         coalesce((select class_b_requests from public.b2_daily_usage
                    where day = (clock_timestamp() at time zone 'UTC')::date and source = 'complete'), 0) as requests,
         coalesce((select download_bytes from public.b2_daily_usage
                    where day = (clock_timestamp() at time zone 'UTC')::date and source = 'complete'), 0) as bytes,
         coalesce((select copy_bytes from public.b2_daily_usage
                    where day = (clock_timestamp() at time zone 'UTC')::date and source = 'complete'), 0) as copy_bytes;
create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated, service_role;
grant select on base to service_role;
-- ส่วนต่างของตัวนับวันนี้ (source = complete) เทียบก่อนเริ่ม
create function pg_temp.usage_delta() returns text language sql security definer set search_path = '' as $$
  select format('%s req / %s B / copy %s B',
                coalesce(u.class_b_requests, 0) - b.requests, coalesce(u.download_bytes, 0) - b.bytes,
                coalesce(u.copy_bytes, 0) - b.copy_bytes)
    from pg_temp.base b
    left join public.b2_daily_usage u on u.day = (clock_timestamp() at time zone 'UTC')::date and u.source = 'complete'
$$;
grant execute on function pg_temp.usage_delta() to service_role;

-- ---------------------------------------------------------------------------
-- ขั้นที่ 1: upload_complete_target (JWT ของผู้ใช้)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 1),
  jsonb_build_object('account_id', '3f000000-0000-4000-8000-000000000001', 'batch_id', '9f000000-0000-4000-8000-000000000001', 'item', 1,
                     'staging_key', 'staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000001',
                     'file_name', 'โจทย์ Kc.pdf', 'content_type', 'application/pdf', 'size_bytes', 1000, 'asset', null),
  'เจ้าของ batch ได้ staging key/ชนิด/ขนาดที่ประกาศจากแถว batch (ยังไม่มี asset)');
select is(public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 2) ->> 'staging_key',
  'staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000002', 'ลำดับไฟล์ที่ 2 ได้ key ของไฟล์ที่ 2');
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 3) $$,
  'P0001', 'invalid_request', 'ลำดับไฟล์เกินจำนวนในชุด → invalid_request');
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 0) $$,
  'P0001', 'invalid_request', 'ลำดับไฟล์ 0 → invalid_request');
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-000000000003', 1) $$,
  'P0001', 'forbidden', 'batch ของครูคนอื่น → forbidden');
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-0000000000ff', 1) $$,
  'P0001', 'forbidden', 'batch ที่ไม่มี → forbidden (ตอบเหมือน batch ของคนอื่น)');
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-000000000002', 1) $$,
  'P0001', 'upload_expired', 'batch หมดอายุและไฟล์ยังไม่ complete → upload_expired');
select throws_ok($$ select public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, 'v1', 1000, 'application/pdf', 16) $$,
  '42501', null, 'ผู้ใช้เรียก upload_complete_begin ผ่าน PostgREST ตรง ๆ ไม่ได้');
select throws_ok($$ select public.upload_complete_finish(gen_random_uuid(), 'v', 'etag') $$,
  '42501', null, 'ผู้ใช้เรียก upload_complete_finish ไม่ได้');
select throws_ok($$ select public.record_b2_usage('view', 1, 1) $$,
  '42501', null, 'ผู้ใช้เรียก record_b2_usage ไม่ได้');
select throws_ok($$ select * from public.b2_daily_usage $$,
  '42501', null, 'ผู้ใช้อ่านตัวนับงบรายวันไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-0000000000ff", "role": "authenticated"}';
select throws_ok($$ select public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 1) $$,
  'P0001', 'account_required', 'ผู้ใช้ที่ยังไม่มีบัญชี → account_required');

-- ---------------------------------------------------------------------------
-- ขั้นที่ 2: upload_complete_begin (service_role) — ตรวจผล GET แบบ Range
-- ---------------------------------------------------------------------------
set local role service_role;
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, 'v-size', 1001, 'application/pdf', 16),
  '{"code": "upload_size_mismatch"}'::jsonb, 'ขนาดเต็มจาก Content-Range ไม่เท่าที่ประกาศ → upload_size_mismatch');
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, 'v-type', 1000, null, 16),
  '{"code": "upload_type_mismatch"}'::jsonb, 'magic number ไม่ใช่ JPEG/PNG/PDF → upload_type_mismatch');
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, 'v-type2', 1000, 'image/png', 16),
  '{"code": "upload_type_mismatch"}'::jsonb, 'เนื้อไฟล์เป็น PNG แต่ประกาศ PDF → upload_type_mismatch');
select is(pg_temp.usage_delta(), '3 req / 48 B / copy 0 B', 'ผลที่ถูกปฏิเสธยังนับคำขอ GET และไบต์ที่อ่าน (3 ครั้ง × 16 ไบต์)');
select is((select count(*)::integer from public.assets where upload_batch_id = '9f000000-0000-4000-8000-000000000001'), 0,
  'ผลที่ถูกปฏิเสธไม่สร้าง asset');
select throws_ok($$ select public.upload_complete_begin('3f000000-0000-4000-8000-000000000002', '9f000000-0000-4000-8000-000000000001', 1, 'v', 1000, 'application/pdf', 16) $$,
  'P0001', 'forbidden', 'บัญชีที่ส่งมาไม่ใช่เจ้าของ batch → forbidden');
select throws_ok($$ select public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 3, 'v', 1000, 'application/pdf', 16) $$,
  'P0001', 'invalid_request', 'ลำดับไฟล์เกิน → invalid_request');
select throws_ok($$ select public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, 'v', 1000, 'application/pdf', 17) $$,
  'P0001', 'invalid_request', 'อ่านเกิน 16 ไบต์ไม่ใช่รูปแบบของขั้นนี้ → invalid_request');
select throws_ok($$ select public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, '', 1000, 'application/pdf', 16) $$,
  'P0001', 'invalid_request', 'ไม่มี version id ของไฟล์พัก → invalid_request');
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000002', 1, 'v', 100, 'image/png', 16),
  '{"code": "upload_expired"}'::jsonb, 'batch หมดอายุ → upload_expired (ไม่สร้าง asset)');

insert into res values ('pdf', public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, '4_zstaging_v1', 1000, 'application/pdf', 16));
select ok((select body ->> 'status' = 'copying' and body ->> 'final_key' = 'files/' || (body ->> 'asset_id') || '.pdf'
                  and body ->> 'file_name' = 'โจทย์ Kc.pdf' and (body ->> 'size_bytes')::bigint = 1000 from res where label = 'pdf'),
  'ผ่านการตรวจ → asset สถานะ copying และ final_key = files/{asset_id}.pdf (ไม่ผูกกับโพสต์)');
set local role postgres;
select results_eq(
  $$ select owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, content_type, size_bytes, status, version_id, checksum
       from public.assets where id = ((select body from res where label = 'pdf') ->> 'asset_id')::uuid $$,
  $$ values ('3f000000-0000-4000-8000-000000000001'::uuid, 'post', '9f000000-0000-4000-8000-000000000001'::uuid,
             'staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000001', '4_zstaging_v1',
             'application/pdf', 1000::bigint, 'copying', null::text, null::text) $$,
  'แถว asset เก็บเจ้าของ/batch/staging key จาก batch และเวอร์ชันไฟล์พักที่อ่าน');
select is(private.storage_used_bytes() - (select used from base), 0::bigint,
  'ยอดพื้นที่ไม่นับซ้ำ: asset นับแทนส่วนที่ batch จองไว้');
set local role service_role;
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, '4_zstaging_v2', 1000, 'application/pdf', 16),
  jsonb_build_object('asset_id', (select body ->> 'asset_id' from res where label = 'pdf'), 'status', 'copying', 'existing', true),
  'เรียกซ้ำ/พร้อมกันระหว่างคัดลอก → ได้ asset เดิม (existing) ไม่สร้างแถวใหม่');
set local role postgres;
select is((select count(*)::integer from public.assets where staging_key like 'staging/9f000000-0000-4000-8000-000000000001/%'), 1,
  'ไฟล์พักหนึ่งชิ้นมี asset เดียว');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3f000000-0000-4000-8000-000000000001', 'post', 'staging/9f000000-0000-4000-8000-000000000001/a1000000-0000-4000-8000-000000000001',
                            'x', 'files/dup.pdf', 'application/pdf', 1000, 'ซ้ำ.pdf') $$,
  '23505', null, 'staging_key ซ้ำไม่ได้ (unique index กันคัดลอกซ้ำ)');
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 1) -> 'asset',
  jsonb_build_object('id', (select body ->> 'asset_id' from res where label = 'pdf'), 'status', 'copying'),
  'target บอกสถานะ asset ที่มีแล้ว (Edge Function ตอบ upload_in_progress โดยไม่เรียก B2)');

-- ---------------------------------------------------------------------------
-- ขั้นที่ 3: finish / abort (service_role)
-- ---------------------------------------------------------------------------
set local role service_role;
select is(public.upload_complete_finish(((select body from res where label = 'pdf') ->> 'asset_id')::uuid, '4_zfinal_v1', 'd41d8cd98f00b204e9800998ecf8427e'),
  jsonb_build_object('asset_id', (select body ->> 'asset_id' from res where label = 'pdf'), 'file_name', 'โจทย์ Kc.pdf',
                     'content_type', 'application/pdf', 'size_bytes', 1000, 'status', 'ready'),
  'CopyObject สำเร็จ → ready');
set local role postgres;
select results_eq(
  $$ select status, version_id, checksum, ready_at is not null from public.assets
      where id = ((select body from res where label = 'pdf') ->> 'asset_id')::uuid $$,
  $$ values ('ready', '4_zfinal_v1', 'd41d8cd98f00b204e9800998ecf8427e', true) $$,
  'บันทึก version_id ปลายทางและ ETag');
set local role service_role;
select is(public.upload_complete_finish(((select body from res where label = 'pdf') ->> 'asset_id')::uuid, '4_zfinal_v1', 'd41d8cd98f00b204e9800998ecf8427e') ->> 'status',
  'ready', 'finish ซ้ำด้วยค่าเดิมได้ผลเดิม');
select throws_ok(format($$ select public.upload_complete_finish(%L, '4_zfinal_other', 'd41d8cd98f00b204e9800998ecf8427e') $$,
                        (select body ->> 'asset_id' from res where label = 'pdf')),
  'P0001', 'upload_failed', 'finish ด้วยเวอร์ชันอื่นหลัง ready → upload_failed (ไม่เขียนทับ)');
select throws_ok(format($$ select public.upload_complete_finish(%L, '4_zfinal_v1', '"quoted"') $$,
                        (select body ->> 'asset_id' from res where label = 'pdf')),
  'P0001', 'invalid_request', 'ETag ต้องตัดเครื่องหมายคำพูดก่อนบันทึก');
select is(pg_temp.usage_delta(), '6 req / 96 B / copy 1000 B', 'นับ GET ทุกครั้ง (รวม batch หมดอายุและ existing) + copy_bytes ของไฟล์ที่คัดลอก (finish ซ้ำไม่นับเพิ่ม)');
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 1, '4_zstaging_v3', 1000, 'application/pdf', 16) ->> 'status',
  'ready', 'begin หลัง ready → existing ready (Edge Function ตอบผลเดิม)');

insert into res values ('jpg', public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 2, '4_zjpg_v1', 500, 'image/jpeg', 16));
select ok((select body ->> 'final_key' like 'files/%.jpg' from res where label = 'jpg'), 'JPEG → final_key ลงท้าย .jpg');
select is(public.upload_complete_abort(((select body from res where label = 'jpg') ->> 'asset_id')::uuid), true,
  'CopyObject ถูกปฏิเสธแน่นอน → abort ลบแถว copying');
select is(public.upload_complete_abort(((select body from res where label = 'pdf') ->> 'asset_id')::uuid), false,
  'abort ไม่ลบไฟล์ที่ ready แล้ว');
select is(public.upload_complete_begin('3f000000-0000-4000-8000-000000000001', '9f000000-0000-4000-8000-000000000001', 2, '4_zjpg_v2', 500, 'image/jpeg', 16) ->> 'status',
  'copying', 'หลัง abort เรียก complete ใหม่ได้');

-- หลัง batch หมดอายุ ไฟล์ที่ complete แล้วยังตอบผลเดิม
set local role postgres;
update public.upload_batches set expires_at = created_at - interval '30 minutes', created_at = created_at - interval '1 hour'
 where id = '9f000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.upload_complete_target('9f000000-0000-4000-8000-000000000001', 1) #>> '{asset,status}', 'ready',
  'batch หมดอายุแล้ว ไฟล์ที่ ready ยังตอบผลเดิม (เรียกซ้ำหลังเน็ตหลุด)');

-- ---------------------------------------------------------------------------
-- record_b2_usage
-- ---------------------------------------------------------------------------
set local role service_role;
select lives_ok($$ select public.record_b2_usage('complete', 1, 0) $$, 'นับ GET ที่ได้ 404 (ไม่มีไฟล์พัก)');
select throws_ok($$ select public.record_b2_usage('backup', 1, 0) $$,
  'P0001', 'invalid_request', 'แหล่ง backup นับผ่าน psql (postgres) ไม่ใช่ RPC');
select throws_ok($$ select public.record_b2_usage('view', -1, 0) $$,
  'P0001', 'invalid_request', 'ค่าติดลบไม่ได้');
set local role postgres;
select is(pg_temp.usage_delta(), '10 req / 144 B / copy 1000 B', 'ยอดรวมของวันนี้ (source = complete) ตรงกับคำขอที่ทำ');

select * from finish();
rollback;
