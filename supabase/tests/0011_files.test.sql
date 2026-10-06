-- ทดสอบ 0011_files: ยอดพื้นที่ (ก) การจองพื้นที่ (ข) ไฟล์ไม่หายตาม cascade (ค) เป้าหมายของการผูก (ง) RLS อ่าน (จ)
-- สถานะไฟล์และช่องที่แก้ไม่ได้ (ฉ) ค่าตั้งพื้นที่แถวเดียว (ช) — ข้อมูลสมมติทั้งหมด (เลขประจำตัว 9200000000000xx,
-- อีเมล @example.com) และ rollback ตอนจบ; ยอดพื้นที่เทียบเป็นส่วนต่างจากก่อนใส่ข้อมูล (kemi-dev อาจมีไฟล์อยู่แล้ว)
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

select plan(103);

create temp table base on commit drop as select private.storage_used_bytes() as used;
create function pg_temp.used_delta() returns bigint language sql volatile as
  $$ select private.storage_used_bytes() - (select used from base) $$;

-- ---------------------------------------------------------------------------
-- โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('public', 'storage_settings', 'มี public.storage_settings');
select has_table('public', 'upload_batches', 'มี public.upload_batches');
select has_table('public', 'assets', 'มี public.assets');
select has_table('public', 'attachments', 'มี public.attachments');
select ok((select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.storage_settings'::regclass, 'public.upload_batches'::regclass,
                            'public.assets'::regclass, 'public.attachments'::regclass)),
  'ทั้ง 4 ตารางเปิด RLS');
select policies_are('public', 'storage_settings', array['storage_settings_select'], 'storage_settings มีเฉพาะ policy อ่าน');
select policies_are('public', 'upload_batches', array['upload_batches_select'], 'upload_batches มีเฉพาะ policy อ่าน');
select policies_are('public', 'assets', array['assets_select'], 'assets มีเฉพาะ policy อ่าน');
select policies_are('public', 'attachments', array['attachments_select'], 'attachments มีเฉพาะ policy อ่าน');
select is_empty(
  $$ select format('%s %s %s', r, t, p)
       from unnest(array['public.storage_settings', 'public.upload_batches', 'public.assets', 'public.attachments']) t,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
      where has_table_privilege(r, t, p)
     union all
     select format('%s %s column %s', r, t, p)
       from unnest(array['public.storage_settings', 'public.upload_batches', 'public.assets', 'public.attachments']) t,
            unnest(array['anon', 'authenticated']) r,
            unnest(array['INSERT', 'UPDATE', 'REFERENCES']) p
      where has_any_column_privilege(r, t, p)
     union all
     select format('anon %s SELECT', t)
       from unnest(array['public.storage_settings', 'public.upload_batches', 'public.assets', 'public.attachments']) t
      where has_any_column_privilege('anon', t, 'SELECT') $$,
  'anon ไม่มีสิทธิ์ใด และ authenticated ไม่มีสิทธิ์เขียน (ทั้งระดับตารางและคอลัมน์) บน 4 ตาราง');
select ok(
  has_table_privilege('authenticated', 'public.storage_settings', 'SELECT')
  and has_table_privilege('authenticated', 'public.upload_batches', 'SELECT')
  and has_table_privilege('authenticated', 'public.attachments', 'SELECT'),
  'authenticated มี SELECT บน storage_settings/upload_batches/attachments (คัดแถวด้วย RLS)');
select is_empty(
  $$ select c from unnest(array['id', 'purpose', 'file_name', 'content_type', 'size_bytes', 'status', 'created_at']) c
      where not has_column_privilege('authenticated', 'public.assets', c, 'SELECT') $$,
  'assets: authenticated อ่านคอลัมน์ที่หน้าเว็บแสดงได้');
select is_empty(
  $$ select c from unnest(array['owner_account_id', 'upload_batch_id', 'staging_key', 'staging_version_id',
                                 'final_key', 'version_id', 'checksum', 'ready_at', 'delete_requested_at']) c
      where has_column_privilege('authenticated', 'public.assets', c, 'SELECT') $$,
  'assets: authenticated อ่าน key/version/checksum/เจ้าของไม่ได้ (ลิงก์ออกผ่าน Edge Function)');
select ok(
  has_function_privilege('authenticated', 'private.can_read_solution(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.can_read_solution(uuid)', 'EXECUTE'),
  'can_read_solution: authenticated เรียกได้ (ใช้ใน policy) anon ไม่ได้');
select is_empty(
  $$ select format('%s %s', r, f)
       from unnest(array['private.storage_used_bytes()', 'private.reserve_storage(bigint)']) f,
            unnest(array['anon', 'authenticated']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'storage_used_bytes/reserve_storage ใช้ภายในเท่านั้น (ไม่ GRANT ใคร)');

-- ง: เป้าหมายของการผูกมีเฉพาะที่มี FK (post / solution + submission จาก 0020) — ไม่มีคอลัมน์รอไว้สำหรับ charm
select columns_are('public', 'attachments', array['id', 'asset_id', 'post_id', 'solution_id', 'position', 'created_at', 'submission_id'],
  'attachments มีเป้าหมาย post_id/solution_id/submission_id (charm เพิ่มพร้อม FK ในระยะ 5)');
select fk_ok('public', 'attachments', 'post_id', 'public', 'posts', 'id', 'attachments.post_id อ้าง posts');
select fk_ok('public', 'attachments', 'solution_id', 'public', 'solutions', 'assignment_id', 'attachments.solution_id อ้าง solutions');
select fk_ok('public', 'attachments', 'asset_id', 'public', 'assets', 'id', 'attachments.asset_id อ้าง assets');

-- ---------------------------------------------------------------------------
-- ช: ค่าตั้งพื้นที่แถวเดียว ค่าฝั่ง dev
-- ---------------------------------------------------------------------------
select results_eq(
  $$ select count(*)::integer, min(quota_bytes), min(hard_stop_margin_bytes), min(admin_warn_pct), min(teacher_warn_pct)
       from public.storage_settings $$,
  $$ values (1, 500000000::bigint, 50000000::bigint, 80, 90) $$,
  'storage_settings มีแถวเดียว ค่า dev: quota 500,000,000 · margin 50,000,000 · เตือน 80/90%');
select throws_ok($$ insert into public.storage_settings (quota_bytes, hard_stop_margin_bytes) values (1000, 10) $$,
  '23505', null, 'เพิ่มแถวที่สองไม่ได้');
select throws_ok($$ insert into public.storage_settings (singleton, quota_bytes, hard_stop_margin_bytes) values (false, 1000, 10) $$,
  '23514', null, 'singleton ต้องเป็น true');
select throws_ok($$ update public.storage_settings set hard_stop_margin_bytes = quota_bytes $$,
  '23514', null, 'margin ต้องน้อยกว่า quota');
select throws_ok($$ update public.storage_settings set admin_warn_pct = 95 $$,
  '23514', null, 'เกณฑ์เตือนผู้ดูแลต้องไม่เกินเกณฑ์เตือนครู');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน (ห้องละคน), ผู้ดูแล, นักเรียน 3 คน (สมาชิกห้อง 1 สองคน ห้อง 2 หนึ่งคน), บัญชียังไม่ผูก
-- ---------------------------------------------------------------------------
insert into public.terms (id, name, status) values ('4b000000-0000-4000-8000-000000000001', 'ภาคทดสอบไฟล์', 'active');
insert into public.term_control (term_id) values ('4b000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active';
insert into public.teachers (id, display_name) values
  ('1b000000-0000-4000-8000-000000000001', 'ครูทดสอบไฟล์หนึ่ง'),
  ('1b000000-0000-4000-8000-000000000002', 'ครูทดสอบไฟล์สอง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3b000000-0000-4000-8000-000000000001', '2b000000-0000-4000-8000-000000000001', 'google', 'fi-1', 'teacher11a@example.com', 'teacher', '1b000000-0000-4000-8000-000000000001'),
  ('3b000000-0000-4000-8000-000000000002', '2b000000-0000-4000-8000-000000000002', 'google', 'fi-2', 'teacher11b@example.com', 'teacher', '1b000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000003', '2b000000-0000-4000-8000-000000000003', 'google', 'fi-3', 'admin11@example.com', 'admin', null),
  ('3b000000-0000-4000-8000-000000000004', '2b000000-0000-4000-8000-000000000004', 'google', 'fi-4', 'member11@example.com', 'student', null),
  ('3b000000-0000-4000-8000-000000000005', '2b000000-0000-4000-8000-000000000005', 'google', 'fi-5', 'outsider11@example.com', 'student', null),
  ('3b000000-0000-4000-8000-000000000006', '2b000000-0000-4000-8000-000000000006', 'google', 'fi-6', 'removed11@example.com', 'student', null),
  ('3b000000-0000-4000-8000-000000000007', '2b000000-0000-4000-8000-000000000007', 'google', 'fi-7', 'unbound11@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6b000000-0000-4000-8000-000000000001', '920000000000001', 'สมาชิก ห้องไฟล์', '3b000000-0000-4000-8000-000000000004'),
  ('6b000000-0000-4000-8000-000000000002', '920000000000002', 'คนนอก ห้องไฟล์', '3b000000-0000-4000-8000-000000000005'),
  ('6b000000-0000-4000-8000-000000000003', '920000000000003', 'ถูกเอาออก ห้องไฟล์', '3b000000-0000-4000-8000-000000000006');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7b000000-0000-4000-8000-000000000001', '4b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000001', 'เคมีทดสอบไฟล์ 1', 'XXXX25'),
  ('7b000000-0000-4000-8000-000000000002', '4b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000002', 'เคมีทดสอบไฟล์ 2', 'XXXX26');
insert into public.memberships (classroom_id, student_id) values
  ('7b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001'),
  ('7b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000003'),
  ('7b000000-0000-4000-8000-000000000002', '6b000000-0000-4000-8000-000000000002');
-- ห้อง 1: งาน A (เฉลยยังไม่เผยแพร่) งาน C (เฉลยเผยแพร่แล้ว) · ห้อง 2: งาน D
insert into public.posts (id, classroom_id, kind, title) values
  ('8b000000-0000-4000-8000-00000000000a', '7b000000-0000-4000-8000-000000000001', 'homework', 'งาน A ไฟล์'),
  ('8b000000-0000-4000-8000-00000000000c', '7b000000-0000-4000-8000-000000000001', 'homework', 'งาน C ไฟล์'),
  ('8b000000-0000-4000-8000-00000000000d', '7b000000-0000-4000-8000-000000000002', 'homework', 'งาน D ไฟล์');
insert into public.assignments (post_id, full_score, due_at) values
  ('8b000000-0000-4000-8000-00000000000a', 10, '2026-11-01 16:59:00+00'),
  ('8b000000-0000-4000-8000-00000000000c', 10, '2026-11-01 16:59:00+00'),
  ('8b000000-0000-4000-8000-00000000000d', 10, '2026-11-01 16:59:00+00');
insert into public.solutions (assignment_id, published_at) values
  ('8b000000-0000-4000-8000-00000000000a', null),
  ('8b000000-0000-4000-8000-00000000000c', '2026-11-03 01:00:00+00'),
  ('8b000000-0000-4000-8000-00000000000d', null);

-- batch ของนักเรียนสมาชิก: b1 เปิดอยู่ (จอง 10,000) · b2 หมดอายุ · b3 ยกเลิก · b4 ใช้แล้ว
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, reserved_bytes, status, created_at, expires_at) values
  ('9b000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000004', 'submission', '7b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', 10000, 'open', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour'),
  ('9b000000-0000-4000-8000-000000000002', '3b000000-0000-4000-8000-000000000004', 'submission', '7b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', 20000, 'open', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour'),
  ('9b000000-0000-4000-8000-000000000003', '3b000000-0000-4000-8000-000000000004', 'submission', '7b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', 40000, 'cancelled', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour'),
  ('9b000000-0000-4000-8000-000000000004', '3b000000-0000-4000-8000-000000000004', 'submission', '7b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', 80000, 'consumed', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour');

-- ไฟล์: a1 โจทย์ A · a2 เฉลย A · a3 เฉลย C · a4 โจทย์ D · a5/a6 งานส่งของสมาชิกใน b1 (a6 ยัง copying) · a7 ไม่มีใครอ้าง → deleting
insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ab000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000001', 'post', null, 'staging/t11/a1', 'sv-a1', 'files/t11/a1.pdf', 'application/pdf', 100, 'โจทย์.pdf'),
  ('ab000000-0000-4000-8000-000000000002', '3b000000-0000-4000-8000-000000000001', 'solution', null, 'staging/t11/a2', 'sv-a2', 'files/t11/a2.pdf', 'application/pdf', 200, 'เฉลย A.pdf'),
  ('ab000000-0000-4000-8000-000000000003', '3b000000-0000-4000-8000-000000000001', 'solution', null, 'staging/t11/a3', 'sv-a3', 'files/t11/a3.jpg', 'image/jpeg', 400, 'เฉลย C.jpg'),
  ('ab000000-0000-4000-8000-000000000004', '3b000000-0000-4000-8000-000000000002', 'post', null, 'staging/t11/a4', 'sv-a4', 'files/t11/a4.png', 'image/png', 800, 'โจทย์ D.png'),
  ('ab000000-0000-4000-8000-000000000005', '3b000000-0000-4000-8000-000000000004', 'submission', '9b000000-0000-4000-8000-000000000001', 'staging/t11/a5', 'sv-a5', 'files/t11/a5.jpg', 'image/jpeg', 1600, 'หน้า1.jpg'),
  ('ab000000-0000-4000-8000-000000000006', '3b000000-0000-4000-8000-000000000004', 'submission', '9b000000-0000-4000-8000-000000000001', 'staging/t11/a6', 'sv-a6', 'files/t11/a6.jpg', 'image/jpeg', 3200, 'หน้า2.jpg'),
  ('ab000000-0000-4000-8000-000000000007', '3b000000-0000-4000-8000-000000000001', 'post', null, 'staging/t11/a7', 'sv-a7', 'files/t11/a7.pdf', 'application/pdf', 6400, 'เก่า.pdf');
update public.assets
   set status = 'ready', version_id = 'v-' || right(id::text, 2), checksum = 'etag-' || right(id::text, 2), ready_at = clock_timestamp()
 where id in ('ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002', 'ab000000-0000-4000-8000-000000000003',
              'ab000000-0000-4000-8000-000000000004', 'ab000000-0000-4000-8000-000000000005', 'ab000000-0000-4000-8000-000000000007');
update public.assets set status = 'deleting', delete_requested_at = clock_timestamp()
 where id = 'ab000000-0000-4000-8000-000000000007';
insert into public.attachments (id, asset_id, post_id, solution_id, position) values
  ('cb000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', null, 1),
  ('cb000000-0000-4000-8000-000000000002', 'ab000000-0000-4000-8000-000000000002', null, '8b000000-0000-4000-8000-00000000000a', 1),
  ('cb000000-0000-4000-8000-000000000003', 'ab000000-0000-4000-8000-000000000003', null, '8b000000-0000-4000-8000-00000000000c', 1),
  ('cb000000-0000-4000-8000-000000000004', 'ab000000-0000-4000-8000-000000000004', '8b000000-0000-4000-8000-00000000000d', null, 1);

-- ---------------------------------------------------------------------------
-- ก: ยอดพื้นที่ที่ใช้
-- ---------------------------------------------------------------------------
-- ไฟล์ทุกสถานะ 100+200+400+800+1600+3200+6400 = 12,700 + b1 จอง 10,000 หักไฟล์ที่ complete แล้ว 4,800 = 5,200
select is(pg_temp.used_delta(), 17900::bigint,
  'ยอด = ไฟล์ทุกแถว (copying/ready/deleting รวมไฟล์ที่ไม่มีใครอ้าง) + ส่วนที่ batch เปิดอยู่ยังจอง (ไม่นับ batch หมดอายุ/ยกเลิก/ใช้แล้ว)');
update public.upload_batches set expires_at = clock_timestamp() - interval '1 second' where id = '9b000000-0000-4000-8000-000000000001';
select is(pg_temp.used_delta(), 12700::bigint, 'batch หมดอายุแล้วปล่อยพื้นที่ที่จองไว้ (ไฟล์ที่ complete แล้วยังนับ)');
update public.upload_batches set expires_at = clock_timestamp() + interval '1 hour', status = 'cancelled' where id = '9b000000-0000-4000-8000-000000000001';
select is(pg_temp.used_delta(), 12700::bigint, 'batch ที่ยกเลิกแล้วปล่อยพื้นที่ที่จองไว้');
update public.upload_batches set status = 'open', reserved_bytes = 4000 where id = '9b000000-0000-4000-8000-000000000001';
select is(pg_temp.used_delta(), 12700::bigint, 'ไฟล์ของ batch ใหญ่กว่าที่จองเหลือ: ไม่ติดลบ ไม่นับซ้ำ');
update public.upload_batches set reserved_bytes = 10000 where id = '9b000000-0000-4000-8000-000000000001';
delete from public.assets where id = 'ab000000-0000-4000-8000-000000000007';
select is(pg_temp.used_delta(), 11500::bigint, 'ไฟล์ deleting ที่ลบจาก B2 สำเร็จ (ลบแถว) เลิกนับ');

-- ---------------------------------------------------------------------------
-- ข: จองพื้นที่ (เทียบ quota − margin, ล็อกแถวตั้งค่า)
-- ---------------------------------------------------------------------------
update public.storage_settings set quota_bytes = private.storage_used_bytes() + hard_stop_margin_bytes + 1000;
select is(private.reserve_storage(1000), 0::bigint, 'จองได้พอดีเพดาน quota − margin');
insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, reserved_bytes, expires_at) values
  ('9b000000-0000-4000-8000-000000000006', '3b000000-0000-4000-8000-000000000001', 'post', '7b000000-0000-4000-8000-000000000001', 1000, clock_timestamp() + interval '1 hour');
select throws_ok($$ select private.reserve_storage(1) $$, 'P0001', 'storage_full',
  'เกินเพดาน (ยังเหลือ margin ก็ไม่ให้) → storage_full');
update public.upload_batches set status = 'cancelled' where id = '9b000000-0000-4000-8000-000000000006';
select is(private.reserve_storage(1), 999::bigint, 'ยกเลิก batch แล้วจองได้อีก (ปล่อยพื้นที่)');
select throws_ok($$ select private.reserve_storage(0) $$, 'P0001', 'invalid_size', 'จอง 0 ไบต์ไม่ได้');
select ok(pg_get_functiondef('private.reserve_storage(bigint)'::regprocedure)
            ~ 'from public\.storage_settings s where s\.singleton for update;\s+v_used := private\.storage_used_bytes\(\)',
  'ล็อกแถว storage_settings (FOR UPDATE) ก่อนนับยอด — ทดสอบสองคำขอพร้อมกันจริงแยกไว้ในโน้ต P3-01b');
update public.storage_settings set quota_bytes = 500000000;

-- ---------------------------------------------------------------------------
-- ฉ: สถานะ copying → ready → deleting เดินหน้าอย่างเดียว · final_key ไม่ซ้ำ · staging_version_id บังคับ
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, version_id, checksum, content_type, size_bytes, file_name, status, ready_at)
                    values ('3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/x', 'sv-x', 'files/t11/x.pdf', 'v-x', 'e-x', 'application/pdf', 10, 'x.pdf', 'ready', clock_timestamp()) $$,
  'P0001', 'invalid_status_transition', 'ไฟล์ใหม่ต้องเริ่มที่ copying (ไม่มีทางลัดเป็น ready)');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/x', 'sv-x', 'files/t11/a1.pdf', 'application/pdf', 10, 'x.pdf') $$,
  '23505', null, 'final_key ซ้ำไม่ได้');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/x', null, 'files/t11/x.pdf', 'application/pdf', 10, 'x.pdf') $$,
  '23502', null, 'ต้องมี staging_version_id');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/x', 'sv-x', 'files/t11/x.heic', 'image/heic', 10, 'x.heic') $$,
  '23514', null, 'รับเฉพาะ JPEG/PNG/PDF ที่ตรวจแล้ว (ไม่รับ HEIC ดิบ)');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3b000000-0000-4000-8000-000000000001', 'submission', '9b000000-0000-4000-8000-000000000001', 'staging/t11/x', 'sv-x', 'files/t11/x.jpg', 'image/jpeg', 10, 'x.jpg') $$,
  'P0001', 'batch_mismatch', 'ไฟล์ต้องเป็นของเจ้าของ batch และวัตถุประสงค์เดียวกัน');

insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ab000000-0000-4000-8000-000000000008', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/a8', 'sv-a8', 'files/t11/a8.pdf', 'application/pdf', 10, 'a8.pdf'),
  ('ab000000-0000-4000-8000-000000000009', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/a9', 'sv-a9', 'files/t11/a9.pdf', 'application/pdf', 10, 'a9.pdf'),
  ('ab000000-0000-4000-8000-000000000010', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/a10', 'sv-a10', 'files/t11/a10.pdf', 'application/pdf', 10, 'a10.pdf');
select throws_ok($$ update public.assets set status = 'ready', ready_at = clock_timestamp() where id = 'ab000000-0000-4000-8000-000000000008' $$,
  '23514', null, 'ready ต้องมี version_id และ checksum');
select lives_ok($$ update public.assets set status = 'ready', version_id = 'v-a8', checksum = 'etag-a8', ready_at = clock_timestamp()
                    where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'copying → ready พร้อม version_id ปลายทางและ checksum');
select throws_ok($$ update public.assets set status = 'copying' where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'invalid_status_transition', 'ready → copying ไม่ได้');
select throws_ok($$ update public.assets set version_id = 'v-other' where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'immutable_field', 'พ้น copying แล้วเปลี่ยน version_id ไม่ได้');
select throws_ok($$ update public.assets set final_key = 'files/t11/other.pdf' where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'immutable_field', 'final_key เปลี่ยนไม่ได้');
select throws_ok($$ update public.assets set size_bytes = 1 where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'immutable_field', 'ขนาดไฟล์เปลี่ยนไม่ได้ (กันยอดพื้นที่ถูกแก้)');
select throws_ok($$ delete from public.assets where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'asset_not_deletable', 'ลบแถว ready ตรง ๆ ไม่ได้ (ต้องผ่าน deleting ไม่งั้นไฟล์ค้างใน B2 โดยไม่ถูกนับ)');
select throws_ok($$ update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = 'ab000000-0000-4000-8000-000000000001' $$,
  'P0001', 'asset_attached', 'ไฟล์ที่ยังผูกกับโจทย์เข้าคิวลบไม่ได้');
select lives_ok($$ update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'ready → deleting เมื่อไม่มีใครอ้าง');
select throws_ok($$ update public.assets set status = 'ready' where id = 'ab000000-0000-4000-8000-000000000008' $$,
  'P0001', 'invalid_status_transition', 'deleting → ready ไม่ได้');
select throws_ok($$ update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where id = 'ab000000-0000-4000-8000-000000000009' $$,
  '23514', null, 'copying → deleting ต้องรู้ version_id ปลายทาง (ลบแบบระบุเวอร์ชัน)');
select lives_ok($$ update public.assets set status = 'deleting', version_id = 'v-a9', delete_requested_at = clock_timestamp() where id = 'ab000000-0000-4000-8000-000000000009' $$,
  'sweeper: copying ค้างที่ปลายทางมีไฟล์แล้ว → deleting พร้อม version_id');
select lives_ok($$ delete from public.assets where id in ('ab000000-0000-4000-8000-000000000008', 'ab000000-0000-4000-8000-000000000009') $$,
  'ลบแถว deleting ได้เมื่อลบจาก B2 สำเร็จ');
select lives_ok($$ delete from public.assets where id = 'ab000000-0000-4000-8000-000000000010' $$,
  'sweeper: copying ค้างที่ปลายทางไม่มีไฟล์ → ลบแถวได้');

-- ---------------------------------------------------------------------------
-- ง: การผูกไฟล์ — เป้าหมายเดียว ตรงวัตถุประสงค์ ไฟล์พร้อมใช้ ลำดับไม่ซ้ำ
-- ---------------------------------------------------------------------------
insert into public.assets (id, owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name) values
  ('ab000000-0000-4000-8000-000000000011', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/a11', 'sv-a11', 'files/t11/a11.pdf', 'application/pdf', 10, 'a11.pdf'),
  ('ab000000-0000-4000-8000-000000000012', '3b000000-0000-4000-8000-000000000001', 'solution', 'staging/t11/a12', 'sv-a12', 'files/t11/a12.pdf', 'application/pdf', 10, 'a12.pdf'),
  ('ab000000-0000-4000-8000-000000000013', '3b000000-0000-4000-8000-000000000001', 'post', 'staging/t11/a13', 'sv-a13', 'files/t11/a13.pdf', 'application/pdf', 10, 'a13.pdf');
update public.assets set status = 'ready', version_id = 'v-x', checksum = 'etag-x', ready_at = clock_timestamp()
 where id in ('ab000000-0000-4000-8000-000000000012', 'ab000000-0000-4000-8000-000000000013');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000011', '8b000000-0000-4000-8000-00000000000a', 5) $$,
  'P0001', 'asset_not_ready', 'ผูกไฟล์ที่ยัง copying ไม่ได้');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000012', '8b000000-0000-4000-8000-00000000000a', 5) $$,
  'P0001', 'attachment_purpose_mismatch', 'ไฟล์เฉลยผูกกับโจทย์ไม่ได้ (วัตถุประสงค์ต้องตรงเป้าหมาย)');
select throws_ok($$ insert into public.attachments (asset_id, post_id, solution_id, position) values ('ab000000-0000-4000-8000-000000000013', '8b000000-0000-4000-8000-00000000000a', '8b000000-0000-4000-8000-00000000000a', 5) $$,
  '23514', null, 'ผูกสองเป้าหมายพร้อมกันไม่ได้');
select throws_ok($$ insert into public.attachments (asset_id, position) values ('ab000000-0000-4000-8000-000000000013', 5) $$,
  '23514', null, 'ต้องมีเป้าหมายหนึ่งอย่าง');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000013', '8b000000-0000-4000-8000-00000000000a', 11) $$,
  '23514', null, 'โจทย์ผูกได้ไม่เกิน 10 ไฟล์ (ลำดับ 1–10)');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000013', '8b000000-0000-4000-8000-00000000000a', 1) $$,
  '23505', null, 'ลำดับซ้ำในโพสต์เดียวกันไม่ได้');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000c', 1) $$,
  '23505', null, 'ไฟล์หนึ่งชิ้นผูกได้ที่เดียว');
select lives_ok($$ insert into public.attachments (id, asset_id, post_id, position) values ('cb000000-0000-4000-8000-000000000013', 'ab000000-0000-4000-8000-000000000013', '8b000000-0000-4000-8000-00000000000a', 2) $$,
  'ผูกไฟล์โจทย์ที่พร้อมใช้กับโจทย์ได้');
select throws_ok($$ update public.attachments set post_id = '8b000000-0000-4000-8000-00000000000c' where id = 'cb000000-0000-4000-8000-000000000013' $$,
  'P0001', 'immutable_field', 'ย้ายไฟล์ไปเป้าหมายอื่นไม่ได้');
select throws_ok($$ update public.attachments set asset_id = 'ab000000-0000-4000-8000-000000000012' where id = 'cb000000-0000-4000-8000-000000000013' $$,
  'P0001', 'immutable_field', 'เปลี่ยนไฟล์ของแถวผูกไม่ได้');
select lives_ok($$ update public.attachments set position = 3 where id = 'cb000000-0000-4000-8000-000000000013' $$,
  'เปลี่ยนลำดับได้');

-- ---------------------------------------------------------------------------
-- จ: RLS อ่าน
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select id from public.assets $$, '42501', null, 'anon อ่าน assets ไม่ได้');
select throws_ok($$ select * from public.attachments $$, '42501', null, 'anon อ่าน attachments ไม่ได้');

set local role authenticated;
-- สมาชิกห้อง 1
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select set_eq($$ select asset_id from public.attachments $$,
  array['ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000003', 'ab000000-0000-4000-8000-000000000013']::uuid[],
  'สมาชิกเห็นไฟล์โจทย์ของห้องตัวเองและไฟล์เฉลยที่เผยแพร่แล้ว (ไม่เห็นเฉลยที่ยังไม่เผยแพร่ หรือห้องอื่น)');
select set_eq($$ select id from public.assets $$,
  array['ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000003', 'ab000000-0000-4000-8000-000000000013',
        'ab000000-0000-4000-8000-000000000005', 'ab000000-0000-4000-8000-000000000006']::uuid[],
  'สมาชิกเห็น asset ที่ผูกกับสิ่งที่ตนอ่านได้ + ไฟล์ที่ตนอัปโหลดเอง');
select throws_ok($$ select final_key from public.assets $$, '42501', null, 'นักเรียนอ่าน final_key ไม่ได้');
select throws_ok($$ select version_id from public.assets $$, '42501', null, 'นักเรียนอ่าน version_id ไม่ได้');
select set_eq($$ select id from public.upload_batches $$,
  array['9b000000-0000-4000-8000-000000000001', '9b000000-0000-4000-8000-000000000002',
        '9b000000-0000-4000-8000-000000000003', '9b000000-0000-4000-8000-000000000004']::uuid[],
  'upload_batches: เห็นเฉพาะของตัวเอง');
select is_empty($$ select singleton from public.storage_settings $$, 'นักเรียนไม่เห็นค่าตั้งพื้นที่');

-- คนนอกห้อง (สมาชิกห้อง 2)
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select set_eq($$ select asset_id from public.attachments $$, array['ab000000-0000-4000-8000-000000000004']::uuid[],
  'คนนอกห้องไม่เห็นไฟล์โจทย์/เฉลยของห้อง 1');
select set_eq($$ select id from public.assets $$, array['ab000000-0000-4000-8000-000000000004']::uuid[],
  'คนนอกห้องไม่เห็น asset ของห้อง 1');
select is_empty($$ select id from public.upload_batches $$, 'คนนอกห้องไม่เห็น batch ของคนอื่น');

-- บัญชีนักเรียนที่ยังไม่ผูกชื่อ
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000007", "role": "authenticated"}';
select is_empty($$ select asset_id from public.attachments union all select id from public.assets $$,
  'ยังไม่ผูกชื่อ: ไม่เห็นไฟล์ใด');

-- ครูเจ้าของห้อง 1
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select set_eq($$ select asset_id from public.attachments $$,
  array['ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002',
        'ab000000-0000-4000-8000-000000000003', 'ab000000-0000-4000-8000-000000000013']::uuid[],
  'ครูเห็นไฟล์โจทย์และเฉลย (รวมที่ยังไม่เผยแพร่) ของห้องตัวเองเท่านั้น');
select set_eq($$ select id from public.assets $$,
  array['ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002', 'ab000000-0000-4000-8000-000000000003',
        'ab000000-0000-4000-8000-000000000011', 'ab000000-0000-4000-8000-000000000012', 'ab000000-0000-4000-8000-000000000013']::uuid[],
  'ครูเห็น asset ของห้องตัวเอง + ที่ตนอัปโหลด (ไม่เห็นงานส่งที่ยังไม่ผูก — กลุ่ม submissions เพิ่มสิทธิ์ครูของห้อง)');
select is((select count(*)::integer from public.storage_settings), 1, 'ครูเห็นค่าตั้งพื้นที่');
select set_eq($$ select id from public.upload_batches $$, array['9b000000-0000-4000-8000-000000000006']::uuid[],
  'ครูเห็นเฉพาะ batch ของตัวเอง');
-- ครูห้อง 2
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select set_eq($$ select asset_id from public.attachments $$, array['ab000000-0000-4000-8000-000000000004']::uuid[],
  'ครูอีกคนไม่เห็นไฟล์ของห้องที่ไม่ได้สอน');
-- ผู้ดูแล (อ่านได้โดยไม่ต้องอยู่ในโหมดผู้ดูแล — การเขียนตรวจโหมดใน RPC)
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select is((select count(*)::integer from public.attachments where id::text like 'cb000000-%'), 5, 'ผู้ดูแลเห็นไฟล์ทุกห้อง');
select is((select count(*)::integer from public.storage_settings), 1, 'ผู้ดูแลเห็นค่าตั้งพื้นที่');

-- นักเรียนที่ถูกเอาออก: เห็นระหว่างเป็นสมาชิก แล้วไม่เห็นทันทีหลังครูเอาออก
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is((select count(*)::integer from public.attachments), 3, 'ก่อนถูกเอาออก: เห็นไฟล์โจทย์และเฉลยที่เผยแพร่ของห้อง 1');
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select lives_ok($$ select public.remove_member('7b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000003') $$,
  'ครูเอานักเรียนออกจากห้อง 1');
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000006", "role": "authenticated"}';
select is_empty($$ select asset_id from public.attachments union all select id from public.assets $$,
  'ถูกเอาออกแล้ว: ไม่เห็นไฟล์โจทย์หรือเฉลย (รวมที่เผยแพร่แล้ว) ทันที');

-- เขียนตรงไม่ได้ (ผ่าน RPC/Edge Function เท่านั้น)
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000005', '8b000000-0000-4000-8000-00000000000a', 9) $$,
  '42501', null, 'นักเรียนเพิ่ม attachments ตรงไม่ได้');
select throws_ok($$ update public.attachments set position = 9 where id = 'cb000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'นักเรียนแก้ attachments ตรงไม่ได้');
select throws_ok($$ delete from public.attachments where id = 'cb000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'นักเรียนลบ attachments ตรงไม่ได้');
select throws_ok($$ insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
                    values ('3b000000-0000-4000-8000-000000000004', 'submission', 'staging/t11/s', 'sv-s', 'files/t11/s.jpg', 'image/jpeg', 10, 's.jpg') $$,
  '42501', null, 'นักเรียนเพิ่ม assets ตรงไม่ได้');
select throws_ok($$ update public.assets set file_name = 'x.jpg' where id = 'ab000000-0000-4000-8000-000000000005' $$,
  '42501', null, 'นักเรียนแก้ assets ตรงไม่ได้ (แม้เป็นไฟล์ของตัวเอง)');
select throws_ok($$ delete from public.assets where id = 'ab000000-0000-4000-8000-000000000006' $$,
  '42501', null, 'นักเรียนลบ assets ตรงไม่ได้');
select throws_ok($$ insert into public.upload_batches (owner_account_id, purpose, classroom_id, post_id, reserved_bytes, expires_at)
                    values ('3b000000-0000-4000-8000-000000000004', 'submission', '7b000000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-00000000000a', 1, clock_timestamp() + interval '1 hour') $$,
  '42501', null, 'นักเรียนสร้าง upload_batches ตรงไม่ได้ (ต้องผ่านการจองพื้นที่)');
select throws_ok($$ update public.upload_batches set reserved_bytes = 0 where id = '9b000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'นักเรียนแก้ upload_batches ตรงไม่ได้');
select throws_ok($$ update public.storage_settings set quota_bytes = 10000000000000 $$,
  '42501', null, 'นักเรียนแก้ค่าตั้งพื้นที่ไม่ได้');
set local request.jwt.claims to '{"sub": "2b000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ update public.storage_settings set quota_bytes = 10000000000000 $$,
  '42501', null, 'ครูก็แก้ค่าตั้งพื้นที่ตรงไม่ได้');
select throws_ok($$ insert into public.attachments (asset_id, post_id, position) values ('ab000000-0000-4000-8000-000000000011', '8b000000-0000-4000-8000-00000000000a', 9) $$,
  '42501', null, 'ครูก็เพิ่ม attachments ตรงไม่ได้ (ต้องผ่าน RPC)');

-- ---------------------------------------------------------------------------
-- ค: ลบโพสต์ที่มีไฟล์ — แถวผูกหายตาม แต่ asset อยู่ต่อและยังนับพื้นที่
-- ---------------------------------------------------------------------------
set local role postgres;
-- ปิด batch ที่ยังเปิดก่อน เพื่อให้ส่วนต่างเหลือเฉพาะไฟล์ (batch ของโพสต์ที่ถูกลบหายตามและคืนพื้นที่ที่จอง — ทดสอบท้ายส่วนนี้)
update public.upload_batches set status = 'consumed' where id = '9b000000-0000-4000-8000-000000000001';
create temp table before_delete on commit drop as select pg_temp.used_delta() as used;
delete from public.posts where id = '8b000000-0000-4000-8000-00000000000a';
select is_empty($$ select id from public.attachments where post_id = '8b000000-0000-4000-8000-00000000000a'
                     or solution_id = '8b000000-0000-4000-8000-00000000000a' $$,
  'ลบโพสต์แล้วแถวผูกของโจทย์และเฉลยหายตาม');
select results_eq(
  $$ select id, status from public.assets
      where id in ('ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002', 'ab000000-0000-4000-8000-000000000013')
      order by id $$,
  $$ values ('ab000000-0000-4000-8000-000000000001'::uuid, 'ready'), ('ab000000-0000-4000-8000-000000000002'::uuid, 'ready'),
            ('ab000000-0000-4000-8000-000000000013'::uuid, 'ready') $$,
  'asset (final_key + version_id) ของโจทย์และเฉลยไม่หายตาม cascade');
select is(pg_temp.used_delta(), (select used from before_delete), 'ไฟล์ที่ไม่มีใครอ้างแล้วยังนับพื้นที่จนเข้าคิวลบ B2');
select lives_ok($$ update public.assets set status = 'deleting', delete_requested_at = clock_timestamp()
                    where id in ('ab000000-0000-4000-8000-000000000001', 'ab000000-0000-4000-8000-000000000002', 'ab000000-0000-4000-8000-000000000013') $$,
  'หลังเลิกผูกแล้วเข้าคิวลบ (deleting) ได้');
select is_empty($$ select id from public.upload_batches where post_id = '8b000000-0000-4000-8000-00000000000a' $$,
  'batch ของโพสต์ที่ถูกลบหายตาม (ปล่อยพื้นที่ที่จอง)');
select is((select upload_batch_id from public.assets where id = 'ab000000-0000-4000-8000-000000000005'), null::uuid,
  'ไฟล์ของ batch ที่หายไปยังอยู่ (upload_batch_id เป็น null)');

select * from finish();
rollback;
