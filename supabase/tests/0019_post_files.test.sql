-- ทดสอบ 0019_post_files: ผูกไฟล์โจทย์/ไฟล์แนบใน create_post/update_post — asset ของคนอื่น/ไม่ ready/วัตถุประสงค์ผิด/ผูกที่อื่น/
-- ซ้ำ/เกิน 10 ไฟล์/เกิน 20 MB, ประกาศว่าง, แก้เพิ่ม/เอาออก/เรียงใหม่, กติกา content_updated_at (N1/N2), ผู้ดูแลในโหมดผู้ดูแล,
-- batch ที่ผูกครบเลิกจอง, สมาชิกที่ถูกเอาออกเปิดไฟล์ไม่ได้ — ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
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

select plan(54);

select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.post_files_ids(jsonb)', 'private.post_files_apply(uuid,uuid[],uuid)',
                         'private.post_files_json(uuid)']) f,
            unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยของไฟล์โพสต์ใช้ภายในเท่านั้น');
select ok(pg_get_functiondef('private.post_files_apply(uuid,uuid[],uuid)'::regprocedure)
            ~ 'perform 1 from public\.assets a where a\.id = any\(p_ids\) order by a\.id for update;\s+select count',
  'ล็อกแถว asset ที่ขอ (FOR UPDATE) ก่อนตรวจว่าผูกแล้วหรือยัง — สองคำขอพร้อมกันทดสอบจริงแยกไว้ในโน้ต P3-06b');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน (ห้องละคน), ผู้ดูแล, นักเรียนสมาชิก + นักเรียนที่จะถูกเอาออก (ห้อง 1)
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4e000000-0000-4000-8000-000000000001', 'ภาคทดสอบไฟล์โพสต์', 'active');
insert into public.term_control (term_id) values ('4e000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1e000000-0000-4000-8000-000000000001', 'ครูทดสอบไฟล์โพสต์'),
  ('1e000000-0000-4000-8000-000000000002', 'ครูทดสอบไฟล์โพสต์สอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3e000000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'google', 'pf-1', 'teacher19a@example.com', 'teacher', '1e000000-0000-4000-8000-000000000001'),
  ('3e000000-0000-4000-8000-000000000002', '2e000000-0000-4000-8000-000000000002', 'google', 'pf-2', 'teacher19b@example.com', 'teacher', '1e000000-0000-4000-8000-000000000002'),
  ('3e000000-0000-4000-8000-000000000003', '2e000000-0000-4000-8000-000000000003', 'google', 'pf-3', 'admin19@example.com', 'admin', null),
  ('3e000000-0000-4000-8000-000000000004', '2e000000-0000-4000-8000-000000000004', 'google', 'pf-4', 'member19@example.com', 'student', null),
  ('3e000000-0000-4000-8000-000000000005', '2e000000-0000-4000-8000-000000000005', 'google', 'pf-5', 'removed19@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6e000000-0000-4000-8000-000000000001', '920000000000191', 'สมาชิก ไฟล์โพสต์', '3e000000-0000-4000-8000-000000000004'),
  ('6e000000-0000-4000-8000-000000000002', '920000000000192', 'ถูกเอาออก ไฟล์โพสต์', '3e000000-0000-4000-8000-000000000005');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000001', 'เคมีทดสอบไฟล์โพสต์ 1', 'YYYY32'),
  ('7e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000002', 'เคมีทดสอบไฟล์โพสต์ 2', 'YYYY33');
insert into public.memberships (classroom_id, student_id) values
  ('7e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000001'),
  ('7e000000-0000-4000-8000-000000000001', '6e000000-0000-4000-8000-000000000002');

-- batch ของครู 1 สองไฟล์ (ใช้ทดสอบการเลิกจองเมื่อผูกครบ) — ไฟล์ 01, 02 มาจาก batch นี้
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, files, reserved_bytes, expires_at) values
  ('9e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'post', '7e000000-0000-4000-8000-000000000001',
   '[{"staging_key":"staging/t19/01"},{"staging_key":"staging/t19/02"}]', 3000, clock_timestamp() + interval '1 hour');

-- asset: 01–05 ของครู 1 (ready, post) · 06 ครู 1 ยัง copying · 07 ครู 1 วัตถุประสงค์ solution · 08 ของครู 2
--        09–11 ของครู 1 PDF 10 MB (เกินเพดานรวม) · 12 ของผู้ดูแล · 13–24 ของครู 1 สำหรับนับ 11 ไฟล์
create function pg_temp.f(n integer) returns uuid language sql immutable as
  $$ select ('ae000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.fs(variadic n integer[]) returns jsonb language sql immutable as
  $$ select coalesce(jsonb_agg(pg_temp.f(x) order by o), '[]') from unnest(n) with ordinality u(x, o) $$;
insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
select pg_temp.f(n),
       case n when 8 then '3e000000-0000-4000-8000-000000000002'::uuid when 12 then '3e000000-0000-4000-8000-000000000003'::uuid
              else '3e000000-0000-4000-8000-000000000001'::uuid end,
       case n when 7 then 'solution' else 'post' end,
       case when n in (1, 2) then '9e000000-0000-4000-8000-000000000001'::uuid end,
       'staging/t19/' || lpad(n::text, 2, '0'), 'sv-' || n, 'files/t19/' || n || '.pdf', 'application/pdf',
       case when n between 9 and 11 then 10485760 else 1000 * n end,
       'ไฟล์ ' || n || '.pdf'
  from generate_series(1, 24) n;
update public.assets set status = 'ready', version_id = 'v-' || staging_version_id, checksum = 'e', ready_at = clock_timestamp()
 where id::text like 'ae000000-%' and id <> pg_temp.f(6);
-- โพสต์ของครู 2 ที่ผูกไฟล์ 08 อยู่แล้ว (สร้างตรงด้วย postgres)
insert into public.posts (id, classroom_id, kind, title, body) values
  ('8e000000-0000-4000-8000-0000000000b2', '7e000000-0000-4000-8000-000000000002', 'announcement', 'ประกาศห้อง 2', 'ข้อความ');
insert into public.attachments (asset_id, post_id, position) values (pg_temp.f(8), '8e000000-0000-4000-8000-0000000000b2', 1);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.ann(p_files jsonb, p_body text default null) returns jsonb language sql immutable as
  $$ select jsonb_build_object('kind', 'announcement', 'title', 'ประกาศมีไฟล์', 'body', p_body, 'files', p_files) $$;
create function pg_temp.hw(p_files jsonb) returns jsonb language sql immutable as
  $$ select jsonb_build_object('kind', 'homework', 'title', 'งานมีไฟล์โจทย์', 'full_score', 10, 'due_at', '2026-11-10T13:00:00Z',
                               'files', p_files) $$;
create function pg_temp.files_of(p_post uuid) returns uuid[] language sql stable as
  $$ select coalesce(array_agg(t.asset_id order by t.position), '{}') from public.attachments t where t.post_id = p_post $$;
create function pg_temp.post_of(p_label text) returns uuid language sql stable as
  $$ select (body ->> 'post_id')::uuid from res where label = p_label $$;
grant execute on function pg_temp.f(integer), pg_temp.fs(integer[]), pg_temp.ann(jsonb, text), pg_temp.hw(jsonb),
  pg_temp.files_of(uuid), pg_temp.post_of(text) to authenticated;
create temp table posts_before on commit drop as select count(*) as n from public.posts;

-- ---------------------------------------------------------------------------
-- ก: create_post ผูกไฟล์ (ครู 1)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('ann', public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(3, 1)), gen_random_uuid()));
select is((select jsonb_path_query_array(body, '$.files[*].asset_id') from res where label = 'ann'),
  jsonb_build_array(pg_temp.f(3), pg_temp.f(1)), 'ประกาศมีแต่ไฟล์ (ไม่มีข้อความ) โพสต์ได้ ผลคืนไฟล์ตามลำดับที่ส่ง');
select is((select body -> 'files' -> 0 from res where label = 'ann'),
  jsonb_build_object('asset_id', pg_temp.f(3), 'file_name', 'ไฟล์ 3.pdf', 'content_type', 'application/pdf', 'size_bytes', 3000),
  'ผลมีชื่อ ชนิด ขนาด (ไม่มี key/เวอร์ชัน)');
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(3), pg_temp.f(1)], 'แถวผูกเรียงตำแหน่ง 1, 2');
insert into res values ('hw', public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.hw(pg_temp.fs(2)), gen_random_uuid()));
select is(pg_temp.files_of(pg_temp.post_of('hw')), array[pg_temp.f(2)], 'การบ้านผูกไฟล์โจทย์ได้');

-- batch 01/02 ผูกครบสองไฟล์แล้ว (คนละโพสต์) → consumed
set local role postgres;
select is((select status from public.upload_batches where id = '9e000000-0000-4000-8000-000000000001'), 'consumed',
  'batch ที่ทุกไฟล์ถูกผูกแล้วตั้ง consumed (เลิกจองพื้นที่)');
set local role authenticated;

select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann('[]'), gen_random_uuid()) $$,
  'P0001', 'post_body_required', 'ประกาศไม่มีทั้งข้อความและไฟล์ → post_body_required');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', jsonb_build_object('kind', 'announcement', 'title', 'ว่าง'), gen_random_uuid()) $$,
  'P0001', 'post_body_required', 'ประกาศไม่ส่งคีย์ files และไม่มีข้อความ → post_body_required');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(4, 8)), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'asset ของครูคนอื่น → post_file_unavailable ทั้งคำขอ');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(6)), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'asset ที่ยังไม่ ready → post_file_unavailable');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(7)), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'asset วัตถุประสงค์ solution → post_file_unavailable');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(4, 3)), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'asset ของตัวเองที่ผูกกับโพสต์อื่นแล้ว → post_file_unavailable');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(jsonb_build_array('ae000000-0000-4000-8000-0000000000ff')), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'id ที่ไม่มีอยู่ได้รหัสเดียวกัน (ไม่บอกว่ามี asset หรือไม่)');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(4, 4)), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'id ซ้ำในรายการ → invalid_request');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)), gen_random_uuid()) $$,
  'P0001', 'too_many_files', 'เกิน 10 ไฟล์ → too_many_files');
select lives_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(9, 10)), gen_random_uuid()) $$,
  'รวม 20 MB พอดีผ่าน');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(9, 4)), gen_random_uuid()) $$,
  'P0001', 'post_file_unavailable', 'ไฟล์ที่เพิ่งผูกในโพสต์ก่อนหน้าใช้ซ้ำไม่ได้');
set local role postgres;
-- ปลดโพสต์ 20 MB เพื่อทดสอบเกินเพดาน (ลบโพสต์ = แถวผูกหายตาม asset คงอยู่)
delete from public.posts where id in (select t.post_id from public.attachments t where t.asset_id = pg_temp.f(9));
select is((select count(*)::integer from public.assets where id in (pg_temp.f(9), pg_temp.f(10))), 2,
  'ลบโพสต์แล้วแถวผูกหาย แต่ asset คงอยู่ (นับพื้นที่จนงานลบ P3-10)');
set local role authenticated;
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(9, 10, 4)), gen_random_uuid()) $$,
  'P0001', 'batch_too_large', 'รวมเกิน 20 MB → batch_too_large (J6)');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann('["not-a-uuid"]'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'รายการที่ไม่ใช่ uuid → invalid_request');
select throws_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(to_jsonb(pg_temp.f(4)::text)), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'files ไม่ใช่อาร์เรย์ → invalid_request');
set local role postgres;
select is((select count(*) from public.posts) - (select n from posts_before), 2::bigint,
  'คำขอที่ถูกปฏิเสธไม่สร้างโพสต์ และไม่ผูกไฟล์ใดเลย');
select is((select count(*)::integer from public.attachments where asset_id in (pg_temp.f(4), pg_temp.f(5), pg_temp.f(11))), 0,
  'ไฟล์ในคำขอที่ถูกปฏิเสธไม่ถูกผูก');
set local role authenticated;

-- ส่งซ้ำด้วย request key เดิมได้โพสต์เดิม (ไม่ผูกซ้ำ/ไม่ชนแถวผูก)
select lives_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(4)), 'fe000000-0000-4000-8000-000000000001') $$,
  'สร้างประกาศด้วยไฟล์ 04');
select is(
  (public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(4)), 'fe000000-0000-4000-8000-000000000001') ->> 'post_id')::uuid,
  (select t.post_id from public.attachments t where t.asset_id = pg_temp.f(4)),
  'request key เดิม → โพสต์เดิม (ไม่ได้ post_file_unavailable จากการผูกครั้งแรก)');

-- ---------------------------------------------------------------------------
-- ข: update_post — เพิ่ม/เอาออก/เรียงใหม่ และกติกา content_updated_at (N1/N2)
-- ---------------------------------------------------------------------------
create function pg_temp.edit(p_post uuid, p_patch jsonb) returns jsonb language sql as $$
  select public.update_post(p_post,
           jsonb_build_object('kind', p.kind, 'title', p.title, 'body', p.body) || p_patch,
           p.version, gen_random_uuid())
    from public.posts p where p.id = p_post
$$;
create function pg_temp.mark(p_post uuid) returns void language sql as $$
  update public.posts set content_updated_at = '2026-01-01 00:00:00+00' where id = p_post
$$;
create function pg_temp.state(p_post uuid) returns text language sql stable as $$
  select version || ' ' || (content_updated_at > '2026-01-01 00:00:00+00') from public.posts where id = p_post
$$;
set local role postgres;
grant execute on function pg_temp.edit(uuid, jsonb), pg_temp.state(uuid) to authenticated;
select pg_temp.mark(pg_temp.post_of('ann'));
create temp table v0 on commit drop as select version from public.posts where id = pg_temp.post_of('ann');
grant select on v0 to authenticated;
set local role authenticated;

insert into res values ('same', pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', pg_temp.fs(3, 1))));
select is((select body ->> 'changed' from res where label = 'same'), 'false', 'ส่งชุดเดิมลำดับเดิม → ไม่เปลี่ยน');
select is(pg_temp.state(pg_temp.post_of('ann')), (select version from v0) || ' false', 'ชุดเดิม: version และ content_updated_at ไม่ขยับ');

insert into res values ('add', pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', pg_temp.fs(3, 1, 5))));
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(3), pg_temp.f(1), pg_temp.f(5)], 'แก้: เพิ่มไฟล์ต่อท้าย');
select is(pg_temp.state(pg_temp.post_of('ann')), ((select version from v0) + 1) || ' true', 'เพิ่มไฟล์ = แก้โจทย์: version +1 และขยับ content_updated_at');
select is((select jsonb_array_length(body -> 'files') from res where label = 'add'), 3, 'ผลของ update_post คืนไฟล์ชุดใหม่');

set local role postgres;
select pg_temp.mark(pg_temp.post_of('ann'));
set local role authenticated;
select lives_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', pg_temp.fs(5, 3, 1))) $$, 'เรียงใหม่ (สลับตำแหน่งทั้งหมด)');
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(5), pg_temp.f(3), pg_temp.f(1)], 'ลำดับใหม่ถูกต้อง');
select is(pg_temp.state(pg_temp.post_of('ann')), ((select version from v0) + 2) || ' true', 'เรียงใหม่ = แก้โจทย์: ขยับ content_updated_at');

select lives_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', pg_temp.fs(5, 1))) $$, 'เอาไฟล์ 03 ออก');
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(5), pg_temp.f(1)], 'เอาออกแล้วเหลือสองไฟล์ ตำแหน่ง 1, 2');
set local role postgres;
select is((select status from public.assets where id = pg_temp.f(3)), 'ready', 'asset ที่เอาออกยังอยู่ (ready) — เลิกผูกเท่านั้น');
set local role authenticated;
select lives_ok($$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(3)), gen_random_uuid()) $$,
  'asset ที่เอาออกจากโพสต์แล้วผูกกับโพสต์ใหม่ได้');

select lives_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('title', 'ชื่อใหม่')) $$, 'แก้ชื่ออย่างเดียว (ไม่ส่ง files)');
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(5), pg_temp.f(1)], 'ไม่ส่งคีย์ files = คงชุดเดิม');

select throws_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', pg_temp.fs(5, 8))) $$,
  'P0001', 'post_file_unavailable', 'แก้: เพิ่ม asset ที่ผูกกับโพสต์ของครูอื่น → post_file_unavailable');
select is(pg_temp.files_of(pg_temp.post_of('ann')), array[pg_temp.f(5), pg_temp.f(1)], 'แก้ที่ถูกปฏิเสธไม่เปลี่ยนชุดไฟล์');

-- ประกาศ: เอาข้อความออกได้ถ้ายังมีไฟล์ · เอาออกทั้งสองไม่ได้
select lives_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('body', null)) $$, 'ประกาศมีไฟล์ เอาข้อความออกได้');
select throws_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('files', '[]'::jsonb)) $$,
  'P0001', 'post_body_required', 'ประกาศไม่มีข้อความแล้ว เอาไฟล์ออกหมด → post_body_required');
select lives_ok($$ select pg_temp.edit(pg_temp.post_of('ann'), jsonb_build_object('body', 'มีข้อความแล้ว', 'files', '[]'::jsonb)) $$,
  'ใส่ข้อความพร้อมเอาไฟล์ออกหมดได้');
select is(pg_temp.files_of(pg_temp.post_of('ann')), '{}'::uuid[], 'รายการว่าง = เอาไฟล์ออกทั้งหมด');

-- ครูห้องอื่นแก้โพสต์ห้อง 1 ไม่ได้ (สิทธิ์เดิมของ update_post)
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.update_post(pg_temp.post_of('hw'), jsonb_build_object('kind', 'homework', 'files', pg_temp.fs(8)), 1, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นผูกไฟล์กับโพสต์ห้อง 1 ไม่ได้');

-- ---------------------------------------------------------------------------
-- ค: ผู้ดูแลในโหมดผู้ดูแล — คงไฟล์เดิมของครูได้ เพิ่มได้เฉพาะ asset ของตัวเอง
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select lives_ok(
  $$ select public.update_post(p.id, jsonb_build_object('kind', 'homework', 'files', pg_temp.fs(2, 12)), p.version, gen_random_uuid(), true)
       from public.posts p where p.id = pg_temp.post_of('hw') $$,
  'ผู้ดูแลในโหมดผู้ดูแล: คงไฟล์โจทย์ของครูและเพิ่ม asset ของตัวเองได้');
select is(pg_temp.files_of(pg_temp.post_of('hw')), array[pg_temp.f(2), pg_temp.f(12)], 'ไฟล์โจทย์ = ของครู + ของผู้ดูแล');
select throws_ok(
  $$ select public.update_post(p.id, jsonb_build_object('kind', 'homework', 'files', pg_temp.fs(2, 12, 14)), p.version, gen_random_uuid(), true)
       from public.posts p where p.id = pg_temp.post_of('hw') $$,
  'P0001', 'post_file_unavailable', 'ผู้ดูแลแนบ asset ที่ยังไม่ผูกของครูไม่ได้');
select throws_ok(
  $$ select public.update_post(p.id, jsonb_build_object('kind', 'homework', 'files', pg_temp.fs(2)), p.version, gen_random_uuid(), false)
       from public.posts p where p.id = pg_temp.post_of('hw') $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลแก้ไฟล์ไม่ได้');
select throws_ok(
  $$ select public.create_post('7e000000-0000-4000-8000-000000000001', pg_temp.ann(pg_temp.fs(15)), gen_random_uuid(), true) $$,
  'P0001', 'post_file_unavailable', 'ผู้ดูแลสร้างโพสต์โดยแนบ asset ของครูไม่ได้');

-- ---------------------------------------------------------------------------
-- ง: เปิดไฟล์ — สมาชิกเปิดได้ สมาชิกที่ถูกเอาออกเปิดไม่ได้ (authorize_files ของ 0018)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2e000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.authorize_files(array[pg_temp.f(2)]), array[pg_temp.f(2)], 'สมาชิกเปิดไฟล์โจทย์ที่ผูกผ่าน create_post ได้');
set local role postgres;
delete from public.memberships where student_id = '6e000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.authorize_files(array[pg_temp.f(2), pg_temp.f(12)]), '{}'::uuid[], 'สมาชิกที่ถูกเอาออกเปิดไฟล์ของห้องนั้นไม่ได้แล้ว');

select * from finish();
rollback;
