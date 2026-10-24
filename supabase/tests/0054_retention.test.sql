-- ทดสอบ 0054_retention: สิทธิ์, ชุดไฟล์ของภาคเรียนเก่า, รายการเป็นหน้า, สถานะครบอายุ/ดาวน์โหลด/ปุ่มยืนยัน (P6-05a1)
-- ข้อมูลสมมติ rollback ตอนจบ — ไม่เปลี่ยนภาคเรียนจริงของฐานข้อมูล
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

select plan(39);

-- ข้อมูลสมมติ: T1 ปัจจุบัน (active) · T0 เก่าแบบเริ่มเทอมทับเมื่อ 100 วันก่อน (ไฟล์ครบอายุแล้ว คะแนนยัง) ·
-- TE เก่าแบบกดจบเมื่อ 10 วันก่อน (ยังไม่ครบ ไม่มีไฟล์)
-- ห้อง C0 (T0), C1 (T1), CE (TE) · H0 (C0): ไฟล์โจทย์ A1, เฉลย A2, งานส่งของ S3 สองไฟล์ A3 A4
-- ไฟล์ที่ไม่นับใน T0: A8 โจทย์ของ C1 (เทอมปัจจุบัน), A7 ยังไม่ผูก, A6 โจทย์ของ CX (ภาคเรียนเก่าอีกภาค TX)
insert into public.terms (id, name, status, started_at) values
  ('40540000-0000-4000-8000-000000000001', 'ภาคเก็บอายุ ปัจจุบัน', 'active', now() - interval '20 days');
insert into public.terms (id, name, status, started_at, ended_at, superseded_at) values
  ('40540000-0000-4000-8000-000000000002', 'ภาคเก็บอายุ เก่า', 'superseded', now() - interval '250 days', null, now() - interval '100 days'),
  ('40540000-0000-4000-8000-000000000003', 'ภาคเก็บอายุ จบแล้ว', 'ended', now() - interval '60 days', now() - interval '10 days', null),
  ('40540000-0000-4000-8000-000000000004', 'ภาคเก็บอายุ อื่น', 'superseded', now() - interval '400 days', null, now() - interval '250 days');
insert into public.term_control (term_id) values ('40540000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10540000-0000-4000-8000-000000000001', 'ครูเก็บอายุ');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30540000-0000-4000-8000-000000000001', '20540000-0000-4000-8000-000000000001', 'google', 'ret-1', 't54@example.com', 'teacher', '10540000-0000-4000-8000-000000000001'),
  ('30540000-0000-4000-8000-000000000002', '20540000-0000-4000-8000-000000000002', 'google', 'ret-2', 'a54@example.com', 'admin', null),
  ('30540000-0000-4000-8000-000000000011', '20540000-0000-4000-8000-000000000011', 'google', 'ret-11', 's54@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60540000-0000-4000-8000-000000000003', '954000000000543', 'สาม เก็บอายุ', '30540000-0000-4000-8000-000000000011');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('40540000-0000-4000-8000-000000000002', '60540000-0000-4000-8000-000000000003', '5/9', 7);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70540000-0000-4000-8000-000000000000', '40540000-0000-4000-8000-000000000002', '10540000-0000-4000-8000-000000000001', 'เก็บอายุเก่า', 'ZZZZ5B'),
  ('70540000-0000-4000-8000-000000000001', '40540000-0000-4000-8000-000000000001', '10540000-0000-4000-8000-000000000001', 'เก็บอายุปัจจุบัน', 'ZZZZ5C'),
  ('70540000-0000-4000-8000-000000000003', '40540000-0000-4000-8000-000000000003', '10540000-0000-4000-8000-000000000001', 'เก็บอายุจบแล้ว', 'ZZZZ5D'),
  ('70540000-0000-4000-8000-000000000004', '40540000-0000-4000-8000-000000000004', '10540000-0000-4000-8000-000000000001', 'เก็บอายุอื่น', 'ZZZZ5E');
insert into public.memberships (classroom_id, student_id) values
  ('70540000-0000-4000-8000-000000000000', '60540000-0000-4000-8000-000000000003');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80540000-0000-4000-8000-000000000000', '70540000-0000-4000-8000-000000000000', 'homework', 'งานเก่า H0', now() - interval '200 days'),
  ('80540000-0000-4000-8000-000000000001', '70540000-0000-4000-8000-000000000001', 'announcement', 'ประกาศปัจจุบัน', now() - interval '5 days'),
  ('80540000-0000-4000-8000-000000000004', '70540000-0000-4000-8000-000000000004', 'announcement', 'ประกาศอื่น', now() - interval '300 days');
insert into public.assignments (post_id, full_score, due_at) values
  ('80540000-0000-4000-8000-000000000000', 10, date_trunc('minute', now() - interval '190 days'));
insert into public.solutions (assignment_id) values ('80540000-0000-4000-8000-000000000000');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50540000-0000-4000-8000-000000000003', '80540000-0000-4000-8000-000000000000', '60540000-0000-4000-8000-000000000003',
   now() - interval '195 days', now() - interval '195 days');
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
select ('a0540000-0000-4000-8000-00000000000' || n)::uuid,
       case when n in (3, 4) then '30540000-0000-4000-8000-000000000011' else '30540000-0000-4000-8000-000000000001' end::uuid,
       case n when 2 then 'solution' when 5 then 'solution' when 3 then 'submission' when 4 then 'submission' else 'post' end,
       'staging/t54/0' || n, 'sv-' || n, 'files/t54/0' || n || '.png', 'image/png', 1000 * n, 'รูป ' || n || '.png'
  from generate_series(1, 9) n;
update public.assets set status = 'ready', version_id = 'v-' || right(id::text, 1), checksum = 'etag', ready_at = clock_timestamp()
 where id::text like 'a0540000-%';
insert into public.attachments (asset_id, post_id, solution_id, submission_id, position) values
  ('a0540000-0000-4000-8000-000000000001', '80540000-0000-4000-8000-000000000000', null, null, 1),
  ('a0540000-0000-4000-8000-000000000002', null, '80540000-0000-4000-8000-000000000000', null, 1),
  ('a0540000-0000-4000-8000-000000000003', null, null, '50540000-0000-4000-8000-000000000003', 1),
  ('a0540000-0000-4000-8000-000000000004', null, null, '50540000-0000-4000-8000-000000000003', 2),
  ('a0540000-0000-4000-8000-000000000006', '80540000-0000-4000-8000-000000000004', null, null, 1),
  ('a0540000-0000-4000-8000-000000000008', '80540000-0000-4000-8000-000000000001', null, null, 1);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- สถานะหมวดของภาคเรียนจาก term_overview ในนามครู
create function pg_temp.st(p_term uuid, p_scope text) returns jsonb language sql volatile as $$
  select x -> p_scope from jsonb_array_elements(public.term_overview() -> 'old_terms') x where (x ->> 'id')::uuid = p_term
$$;
grant execute on function pg_temp.st(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- สิทธิ์และคำขอผิด
-- ---------------------------------------------------------------------------
select is(
  (select relrowsecurity and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'retention_requests')
     from pg_class where oid = 'public.retention_requests'::regclass),
  true, 'retention_requests เปิด RLS และไม่มี policy');
select is(has_table_privilege('authenticated', 'public.retention_requests', 'SELECT')
          or has_table_privilege('anon', 'public.retention_requests', 'SELECT'),
  false, 'ไม่ GRANT ตาราง retention_requests ให้ผู้ใช้');

set local role authenticated;
select pg_temp.as_user('20540000-0000-4000-8000-000000000011');
select throws_ok($$ select public.export_files_page('40540000-0000-4000-8000-000000000002') $$, 'P0001', 'forbidden',
  'นักเรียนขอรายการไฟล์ไม่ได้');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', md5(''), 1, 1) $$,
  'P0001', 'forbidden', 'นักเรียนบันทึกว่าดาวน์โหลดไม่ได้');
select pg_temp.as_user('20540000-0000-4000-8000-000000000002');
select throws_ok($$ select public.export_files_page('40540000-0000-4000-8000-000000000002') $$, 'P0001', 'admin_mode_required',
  'ผู้ดูแลต้องอยู่ในโหมดผู้ดูแล');
select lives_ok($$ select public.export_files_page('40540000-0000-4000-8000-000000000002', null, 20, true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลขอรายการได้');

select pg_temp.as_user('20540000-0000-4000-8000-000000000001');
select throws_ok($$ select public.export_files_page('40540000-0000-4000-8000-000000000001') $$, 'P0001', 'invalid_request',
  'ภาคเรียนที่ยังเปิดดาวน์โหลดตามอายุไม่ได้');
select throws_ok($$ select public.export_files_page(gen_random_uuid()) $$, 'P0001', 'invalid_request', 'ภาคเรียนที่ไม่มี');
select throws_ok($$ select public.export_files_page('40540000-0000-4000-8000-000000000002', null, 21) $$, 'P0001',
  'invalid_request', 'หน้าละไม่เกิน 20 ไฟล์');

-- ---------------------------------------------------------------------------
-- ชุดไฟล์และหน้า
-- ---------------------------------------------------------------------------
insert into res values ('p1', public.export_files_page('40540000-0000-4000-8000-000000000002', null, 3));
insert into res values ('p2', public.export_files_page('40540000-0000-4000-8000-000000000002',
                                                       (pg_temp.r('p1') ->> 'next_after')::uuid, 3));
select is(jsonb_build_array(pg_temp.r('p1') -> 'total_count', pg_temp.r('p1') -> 'total_bytes'), '[4, 10000]'::jsonb,
  'ชุดของ T0 = โจทย์ + เฉลย + งานส่ง 2 ไฟล์ (1000+2000+3000+4000 ไบต์) ไม่รวมเทอมอื่นและไฟล์ที่ไม่ผูก');
select is((select jsonb_agg(x ->> 'asset_id' order by ord) from jsonb_array_elements(pg_temp.r('p1') -> 'files') with ordinality o(x, ord)),
  '["a0540000-0000-4000-8000-000000000001", "a0540000-0000-4000-8000-000000000002", "a0540000-0000-4000-8000-000000000003"]'::jsonb,
  'หน้าแรก 3 ไฟล์เรียงตาม asset_id');
select is(pg_temp.r('p1') ->> 'next_after', 'a0540000-0000-4000-8000-000000000003', 'หน้าแรกบอกจุดต่อ');
select is(jsonb_build_array(jsonb_array_length(pg_temp.r('p2') -> 'files'), pg_temp.r('p2') -> 'files' -> 0 ->> 'asset_id',
                            pg_temp.r('p2') -> 'next_after'),
  '[1, "a0540000-0000-4000-8000-000000000004", null]'::jsonb, 'หน้าสุดท้ายมีไฟล์ที่เหลือและไม่มีจุดต่อ');
select is(pg_temp.r('p2') ->> 'fingerprint', pg_temp.r('p1') ->> 'fingerprint', 'fingerprint เท่ากันทุกหน้าเมื่อชุดไม่เปลี่ยน');
select is((select jsonb_agg(jsonb_build_array(x ->> 'purpose', x ->> 'post_title', x ->> 'classroom_name') order by x ->> 'asset_id')
             from jsonb_array_elements(pg_temp.r('p1') -> 'files') x),
  '[["post", "งานเก่า H0", "เก็บอายุเก่า"], ["solution", "งานเก่า H0", "เก็บอายุเก่า"], ["submission", "งานเก่า H0", "เก็บอายุเก่า"]]'::jsonb,
  'แต่ละไฟล์บอกวัตถุประสงค์ งาน และห้อง');
select is(pg_temp.r('p1') -> 'files' -> 2 -> 'student',
  '{"student_id": "60540000-0000-4000-8000-000000000003", "student_code": "954000000000543", "display_name": "สาม เก็บอายุ", "group_name": "5/9", "roll_number": 7}'::jsonb,
  'ไฟล์งานส่งบอกเจ้าของพร้อมห้องและเลขที่ในรายชื่อของภาคเรียนนั้น');
select is(pg_temp.r('p1') -> 'files' -> 0 -> 'student', 'null'::jsonb, 'ไฟล์โจทย์ไม่มีนักเรียน');
select ok(not (pg_temp.r('p1') -> 'files' -> 0 ?| array['final_key', 'version_id', 'checksum']),
  'รายการไม่เปิด key/เวอร์ชัน/checksum ของ B2');

-- ---------------------------------------------------------------------------
-- สถานะครบอายุ (คำนวณตอนอ่าน) ก่อนดาวน์โหลด
-- ---------------------------------------------------------------------------
select is(jsonb_build_array(pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'expired',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'early',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'count',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'downloaded',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'can_confirm'),
  '[true, false, 4, false, false]'::jsonb, 'T0 ไฟล์ครบ 60 วันแล้ว (เสนอให้ลบ) แต่ยังไม่ดาวน์โหลด → ปุ่มยืนยันกดไม่ได้');
select is(jsonb_build_array(pg_temp.st('40540000-0000-4000-8000-000000000002', 'data') -> 'expired',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'data') -> 'files_cleared',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'data') -> 'can_confirm'),
  '[false, false, false]'::jsonb, 'T0 คะแนนยังไม่ครบ 1 ปีและยังมีไฟล์ → ลบคะแนนไม่ได้');
select is(jsonb_build_array(pg_temp.st('40540000-0000-4000-8000-000000000003', 'files') -> 'expired',
                            pg_temp.st('40540000-0000-4000-8000-000000000003', 'files') -> 'early',
                            pg_temp.st('40540000-0000-4000-8000-000000000003', 'files') -> 'count'),
  '[false, true, 0]'::jsonb, 'TE กดจบ 10 วันก่อน: ยังไม่ครบอายุ ไม่มีไฟล์');
select is((select jsonb_build_array((x ->> 'files_due')::timestamptz = (x -> 'files' ->> 'due_at')::timestamptz,
                                    (x ->> 'data_due')::timestamptz = (x -> 'data' ->> 'due_at')::timestamptz,
                                    (x -> 'files' ->> 'due_at')::timestamptz = now() - interval '40 days',
                                    (x -> 'data' ->> 'due_at')::timestamptz = now() - interval '100 days' + interval '1 year')
             from jsonb_array_elements(public.term_overview() -> 'old_terms') x
            where x ->> 'id' = '40540000-0000-4000-8000-000000000002'),
  '[true, true, true, true]'::jsonb, 'วันครบอายุ +60 วัน / +1 ปี จาก superseded_at และคีย์เดิมของ 0042 ยังอยู่');
select is((select count(*)::integer from jsonb_array_elements(public.term_overview() -> 'old_terms') x
            where x ->> 'id' = '40540000-0000-4000-8000-000000000001'),
  0, 'ภาคเรียนที่ยังเปิดไม่อยู่ในข้อมูลเก่า');

-- ---------------------------------------------------------------------------
-- บันทึกว่าดาวน์โหลดครบ
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', %L, 3, 10000) $$,
                        pg_temp.r('p1') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'จำนวนไฟล์ไม่ตรง → ปฏิเสธ');
select throws_ok(format($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', %L, 4, 9999) $$,
                        pg_temp.r('p1') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'จำนวนไบต์ไม่ตรง → ปฏิเสธ');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', md5('x'), 4, 10000) $$,
  'P0001', 'export_mismatch', 'fingerprint ไม่ตรง (ชุดเปลี่ยนระหว่างดาวน์โหลด) → ปฏิเสธ');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000003', 'files', md5(''), 0, 0) $$,
  'P0001', 'export_mismatch', 'ชุดว่างไม่มีอะไรให้ดาวน์โหลด → บันทึกไม่ได้');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'data', md5(''), 1, 0) $$,
  'P0001', 'export_mismatch', 'หมวดคะแนนตรวจกับชุดของตัวเอง ไม่ใช่ชุดไฟล์ (0055)');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'cache', md5(''), 1, 0) $$,
  'P0001', 'invalid_request', 'หมวดที่ไม่มี → invalid_request');
select throws_ok($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000001', 'files', md5(''), 1, 1) $$,
  'P0001', 'invalid_request', 'ภาคเรียนที่ยังเปิดบันทึกไม่ได้');

insert into res values ('mark', public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files',
                                                              pg_temp.r('p1') ->> 'fingerprint', 4, 10000));
select is(jsonb_build_array(pg_temp.r('mark') -> 'files' -> 'downloaded', pg_temp.r('mark') -> 'files' -> 'can_confirm',
                            pg_temp.r('mark') -> 'files' -> 'download_stale',
                            (pg_temp.r('mark') -> 'files' ->> 'downloaded_at') is not null),
  '[true, true, false, true]'::jsonb, 'ดาวน์โหลดครบแล้ว → ปุ่มยืนยันลบกดได้ (ผลคืนสถานะใหม่)');
select is(pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'can_confirm', 'true'::jsonb,
  'term_overview เห็นสถานะเดียวกัน');
select lives_ok(format($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', %L, 4, 10000) $$,
                       pg_temp.r('p1') ->> 'fingerprint'),
  'บันทึกซ้ำด้วยชุดเดิมได้ (ทับเวลา)');
select is(pg_temp.st('40540000-0000-4000-8000-000000000002', 'data') -> 'can_confirm', 'false'::jsonb,
  'ดาวน์โหลดไฟล์แล้วไม่ทำให้ลบคะแนนได้');

-- ชุดเปลี่ยนหลังดาวน์โหลด (ครูแนบเฉลยเพิ่ม) → ต้องดาวน์โหลดใหม่
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.attachments (asset_id, solution_id, position) values
  ('a0540000-0000-4000-8000-000000000005', '80540000-0000-4000-8000-000000000000', 2);
set local role authenticated;
select pg_temp.as_user('20540000-0000-4000-8000-000000000001');
select is(jsonb_build_array(pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'downloaded',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'download_stale',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'can_confirm',
                            pg_temp.st('40540000-0000-4000-8000-000000000002', 'files') -> 'count'),
  '[false, true, false, 5]'::jsonb, 'ชุดไฟล์เปลี่ยนหลังดาวน์โหลด → ยังไม่ได้ดาวน์โหลดชุดนี้ ปุ่มยืนยันกดไม่ได้');
insert into res values ('p3', public.export_files_page('40540000-0000-4000-8000-000000000002'));
select isnt(pg_temp.r('p3') ->> 'fingerprint', pg_temp.r('p1') ->> 'fingerprint', 'fingerprint เปลี่ยนตามชุด');
select throws_ok(format($$ select public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files', %L, 4, 10000) $$,
                        pg_temp.r('p1') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'ZIP ชุดเก่าบันทึกเป็นชุดใหม่ไม่ได้');
insert into res values ('mark2', public.export_mark_downloaded('40540000-0000-4000-8000-000000000002', 'files',
                                                               pg_temp.r('p3') ->> 'fingerprint', 5, 15000));
select is(pg_temp.r('mark2') -> 'files' -> 'can_confirm', 'true'::jsonb, 'ดาวน์โหลดชุดใหม่ครบ → ยืนยันได้อีกครั้ง');

set local role postgres;
select is((select jsonb_build_array(r.downloaded_by_account_id, r.downloaded_count, r.downloaded_bytes, r.confirmed_at)
             from public.retention_requests r where r.term_id = '40540000-0000-4000-8000-000000000002'),
  '["30540000-0000-4000-8000-000000000001", 5, 15000, null]'::jsonb, 'แถวเดียวต่อภาคเรียน/หมวด เก็บชุดล่าสุดและผู้ดาวน์โหลด');

select * from finish();
rollback;
