-- ทดสอบ 0018_files_sign: สิทธิ์เปิดไฟล์ข้ามคน (authorize_files ด้วย JWT) และงบเปิดดูรายวัน (files_sign_begin ด้วย service_role)
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 92000000000018x, อีเมล @example.com) และ rollback ตอนจบ
-- ยอดงบเทียบเป็นส่วนต่างจากก่อนทดสอบ (kemi-dev อาจมีการเปิดไฟล์ของวันนี้อยู่แล้ว)
-- สองคำขอพร้อมกันจริง (สองการเชื่อมต่อ) ทดสอบแยกไว้ในโน้ต P3-05 — ไฟล์นี้ตรวจว่าล็อกแถวตัวนับก่อนอ่านยอด
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

select plan(50);

-- ---------------------------------------------------------------------------
-- สิทธิ์เรียกฟังก์ชัน
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('authenticated', 'public.authorize_files(uuid[])', 'EXECUTE')
          and not has_function_privilege('anon', 'public.authorize_files(uuid[])', 'EXECUTE'),
  'authorize_files: authenticated เรียกได้ anon ไม่ได้');
select ok(has_function_privilege('service_role', 'public.files_sign_begin(uuid[])', 'EXECUTE')
          and not has_function_privilege('authenticated', 'public.files_sign_begin(uuid[])', 'EXECUTE')
          and not has_function_privilege('anon', 'public.files_sign_begin(uuid[])', 'EXECUTE'),
  'files_sign_begin: service_role เท่านั้น (ผู้ใช้ได้ key/เวอร์ชันหรือใช้งบเองไม่ได้)');
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.files_sign_limits()', 'private.files_sign_ids(uuid[])']) f,
            unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'files_sign_limits/files_sign_ids ใช้ภายในเท่านั้น');
select ok(pg_get_functiondef('public.files_sign_begin(uuid[])'::regprocedure)
            ~ 'from public\.b2_daily_usage u where u\.day = v_day and u\.source = ''view'' for update;\s+select s\.\* into v_settings',
  'files_sign_begin ล็อกแถวตัวนับ view ของวัน (FOR UPDATE) ก่อนอ่านยอดและงบ — สองคำขอพร้อมกันผ่านงบรวมกันไม่ได้');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน (ห้องละคน), ผู้ดูแล, นักเรียน: สมาชิกห้อง 1 · สมาชิกห้อง 2 · คนที่ถูกเอาออกจากห้อง 1 · คนนอก
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4d000000-0000-4000-8000-000000000001', 'ภาคทดสอบเปิดไฟล์', 'active');
insert into public.term_control (term_id) values ('4d000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';
insert into public.teachers (id, display_name) values
  ('1d000000-0000-4000-8000-000000000001', 'ครูทดสอบเปิดไฟล์หนึ่ง'),
  ('1d000000-0000-4000-8000-000000000002', 'ครูทดสอบเปิดไฟล์สอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3d000000-0000-4000-8000-000000000001', '2d000000-0000-4000-8000-000000000001', 'google', 'fs-1', 'teacher18a@example.com', 'teacher', '1d000000-0000-4000-8000-000000000001'),
  ('3d000000-0000-4000-8000-000000000002', '2d000000-0000-4000-8000-000000000002', 'google', 'fs-2', 'teacher18b@example.com', 'teacher', '1d000000-0000-4000-8000-000000000002'),
  ('3d000000-0000-4000-8000-000000000003', '2d000000-0000-4000-8000-000000000003', 'google', 'fs-3', 'admin18@example.com', 'admin', null),
  ('3d000000-0000-4000-8000-000000000004', '2d000000-0000-4000-8000-000000000004', 'google', 'fs-4', 'member18@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000005', '2d000000-0000-4000-8000-000000000005', 'google', 'fs-5', 'other18@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000006', '2d000000-0000-4000-8000-000000000006', 'google', 'fs-6', 'removed18@example.com', 'student', null),
  ('3d000000-0000-4000-8000-000000000007', '2d000000-0000-4000-8000-000000000007', 'google', 'fs-7', 'outsider18@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6d000000-0000-4000-8000-000000000001', '920000000000181', 'สมาชิก เปิดไฟล์', '3d000000-0000-4000-8000-000000000004'),
  ('6d000000-0000-4000-8000-000000000002', '920000000000182', 'ห้องอื่น เปิดไฟล์', '3d000000-0000-4000-8000-000000000005'),
  ('6d000000-0000-4000-8000-000000000003', '920000000000183', 'ถูกเอาออก เปิดไฟล์', '3d000000-0000-4000-8000-000000000006'),
  ('6d000000-0000-4000-8000-000000000004', '920000000000184', 'คนนอก เปิดไฟล์', '3d000000-0000-4000-8000-000000000007');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7d000000-0000-4000-8000-000000000001', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000001', 'เคมีทดสอบเปิดไฟล์ 1', 'XXXX93'),
  ('7d000000-0000-4000-8000-000000000002', '4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000002', 'เคมีทดสอบเปิดไฟล์ 2', 'XXXX94');
insert into public.memberships (classroom_id, student_id) values
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000001'),
  ('7d000000-0000-4000-8000-000000000001', '6d000000-0000-4000-8000-000000000003'),
  ('7d000000-0000-4000-8000-000000000002', '6d000000-0000-4000-8000-000000000002');
-- ห้อง 1: งาน A (เฉลยยังไม่เผยแพร่) งาน C (เฉลยเผยแพร่แล้ว) · ห้อง 2: งาน D
insert into public.posts (id, classroom_id, kind, title) values
  ('8d000000-0000-4000-8000-00000000000a', '7d000000-0000-4000-8000-000000000001', 'homework', 'งาน A เปิดไฟล์'),
  ('8d000000-0000-4000-8000-00000000000c', '7d000000-0000-4000-8000-000000000001', 'homework', 'งาน C เปิดไฟล์'),
  ('8d000000-0000-4000-8000-00000000000d', '7d000000-0000-4000-8000-000000000002', 'homework', 'งาน D เปิดไฟล์');
insert into public.assignments (post_id, full_score, due_at) values
  ('8d000000-0000-4000-8000-00000000000a', 10, '2026-11-01 16:59:00+00'),
  ('8d000000-0000-4000-8000-00000000000c', 10, '2026-11-01 16:59:00+00'),
  ('8d000000-0000-4000-8000-00000000000d', 10, '2026-11-01 16:59:00+00');
insert into public.solutions (assignment_id, published_at) values
  ('8d000000-0000-4000-8000-00000000000a', null),
  ('8d000000-0000-4000-8000-00000000000c', '2026-11-03 01:00:00+00'),
  ('8d000000-0000-4000-8000-00000000000d', null);

-- ไฟล์: 01 โจทย์ A · 02 เฉลย A (ยังไม่เผยแพร่) · 03 เฉลย C (เผยแพร่แล้ว) · 04 โจทย์ D (ห้อง 2)
--       05 ของครู 1 ยังไม่ผูก · 06 ของครู 2 ยังไม่ผูก · 07 ของครู 1 ยัง copying · 08 ของครู 1 deleting
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ad000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'post', 'staging/t18/01', 'sv-01', 'files/t18/01.pdf', 'application/pdf', 100, 'โจทย์ A.pdf'),
  ('ad000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'solution', 'staging/t18/02', 'sv-02', 'files/t18/02.pdf', 'application/pdf', 200, 'เฉลย A.pdf'),
  ('ad000000-0000-4000-8000-000000000003', '3d000000-0000-4000-8000-000000000001', 'solution', 'staging/t18/03', 'sv-03', 'files/t18/03.jpg', 'image/jpeg', 400, 'เฉลย C.jpg'),
  ('ad000000-0000-4000-8000-000000000004', '3d000000-0000-4000-8000-000000000002', 'post', 'staging/t18/04', 'sv-04', 'files/t18/04.png', 'image/png', 800, 'โจทย์ D.png'),
  ('ad000000-0000-4000-8000-000000000005', '3d000000-0000-4000-8000-000000000001', 'post', 'staging/t18/05', 'sv-05', 'files/t18/05.jpg', 'image/jpeg', 1600, 'ร่าง 1.jpg'),
  ('ad000000-0000-4000-8000-000000000006', '3d000000-0000-4000-8000-000000000002', 'post', 'staging/t18/06', 'sv-06', 'files/t18/06.jpg', 'image/jpeg', 3200, 'ร่าง 2.jpg'),
  ('ad000000-0000-4000-8000-000000000007', '3d000000-0000-4000-8000-000000000001', 'post', 'staging/t18/07', 'sv-07', 'files/t18/07.pdf', 'application/pdf', 6400, 'กำลังคัดลอก.pdf'),
  ('ad000000-0000-4000-8000-000000000008', '3d000000-0000-4000-8000-000000000001', 'post', 'staging/t18/08', 'sv-08', 'files/t18/08.pdf', 'application/pdf', 12800, 'รอลบ.pdf');
update public.assets
   set status = 'ready', version_id = 'v-' || right(id::text, 2), checksum = 'etag-' || right(id::text, 2), ready_at = clock_timestamp()
 where id::text like 'ad000000-%' and id <> 'ad000000-0000-4000-8000-000000000007';
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp()
 where id = 'ad000000-0000-4000-8000-000000000008';
insert into public.attachments (asset_id, post_id, solution_id, position) values
  ('ad000000-0000-4000-8000-000000000001', '8d000000-0000-4000-8000-00000000000a', null, 1),
  ('ad000000-0000-4000-8000-000000000002', null, '8d000000-0000-4000-8000-00000000000a', 1),
  ('ad000000-0000-4000-8000-000000000003', null, '8d000000-0000-4000-8000-00000000000c', 1),
  ('ad000000-0000-4000-8000-000000000004', '8d000000-0000-4000-8000-00000000000d', null, 1);

-- ชื่อย่อของ id เพื่อให้อ่านเทสต์ง่าย: pg_temp.f(1) = ad000000-…-000000000001
create function pg_temp.f(n integer) returns uuid language sql immutable as
  $$ select ('ad000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.fs(variadic n integer[]) returns uuid[] language sql immutable as
  $$ select coalesce(array_agg(pg_temp.f(x) order by o), '{}') from unnest(n) with ordinality u(x, o) $$;
grant execute on function pg_temp.f(integer), pg_temp.fs(integer[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- ก: authorize_files ด้วย JWT ของแต่ละคน — คืนเฉพาะ id ที่เปิดได้
-- ---------------------------------------------------------------------------
set local role authenticated;
-- นักเรียนสมาชิกห้อง 1
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1)), pg_temp.fs(1), 'สมาชิกเปิดไฟล์โจทย์ของห้องตนได้');
select is(public.authorize_files(pg_temp.fs(2)), '{}'::uuid[], 'สมาชิกเปิดไฟล์เฉลยที่ยังไม่เผยแพร่ไม่ได้');
select is(public.authorize_files(pg_temp.fs(3)), pg_temp.fs(3), 'สมาชิกเปิดไฟล์เฉลยที่เผยแพร่แล้วได้');
select is(public.authorize_files(pg_temp.fs(4)), '{}'::uuid[], 'สมาชิกเปิดไฟล์โจทย์ของห้องอื่นไม่ได้');
select is(public.authorize_files(pg_temp.fs(5)), '{}'::uuid[], 'asset ที่ยังไม่ผูกของคนอื่น (ครู) เปิดไม่ได้');
select is(public.authorize_files(pg_temp.fs(4, 1, 2, 3)), pg_temp.fs(1, 3),
  'ขอปนกัน: คืนเฉพาะที่มีสิทธิ์ตามลำดับที่ขอ (Edge Function ตอบ forbidden ทั้งชุด)');
select is(public.authorize_files(array['ad000000-0000-4000-8000-0000000000ff']::uuid[]), '{}'::uuid[],
  'id ที่ไม่มีอยู่ได้ผลเหมือนไม่มีสิทธิ์ (ไม่บอกว่ามีไฟล์หรือไม่)');
select is(public.authorize_files(pg_temp.fs(1, 1, 3, 1)), pg_temp.fs(1, 3), 'id ซ้ำนับครั้งเดียว');

-- นักเรียนห้อง 2
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1, 3)), '{}'::uuid[], 'นักเรียนห้องอื่นเปิดไฟล์โจทย์/เฉลยของห้อง 1 ไม่ได้');
select is(public.authorize_files(pg_temp.fs(4)), pg_temp.fs(4), 'นักเรียนห้อง 2 เปิดไฟล์โจทย์ของห้องตนได้');

-- คนนอก (มีบัญชี ไม่อยู่ห้องใด)
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1, 3, 4)), '{}'::uuid[], 'คนนอกเปิดไฟล์ของห้องใดไม่ได้');

-- ล็อกอินแล้วแต่ยังไม่มีแถวบัญชี
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-0000000000ff", "role": "authenticated"}';
select throws_ok($$ select public.authorize_files(pg_temp.fs(1)) $$, 'P0001', 'account_required',
  'ยังไม่มีบัญชี → account_required');

-- นักเรียนที่ถูกเอาออก: ก่อนเอาออกเปิดได้ หลังเอาออกเปิดไม่ได้ (ตรวจ membership ทุกคำขอ)
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1, 3)), pg_temp.fs(1, 3), 'ก่อนถูกเอาออก: เปิดไฟล์โจทย์/เฉลยที่เผยแพร่แล้วได้');
set local role postgres;
delete from public.memberships
 where classroom_id = '7d000000-0000-4000-8000-000000000001' and student_id = '6d000000-0000-4000-8000-000000000003';
set local role authenticated;
select is(public.authorize_files(pg_temp.fs(1, 3)), '{}'::uuid[], 'หลังถูกเอาออก: เปิดไฟล์ของห้องนั้นไม่ได้แล้ว');

-- ครูห้อง 1 (เจ้าของห้อง + ผู้อัปโหลด)
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(3, 1, 2, 5)), pg_temp.fs(3, 1, 2, 5),
  'ครูเจ้าของห้องเปิดโจทย์ เฉลย (รวมยังไม่เผยแพร่) และ asset ที่ยังไม่ผูกของตนได้ ตามลำดับที่ขอ');
select is(public.authorize_files(pg_temp.fs(4)), '{}'::uuid[], 'ครูเปิดไฟล์ของห้องครูอื่นไม่ได้');
select is(public.authorize_files(pg_temp.fs(6)), '{}'::uuid[], 'ครูเปิด asset ที่ยังไม่ผูกของครูอื่นไม่ได้');
select is(public.authorize_files(pg_temp.fs(7, 8)), '{}'::uuid[], 'ไฟล์ที่ยัง copying หรือ deleting เปิดไม่ได้แม้เป็นเจ้าของ');

-- ครูห้อง 2
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1, 2)), '{}'::uuid[], 'ครูห้อง 2 เปิดโจทย์/เฉลยของห้อง 1 ไม่ได้');
select is(public.authorize_files(pg_temp.fs(4, 6)), pg_temp.fs(4, 6), 'ครูห้อง 2 เปิดโจทย์ห้องตนและ asset ที่ยังไม่ผูกของตนได้');

-- ผู้ดูแล (อ่านได้เหมือน RLS อ่านของโพสต์/เฉลย) — asset ที่ยังไม่ผูกของคนอื่นยังเปิดไม่ได้
set local request.jwt.claims to '{"sub": "2d000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is(public.authorize_files(pg_temp.fs(1, 2, 3, 4)), pg_temp.fs(1, 2, 3, 4), 'ผู้ดูแลเปิดไฟล์โจทย์/เฉลยของทุกห้องได้');
select is(public.authorize_files(pg_temp.fs(5)), '{}'::uuid[], 'ผู้ดูแลเปิด asset ที่ยังไม่ผูกของครูไม่ได้');

-- รูปแบบคำขอ
select throws_ok($$ select public.authorize_files('{}'::uuid[]) $$, 'P0001', 'invalid_request', 'รายการว่าง → invalid_request');
select throws_ok($$ select public.authorize_files(null) $$, 'P0001', 'invalid_request', 'null → invalid_request');
select throws_ok($$ select public.authorize_files(array[pg_temp.f(1), null]) $$, 'P0001', 'invalid_request',
  'มี null ในรายการ → invalid_request');
select throws_ok($$ select public.authorize_files(array(select pg_temp.f(n) from generate_series(1, 21) n)) $$,
  'P0001', 'invalid_request', 'เกิน 20 ไฟล์ต่อคำขอ → invalid_request');
select lives_ok($$ select public.authorize_files(array(select pg_temp.f(n) from generate_series(1, 20) n)) $$,
  '20 ไฟล์ต่อคำขอได้');

-- เพดานครั้งต่อบัญชี (120 ครั้ง / 10 นาที): ทำให้ใกล้เต็มแล้วเรียกต่อ
set local role postgres;
insert into private.rate_limits (account_id, action, window_start, hits)
values ('3d000000-0000-4000-8000-000000000003', 'files_sign', date_bin('1 minute', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00'), 0)
on conflict (account_id, action, window_start) do nothing;
update private.rate_limits r
   set hits = 119 - (select coalesce(sum(x.hits), 0) from private.rate_limits x
                      where x.account_id = r.account_id and x.action = r.action and x.window_start <> r.window_start
                        and x.window_start > clock_timestamp() - interval '10 minutes')
 where r.account_id = '3d000000-0000-4000-8000-000000000003' and r.action = 'files_sign'
   and r.window_start = date_bin('1 minute', clock_timestamp(), timestamptz '2000-01-01 00:00:00+00');
set local role authenticated;
select is(public.authorize_files(pg_temp.fs(1)), pg_temp.fs(1), 'ครั้งที่ 120 ใน 10 นาทียังได้');
select throws_ok($$ select public.authorize_files(pg_temp.fs(1)) $$, 'P0001', 'rate_limited', 'ครั้งที่ 121 → rate_limited');
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(1)) $$, '42501', null,
  'ผู้ใช้เรียก files_sign_begin ตรง ๆ ไม่ได้ (ไม่ได้ key/เวอร์ชัน และใช้งบไม่ได้)');

-- ---------------------------------------------------------------------------
-- ข: files_sign_begin (service_role) — ข้อมูลลงลายเซ็น + ตรวจและนับงบเปิดดูของวัน
-- ---------------------------------------------------------------------------
set local role postgres;
create temp table base on commit drop as
select coalesce((select u.class_b_requests from public.b2_daily_usage u
                  where u.day = (clock_timestamp() at time zone 'UTC')::date and u.source = 'view'), 0) as requests,
       coalesce((select u.download_bytes from public.b2_daily_usage u
                  where u.day = (clock_timestamp() at time zone 'UTC')::date and u.source = 'view'), 0) as bytes;
-- ส่วนต่างของตัวนับ view วันนี้ (อ่านในนาม postgres — บน cloud service_role ไม่ได้สิทธิ์ตารางใหม่อัตโนมัติ)
create function pg_temp.view_delta() returns bigint[] language sql volatile as
  $$ select array[coalesce(u.class_b_requests, 0) - b.requests, coalesce(u.download_bytes, 0) - b.bytes]
       from base b
       left join public.b2_daily_usage u on u.day = (clock_timestamp() at time zone 'UTC')::date and u.source = 'view' $$;
create temp table res (n integer primary key, v jsonb) on commit drop;
grant select, insert on res to service_role;

set local role service_role;
insert into res values (1, public.files_sign_begin(pg_temp.fs(3, 1)));
set local role postgres;
select is(
  (select v from res where n = 1),
  jsonb_build_object('files', jsonb_build_array(
    jsonb_build_object('id', pg_temp.f(3), 'final_key', 'files/t18/03.jpg', 'version_id', 'v-03',
                       'content_type', 'image/jpeg', 'size_bytes', 400, 'file_name', 'เฉลย C.jpg'),
    jsonb_build_object('id', pg_temp.f(1), 'final_key', 'files/t18/01.pdf', 'version_id', 'v-01',
                       'content_type', 'application/pdf', 'size_bytes', 100, 'file_name', 'โจทย์ A.pdf'))),
  'คืน final_key/version_id/ชนิด/ขนาด/ชื่อ ตามลำดับที่ขอ');
select is(pg_temp.view_delta(), array[2, 500]::bigint[], 'นับงบ view: 1 คำขอ + ขนาดเต็มต่อไฟล์');

set local role service_role;
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(1, 7)) $$, 'P0001', 'forbidden',
  'มีไฟล์ copying ในชุด → forbidden ทั้งชุด');
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(8)) $$, 'P0001', 'forbidden', 'ไฟล์ deleting → forbidden');
select throws_ok($$ select public.files_sign_begin(array['ad000000-0000-4000-8000-0000000000ff']::uuid[]) $$,
  'P0001', 'forbidden', 'id ที่ไม่มีอยู่ → forbidden');
select throws_ok($$ select public.files_sign_begin('{}'::uuid[]) $$, 'P0001', 'invalid_request', 'รายการว่าง → invalid_request');
set local role postgres;
select is(pg_temp.view_delta(), array[2, 500]::bigint[], 'คำขอที่ถูกปฏิเสธไม่นับงบ');

-- งบจำนวนคำขอ: เหลือ 2 คำขอพอดี
update public.storage_settings
   set daily_view_budget_requests = (select requests from base) + 4,
       daily_view_budget_bytes = (select bytes from base) + 1000000;
set local role service_role;
select lives_ok($$ select public.files_sign_begin(pg_temp.fs(1, 1, 5)) $$, 'ใช้คำขอได้พอดีงบ (id ซ้ำนับครั้งเดียว)');
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(1)) $$, 'P0001', 'download_budget_reached',
  'ครบงบจำนวนคำขอ → download_budget_reached ไม่ออกลิงก์');
set local role postgres;
select is(pg_temp.view_delta(), array[4, 2200]::bigint[], 'ครั้งที่ครบงบไม่นับเพิ่ม');

-- งบไบต์: เหลือ 500 ไบต์ — ไฟล์ 400 ผ่าน ไฟล์ 400 อีกครั้งเกิน; ชุดที่บางไฟล์เกินถูกปฏิเสธทั้งชุด
update public.storage_settings
   set daily_view_budget_requests = 1000000,
       daily_view_budget_bytes = (select bytes from base) + 2700;
set local role service_role;
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(1, 2, 3)) $$, 'P0001', 'download_budget_reached',
  'ชุดที่รวมแล้วเกินงบไบต์ → ปฏิเสธทั้งชุด');
select lives_ok($$ select public.files_sign_begin(pg_temp.fs(3)) $$, 'ไฟล์ที่ยังอยู่ในงบไบต์ผ่าน');
select throws_ok($$ select public.files_sign_begin(pg_temp.fs(3)) $$, 'P0001', 'download_budget_reached',
  'ครบงบไบต์ → download_budget_reached');
set local role postgres;
select is(pg_temp.view_delta(), array[5, 2600]::bigint[], 'ยอดหลังครบงบไบต์ไม่เกินงบ');
select is(
  (select count(*)::integer from public.b2_daily_usage u where u.source <> 'view' and u.updated_at >= now()),
  0, 'งบเปิดดูนับเฉพาะแหล่ง view (ไม่แตะแถว complete/backup)');

-- งบเปิดดูกันเฉพาะการเปิดไฟล์ — ขั้น complete ยังนับได้ (record_b2_usage ไม่ตรวจงบ)
set local role service_role;
select lives_ok($$ select public.record_b2_usage('complete', 1, 16) $$,
  'ครบงบเปิดดูแล้ว ขั้น complete ของการส่งงานยังบันทึกได้ (ไม่ถูกหยุดด้วยงบนี้)');

select * from finish();
rollback;
