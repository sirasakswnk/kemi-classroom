-- ทดสอบ 0055_retention_data: แถวคะแนน/เวลาส่ง/ความคิดเห็นของภาคเรียนเก่า, ความคิดเห็นที่ยกเลิกไม่มีเนื้อความ,
-- snapshot หมวด data และเงื่อนไขยืนยันลบคะแนน (P6-05a2)
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

select plan(25);

-- ข้อมูลสมมติ: T1 ปัจจุบัน · T0 เก่า (เริ่มเทอมทับ 400 วันก่อน: คะแนนครบ 1 ปีแล้ว ไม่มีไฟล์) ·
-- TF เก่า 400 วันเหมือนกันแต่ยังมีไฟล์โจทย์ · TX เก่า 400 วันไม่มีงานเลย
-- C0 (T0): สมาชิก S1 (เลขที่ 2) S2 (เลขที่ 1) · S3 ออกจากห้องแล้วแต่มีงานส่ง
-- H0: S1 ส่ง + ตรวจ 8 ผ่าน · S3 ส่ง ยังไม่ตรวจ · S2 ไม่ส่ง มีความคิดเห็นครู 1 + ความคิดเห็นของ S2 ที่ยกเลิกแล้ว 1
-- H1 (โพสต์ทีหลัง): ไม่มีใครส่ง · ประกาศ N0 ไม่นับ
insert into public.terms (id, name, status, started_at) values
  ('40550000-0000-4000-8000-000000000001', 'ภาคคะแนนเก่า ปัจจุบัน', 'active', now() - interval '20 days');
insert into public.terms (id, name, status, started_at, superseded_at) values
  ('40550000-0000-4000-8000-000000000002', 'ภาคคะแนนเก่า เก่า', 'superseded', now() - interval '600 days', now() - interval '400 days'),
  ('40550000-0000-4000-8000-000000000003', 'ภาคคะแนนเก่า มีไฟล์', 'superseded', now() - interval '700 days', now() - interval '400 days'),
  ('40550000-0000-4000-8000-000000000004', 'ภาคคะแนนเก่า ว่าง', 'superseded', now() - interval '800 days', now() - interval '400 days');
insert into public.term_control (term_id) values ('40550000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10550000-0000-4000-8000-000000000001', 'ครูคะแนนเก่า');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30550000-0000-4000-8000-000000000001', '20550000-0000-4000-8000-000000000001', 'google', 'rd-1', 't55@example.com', 'teacher', '10550000-0000-4000-8000-000000000001'),
  ('30550000-0000-4000-8000-000000000002', '20550000-0000-4000-8000-000000000002', 'google', 'rd-2', 'a55@example.com', 'admin', null),
  ('30550000-0000-4000-8000-000000000012', '20550000-0000-4000-8000-000000000012', 'google', 'rd-12', 's55@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60550000-0000-4000-8000-000000000001', '955000000000551', 'หนึ่ง คะแนนเก่า', null),
  ('60550000-0000-4000-8000-000000000002', '955000000000552', 'สอง คะแนนเก่า', '30550000-0000-4000-8000-000000000012'),
  ('60550000-0000-4000-8000-000000000003', '955000000000553', 'สาม คะแนนเก่า', null);
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('40550000-0000-4000-8000-000000000002', '60550000-0000-4000-8000-000000000001', '5/7', 2),
  ('40550000-0000-4000-8000-000000000002', '60550000-0000-4000-8000-000000000002', '5/7', 1);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70550000-0000-4000-8000-000000000000', '40550000-0000-4000-8000-000000000002', '10550000-0000-4000-8000-000000000001', 'คะแนนเก่า', 'ZZZZ6B'),
  ('70550000-0000-4000-8000-000000000003', '40550000-0000-4000-8000-000000000003', '10550000-0000-4000-8000-000000000001', 'คะแนนเก่ามีไฟล์', 'ZZZZ6C'),
  ('70550000-0000-4000-8000-000000000004', '40550000-0000-4000-8000-000000000004', '10550000-0000-4000-8000-000000000001', 'คะแนนเก่าว่าง', 'ZZZZ6D');
insert into public.memberships (classroom_id, student_id) values
  ('70550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000001'),
  ('70550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000002'),
  ('70550000-0000-4000-8000-000000000003', '60550000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80550000-0000-4000-8000-000000000000', '70550000-0000-4000-8000-000000000000', 'homework', 'H0 สมดุล', now() - interval '500 days'),
  ('80550000-0000-4000-8000-000000000001', '70550000-0000-4000-8000-000000000000', 'homework', 'H1 กรดเบส', now() - interval '450 days'),
  ('80550000-0000-4000-8000-000000000002', '70550000-0000-4000-8000-000000000000', 'announcement', 'N0 ประกาศ', now() - interval '480 days'),
  ('80550000-0000-4000-8000-000000000003', '70550000-0000-4000-8000-000000000003', 'homework', 'HF มีไฟล์', now() - interval '500 days');
insert into public.assignments (post_id, full_score, due_at) values
  ('80550000-0000-4000-8000-000000000000', 10, date_trunc('minute', now() - interval '490 days')),
  ('80550000-0000-4000-8000-000000000001', 20, date_trunc('minute', now() - interval '440 days')),
  ('80550000-0000-4000-8000-000000000003', 10, date_trunc('minute', now() - interval '490 days'));
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50550000-0000-4000-8000-000000000001', '80550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000001',
   now() - interval '495 days', now() - interval '495 days'),
  ('50550000-0000-4000-8000-000000000003', '80550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000003',
   now() - interval '493 days', now() - interval '492 days');
insert into public.comments (id, assignment_id, student_id, author_account_id, body, created_at, retracted_at) values
  ('c0550000-0000-4000-8000-000000000001', '80550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000002',
   '30550000-0000-4000-8000-000000000001', 'ส่งงานด้วยนะ', now() - interval '489 days', null),
  ('c0550000-0000-4000-8000-000000000002', '80550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000002',
   '30550000-0000-4000-8000-000000000012', null, now() - interval '488 days', now() - interval '487 days');
-- TF: ไฟล์โจทย์ 1 ไฟล์ยังอยู่
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
values ('a0550000-0000-4000-8000-000000000001', '30550000-0000-4000-8000-000000000001', 'post', 'staging/t55/01', 'sv-1',
        'files/t55/01.png', 'image/png', 1000, 'รูป.png');
update public.assets set status = 'ready', version_id = 'v-1', checksum = 'etag', ready_at = clock_timestamp()
 where id = 'a0550000-0000-4000-8000-000000000001';
insert into public.attachments (asset_id, post_id, position) values
  ('a0550000-0000-4000-8000-000000000001', '80550000-0000-4000-8000-000000000003', 1);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.st(p_term uuid) returns jsonb language sql volatile as $$
  select x -> 'data' from jsonb_array_elements(public.term_overview() -> 'old_terms') x where (x ->> 'id')::uuid = p_term
$$;
grant execute on function pg_temp.st(uuid) to authenticated;
-- แถวของคู่ (งาน, รหัสนักเรียน)
create function pg_temp.row_of(p_label text, p_title text, p_code text) returns jsonb language sql stable as $$
  select x from jsonb_array_elements(pg_temp.r(p_label) -> 'rows') x
   where x ->> 'post_title' = p_title and x ->> 'student_code' = p_code
$$;
grant execute on function pg_temp.row_of(text, text, text) to authenticated;

set local role authenticated;
-- ครูตรวจงานของ S1 (ภาคเรียนเก่ายังตรวจได้ตาม I5)
select pg_temp.as_user('20550000-0000-4000-8000-000000000001');
insert into res values ('g', public.grade_submission('50550000-0000-4000-8000-000000000001', 8, true, null, null, 1, 0, gen_random_uuid()));

-- ---------------------------------------------------------------------------
-- สิทธิ์และคำขอผิด
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20550000-0000-4000-8000-000000000012');
select throws_ok($$ select public.export_term_data('40550000-0000-4000-8000-000000000002') $$, 'P0001', 'forbidden',
  'นักเรียนขอข้อมูลคะแนนทั้งภาคเรียนไม่ได้');
select pg_temp.as_user('20550000-0000-4000-8000-000000000002');
select throws_ok($$ select public.export_term_data('40550000-0000-4000-8000-000000000002') $$, 'P0001', 'admin_mode_required',
  'ผู้ดูแลต้องอยู่ในโหมดผู้ดูแล');
select lives_ok($$ select public.export_term_data('40550000-0000-4000-8000-000000000002', true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลขอได้');
select pg_temp.as_user('20550000-0000-4000-8000-000000000001');
select throws_ok($$ select public.export_term_data('40550000-0000-4000-8000-000000000001') $$, 'P0001', 'invalid_request',
  'ภาคเรียนที่ยังเปิดไม่ได้');

-- ---------------------------------------------------------------------------
-- แถว
-- ---------------------------------------------------------------------------
insert into res values ('d', public.export_term_data('40550000-0000-4000-8000-000000000002'));
select is(jsonb_build_array(pg_temp.r('d') -> 'count', jsonb_array_length(pg_temp.r('d') -> 'rows'), pg_temp.r('d') -> 'bytes',
                            pg_temp.r('d') ->> 'term_name'),
  '[5, 5, 0, "ภาคคะแนนเก่า เก่า"]'::jsonb, '5 แถว = H0 × (S1, S2, S3 ที่ออกแล้วแต่ส่งงาน) + H1 × สมาชิก 2 คน · ไม่มีไฟล์ = 0 ไบต์');
select is((select jsonb_agg(jsonb_build_array(x ->> 'post_title', x ->> 'student_code') order by o)
             from jsonb_array_elements(pg_temp.r('d') -> 'rows') with ordinality e(x, o)),
  '[["H0 สมดุล", "955000000000552"], ["H0 สมดุล", "955000000000551"], ["H0 สมดุล", "955000000000553"],
    ["H1 กรดเบส", "955000000000552"], ["H1 กรดเบส", "955000000000551"]]'::jsonb,
  'เรียงตามงาน (เวลาโพสต์) → เลขที่ → คนที่ไม่มีในรายชื่อไว้ท้าย · ประกาศไม่นับ');
select is(jsonb_build_array(pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') -> 'graded_current',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') -> 'raw_score',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') -> 'net_score',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') -> 'passed',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') -> 'roll_number',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000551') ->> 'group_name'),
  '[true, 8, 8, true, 2, "5/7"]'::jsonb, 'S1 ตรวจแล้ว: คะแนนดิบ/สุทธิ/ผ่าน พร้อมห้องและเลขที่ในรายชื่อของภาคเรียนนั้น');
select is(jsonb_build_array(pg_temp.row_of('d', 'H0 สมดุล', '955000000000553') -> 'member',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000553') -> 'graded_current',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000553') -> 'net_score',
                            (pg_temp.row_of('d', 'H0 สมดุล', '955000000000553') ->> 'last_submitted_at')::timestamptz
                              = now() - interval '492 days',
                            pg_temp.row_of('d', 'H0 สมดุล', '955000000000553') -> 'roll_number'),
  '[false, false, null, true, null]'::jsonb, 'S3 ออกจากห้องแล้ว: ยังมีแถว รอตรวจ เวลาส่งล่าสุดถูกต้อง ไม่มีเลขที่');
select is(jsonb_build_array(pg_temp.row_of('d', 'H1 กรดเบส', '955000000000551') -> 'graded_current',
                            pg_temp.row_of('d', 'H1 กรดเบส', '955000000000551') -> 'first_submitted_at',
                            pg_temp.row_of('d', 'H1 กรดเบส', '955000000000551') -> 'full_score',
                            pg_temp.row_of('d', 'H1 กรดเบส', '955000000000551') -> 'comments'),
  '[null, null, 20, []]'::jsonb, 'สมาชิกที่ยังไม่ส่ง: ไม่มีเวลาส่ง/สถานะตรวจ ไม่มีความคิดเห็น');
select is((select jsonb_agg(jsonb_build_array(c ->> 'author', c -> 'retracted', c -> 'body') order by o)
             from jsonb_array_elements(pg_temp.row_of('d', 'H0 สมดุล', '955000000000552') -> 'comments') with ordinality e(c, o)),
  '[["teacher", false, "ส่งงานด้วยนะ"], ["student", true, null]]'::jsonb,
  'ความคิดเห็นเรียงตามเวลา บอกผู้เขียน ที่ยกเลิกแล้วไม่มีเนื้อข้อความ');
select ok(not exists (select 1 from jsonb_array_elements(pg_temp.r('d') -> 'rows') x,
                                    jsonb_array_elements(x -> 'comments') c
                       where c ? 'id' or (c ->> 'retracted')::boolean and c ->> 'body' is not null),
  'ไม่มี id ความคิดเห็น และทุกความคิดเห็นที่ยกเลิกไม่มีเนื้อข้อความ');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.r('d') -> 'rows') x
            where x ?| array['student_id', 'submission_id', 'classroom_id']),
  0, 'ไม่ส่ง id ภายในของนักเรียน/งานส่ง/ห้อง');

-- ---------------------------------------------------------------------------
-- สถานะและบันทึกว่าดาวน์โหลด
-- ---------------------------------------------------------------------------
select is(jsonb_build_array(pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'expired',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'count',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'files_cleared',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'downloaded',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'can_confirm'),
  '[true, 5, true, false, false]'::jsonb, 'T0 คะแนนครบ 1 ปี ไม่มีไฟล์ แต่ยังไม่ดาวน์โหลด → ปุ่มยืนยันกดไม่ได้');
select throws_ok(format($$ select public.export_mark_downloaded('40550000-0000-4000-8000-000000000002', 'data', %L, 4, 0) $$,
                        pg_temp.r('d') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'จำนวนแถวไม่ตรง → ปฏิเสธ');
select throws_ok(format($$ select public.export_mark_downloaded('40550000-0000-4000-8000-000000000002', 'data', %L, 5, 1) $$,
                        pg_temp.r('d') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'หมวดคะแนนต้องส่งไบต์ 0');
insert into res values ('m', public.export_mark_downloaded('40550000-0000-4000-8000-000000000002', 'data',
                                                           pg_temp.r('d') ->> 'fingerprint', 5, 0));
select is(jsonb_build_array(pg_temp.r('m') -> 'data' -> 'downloaded', pg_temp.r('m') -> 'data' -> 'can_confirm',
                            pg_temp.r('m') -> 'files' -> 'can_confirm'),
  '[true, true, false]'::jsonb, 'ดาวน์โหลด CSV ครบ → ยืนยันลบคะแนนได้ (ไม่ทำให้ลบไฟล์ได้)');

-- ครูเขียนความคิดเห็นเพิ่มหลังดาวน์โหลด → ต้องดาวน์โหลดใหม่
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.comments (assignment_id, student_id, author_account_id, body) values
  ('80550000-0000-4000-8000-000000000000', '60550000-0000-4000-8000-000000000003', '30550000-0000-4000-8000-000000000001', 'ตรวจแล้วนะ');
set local role authenticated;
select pg_temp.as_user('20550000-0000-4000-8000-000000000001');
select is(jsonb_build_array(pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'downloaded',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'download_stale',
                            pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'can_confirm'),
  '[false, true, false]'::jsonb, 'ความคิดเห็นเพิ่มหลังดาวน์โหลด → ต้องดาวน์โหลดใหม่');
insert into res values ('d2', public.export_term_data('40550000-0000-4000-8000-000000000002'));
select isnt(pg_temp.r('d2') ->> 'fingerprint', pg_temp.r('d') ->> 'fingerprint', 'fingerprint เปลี่ยนตามข้อมูล');

-- ตรวจซ้ำ (แก้คะแนน) ก็ทำให้ชุดเปลี่ยน
insert into res values ('m2', public.export_mark_downloaded('40550000-0000-4000-8000-000000000002', 'data',
                                                            pg_temp.r('d2') ->> 'fingerprint', 5, 0));
select is(pg_temp.r('m2') -> 'data' -> 'can_confirm', 'true'::jsonb, 'ดาวน์โหลดชุดใหม่ครบ → ยืนยันได้อีกครั้ง');
insert into res values ('g2', public.grade_submission('50550000-0000-4000-8000-000000000001', 9, true, null, null, 1, 1, gen_random_uuid()));
select is(pg_temp.st('40550000-0000-4000-8000-000000000002') -> 'download_stale', 'true'::jsonb,
  'แก้คะแนนหลังดาวน์โหลด → ต้องดาวน์โหลดใหม่');
select is(pg_temp.row_of('d2', 'H0 สมดุล', '955000000000551') -> 'net_score', '8'::jsonb, 'ชุดที่ดาวน์โหลดก่อนแก้ยังเป็นคะแนนเดิม');

-- ภาคเรียนที่ยังมีไฟล์: ดาวน์โหลดคะแนนครบแล้วก็ยังลบคะแนนไม่ได้จนลบไฟล์ก่อน
insert into res values ('df', public.export_term_data('40550000-0000-4000-8000-000000000003'));
insert into res values ('mf', public.export_mark_downloaded('40550000-0000-4000-8000-000000000003', 'data',
                                                            pg_temp.r('df') ->> 'fingerprint', 1, 0));
select is(jsonb_build_array(pg_temp.r('mf') -> 'data' -> 'downloaded', pg_temp.r('mf') -> 'data' -> 'files_cleared',
                            pg_temp.r('mf') -> 'data' -> 'can_confirm'),
  '[true, false, false]'::jsonb, 'TF ยังมีไฟล์ → ยืนยันลบคะแนนไม่ได้ (ลบงานส่งก่อนไฟล์ไม่ได้)');

-- ภาคเรียนที่ไม่มีงานเลย: ไม่มีอะไรให้ดาวน์โหลด ยืนยันได้เมื่อครบอายุ
insert into res values ('dx', public.export_term_data('40550000-0000-4000-8000-000000000004'));
select is(jsonb_build_array(pg_temp.r('dx') -> 'count', pg_temp.r('dx') -> 'rows'), '[0, []]'::jsonb, 'TX ไม่มีแถว');
select throws_ok(format($$ select public.export_mark_downloaded('40550000-0000-4000-8000-000000000004', 'data', %L, 0, 0) $$,
                        pg_temp.r('dx') ->> 'fingerprint'),
  'P0001', 'export_mismatch', 'ชุดว่างบันทึกดาวน์โหลดไม่ได้');
select is(jsonb_build_array(pg_temp.st('40550000-0000-4000-8000-000000000004') -> 'downloaded',
                            pg_temp.st('40550000-0000-4000-8000-000000000004') -> 'can_confirm'),
  '[false, true]'::jsonb, 'TX ครบ 1 ปีและไม่มีแถว → ยืนยันลบได้โดยไม่ต้องดาวน์โหลด');

select * from finish();
rollback;
