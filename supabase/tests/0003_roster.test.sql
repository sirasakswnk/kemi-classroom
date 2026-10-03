-- ทดสอบ 0003_roster: สิทธิ์อ่านรายชื่อ, ตรวจ/เทียบ/บันทึกการนำเข้า, กันคำขอซ้ำ
-- ข้อมูลสมมติทั้งหมด (เลขประจำตัว 0?666xxxxx ไม่ชนไฟล์ sample-roster ที่อาจนำเข้าไว้บน kemi-dev) และ rollback ตอนจบ
-- การนับ/รายการนักเรียนกรองเฉพาะเลขชุดนี้ เพื่อให้ผลไม่ขึ้นกับข้อมูลทดสอบที่มีอยู่แล้วบน kemi-dev
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

-- ให้เรียก pgTAP ได้ขณะสลับเป็น anon/authenticated (ย้อนเมื่อ rollback)
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

select plan(47);

-- ---------------------------------------------------------------------------
-- A. โครงสร้างและสิทธิ์
-- ---------------------------------------------------------------------------
select has_table('public', 'terms', 'มี public.terms');
select has_table('public', 'term_control', 'มี public.term_control');
select has_table('public', 'students', 'มี public.students');
select has_table('public', 'roster_entries', 'มี public.roster_entries');
select policies_are('public', 'students', array['students_select'], 'students มีเฉพาะ policy อ่าน');
select policies_are('public', 'roster_entries', array['roster_entries_select'], 'roster_entries มีเฉพาะ policy อ่าน');
select ok(has_function_privilege('authenticated', 'private.is_teacher_or_admin()', 'EXECUTE'),
  'authenticated มี EXECUTE บน private.is_teacher_or_admin() (ให้ policy ใช้)');
select is_empty(
  $$ select f from unnest(array[
       'public.preview_roster_import(text,jsonb,boolean)',
       'public.commit_roster_import(text,jsonb,uuid,boolean)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon เรียก RPC นำเข้าไม่ได้'
);
select ok(
  has_function_privilege('authenticated', 'public.preview_roster_import(text,jsonb,boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.commit_roster_import(text,jsonb,uuid,boolean)', 'EXECUTE'),
  'authenticated เรียก RPC นำเข้าได้ (ตรวจสิทธิ์ครูภายใน)'
);
select is_empty(
  $$ select f from unnest(array[
       'private.roster_import_plan(text,jsonb)',
       'private.receipt_lookup(uuid,uuid,text)',
       'private.receipt_store(uuid,uuid,text,jsonb)']) f
      where has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'authenticated เรียกฟังก์ชันช่วยภายในของการนำเข้าไม่ได้'
);
select ok((select condeferrable from pg_constraint where conname = 'roster_entries_group_roll_key'),
  'เลขที่ไม่ซ้ำในห้องตรวจตอนจบ transaction ได้ (สลับเลขที่ตอนนำเข้าซ้ำ)');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ภาคเรียน บัญชี และชุดรายชื่อ
-- ---------------------------------------------------------------------------
insert into public.terms (id, name) values ('40000000-0000-4000-8000-000000000001', 'ภาคเรียนทดสอบ');
insert into public.term_control (term_id) values ('40000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id;

insert into public.teachers (id, display_name) values ('10000000-0000-4000-8000-000000000001', 'ครูทดสอบ');
insert into public.accounts (id, auth_user_id, provider, provider_subject, role, teacher_id) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'google', 'g-teacher', 'teacher', '10000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'google', 'g-student', 'student', null),
  ('30000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003', 'google', 'g-admin', 'admin', null),
  ('30000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000004', 'google', 'g-outsider', 'student', null);

create temp table payloads (name text primary key, rows jsonb not null);
grant select on payloads to authenticated;
insert into payloads values
  -- ข้อผิดพลาดครบทุกชนิดต่อแถว
  ('err', '[
     {"row": 3,  "roll_number": 1, "student_code": "66600001", "first_name": "ก", "last_name": "ข"},
     {"row": 4,  "roll_number": 2, "student_code": "06660002", "first_name": "ค", "last_name": "ง"},
     {"row": 5,  "roll_number": 3, "student_code": "66600003", "first_name": "",  "last_name": "ว่าง"},
     {"row": 6,  "roll_number": 3, "student_code": "66600004", "first_name": "จ", "last_name": "ฉ"},
     {"row": 7,  "roll_number": 5, "student_code": "66600001", "first_name": "ช", "last_name": "ซ"},
     {"row": 8,  "roll_number": 6, "student_code": "",      "first_name": "ฌ", "last_name": "ญ"},
     {"row": 9,  "roll_number": 7, "student_code": 66600007,   "first_name": "ฎ", "last_name": "ฏ"},
     {"row": 10, "roll_number": 8, "student_code": "9x008", "first_name": "ฐ", "last_name": "ฑ"},
     {"row": 11,                   "student_code": "66600009", "first_name": "ฒ", "last_name": "ณ"},
     {"row": 12, "roll_number": 0, "student_code": "66600010", "first_name": "ด", "last_name": "ต"}
   ]'),
  -- นำเข้าครั้งแรก: ศูนย์นำหน้า ช่องว่างหัวท้าย และช่องว่างกลางนามสกุล
  ('ok', '[
     {"row": 3, "roll_number": 1, "student_code": "66600001", "name_prefix": "นาย",    "first_name": " สมชาย", "last_name": "ใจดี "},
     {"row": 4, "roll_number": 2, "student_code": "06660002", "name_prefix": "นางสาว", "first_name": "สมหญิง", "last_name": "อิ นทร์แก้ว"},
     {"row": 5, "roll_number": 3, "student_code": "66600003",                          "first_name": "มานี",   "last_name": "มีนา"}
   ]'),
  ('ok_changed', '[
     {"row": 3, "roll_number": 1, "student_code": "66600001", "name_prefix": "นาย", "first_name": "สมชาย", "last_name": "ใจดี"}
   ]'),
  -- นำเข้าซ้ำ: เปลี่ยนชื่อ สลับเลขที่ 1↔2 เพิ่มคนใหม่ และไม่มี 66600003 ในไฟล์
  ('reimport', '[
     {"row": 3, "roll_number": 2, "student_code": "66600001", "name_prefix": "นาย",    "first_name": "สมชาย",  "last_name": "ใจดีมาก"},
     {"row": 4, "roll_number": 1, "student_code": "06660002", "name_prefix": "นางสาว", "first_name": "สมหญิง", "last_name": "อิ นทร์แก้ว"},
     {"row": 5, "roll_number": 4, "student_code": "66600005", "name_prefix": "นาย",    "first_name": "ปิติ",    "last_name": "ยินดี"}
   ]'),
  ('moved', '[{"roll_number": 1, "student_code": "66600003", "first_name": "มานี", "last_name": "มีนา"}]'),
  ('taken', '[{"roll_number": 3, "student_code": "66600006", "first_name": "ชูใจ", "last_name": "ใจงาม"}]');

-- ---------------------------------------------------------------------------
-- B. ใครเรียกได้
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.preview_roster_import('5/2', (select rows from payloads where name = 'ok')) $$,
  'P0001', 'forbidden', 'นักเรียนดูตัวอย่างการนำเข้าไม่ได้');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.preview_roster_import('5/2', (select rows from payloads where name = 'ok')) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลถูกปฏิเสธ');
select lives_ok($$ select public.preview_roster_import('5/2', (select rows from payloads where name = 'ok'), true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลดูตัวอย่างได้');
set local role anon;
select throws_ok($$ select public.preview_roster_import('5/2', '[]'::jsonb) $$, '42501', null, 'anon เรียกไม่ได้');
set local role authenticated;
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.commit_roster_import('5/2', (select rows from payloads where name = 'ok'), null) $$,
  'P0001', 'request_key_required', 'ยืนยันนำเข้าต้องมี request key');

-- ---------------------------------------------------------------------------
-- C. ตรวจข้อผิดพลาดรายแถว (ครู)
-- ---------------------------------------------------------------------------
select is(
  (select v -> 'counts' -> 'errors' from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'err')) v) s),
  '9'::jsonb, 'พบแถวผิด 9 แถว (แถวเลขประจำตัว 06660002 ถูกต้อง)'
);
select is(
  (select jsonb_agg(x -> 'errors' order by (x ->> 'index')::int)
     from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'err')) v) s,
          jsonb_array_elements(s.v -> 'rows') x),
  '[["code_duplicate"], [], ["name_required", "roll_duplicate"], ["roll_duplicate"], ["code_duplicate"],
    ["code_required"], ["code_invalid"], ["code_invalid"], ["roll_required"], ["roll_invalid"]]'::jsonb,
  'ข้อผิดพลาดรายแถวครบ: รหัสซ้ำ ชื่อว่าง เลขที่ซ้ำ รหัสว่าง รหัสไม่ใช่ข้อความ/ไม่ใช่ตัวเลข เลขที่ว่าง/ผิด'
);
select is(
  (select v -> 'rows' -> 1 ->> 'student_code' from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'err')) v) s),
  '06660002', 'เลขประจำตัวที่มีศูนย์นำหน้าคงไว้เป็นข้อความ'
);
select is(
  (select (v ->> 'ok') || ' ' || (v -> 'term' ->> 'name') || ' ' || (v ->> 'group_name')
     from (select public.preview_roster_import(' 5/2 ', (select rows from payloads where name = 'err')) v) s),
  'false ภาคเรียนทดสอบ 5/2', 'ตัวอย่างบอกภาคเรียนและห้อง (ตัดช่องว่าง) และไม่ผ่านเมื่อมีแถวผิด'
);
select is((select count(*)::int from public.students where student_code ~ '^0?666'), 0, 'ดูตัวอย่างไม่เขียนข้อมูล');

-- ---------------------------------------------------------------------------
-- D. ยืนยันนำเข้าครั้งแรก + กันคำขอซ้ำ
-- ---------------------------------------------------------------------------
select is(
  (select (v ->> 'committed') || ' new=' || (v -> 'counts' ->> 'new')
     from (select public.commit_roster_import('5/2', (select rows from payloads where name = 'ok'),
                  '50000000-0000-4000-8000-000000000001') v) s),
  'true new=3', 'นำเข้า 3 คนสำเร็จ'
);
select results_eq(
  $$ select student_code, coalesce(name_prefix, '-'), display_name from public.students where student_code ~ '^0?666' order by student_code $$,
  $$ values ('06660002', 'นางสาว', 'สมหญิง อิ นทร์แก้ว'), ('66600001', 'นาย', 'สมชาย ใจดี'), ('66600003', '-', 'มานี มีนา') $$,
  'เก็บศูนย์นำหน้า ตัดช่องว่างหัวท้าย ต่อชื่อ-นามสกุลด้วยช่องว่าง 1 ช่อง และคงช่องว่างกลางนามสกุล'
);
select results_eq(
  $$ select s.student_code, e.group_name, e.roll_number from public.roster_entries e
       join public.students s on s.id = e.student_id where s.student_code ~ '^0?666' order by e.roll_number $$,
  $$ values ('66600001', '5/2', 1), ('06660002', '5/2', 2), ('66600003', '5/2', 3) $$,
  'รายชื่อห้อง 5/2 ของภาคเรียนปัจจุบันพร้อมเลขที่'
);
-- คำขอซ้ำ key เดิม: ได้ผลเดิม (new=3 ไม่ใช่ unchanged) และไม่สร้างซ้ำ
select is(
  (select (v ->> 'committed') || ' new=' || (v -> 'counts' ->> 'new')
     from (select public.commit_roster_import('5/2', (select rows from payloads where name = 'ok'),
                  '50000000-0000-4000-8000-000000000001') v) s),
  'true new=3', 'คำขอซ้ำด้วย request key เดิมคืนผลเดิม'
);
select is((select count(*)::int from public.students where student_code ~ '^0?666'), 3, 'คำขอซ้ำไม่สร้างนักเรียนซ้ำ');
select throws_ok(
  $$ select public.commit_roster_import('5/2', (select rows from payloads where name = 'ok_changed'),
                                        '50000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่เนื้อหาต่างถูกปฏิเสธ'
);
select is(
  (select (v ->> 'committed') || ' ' || (v ->> 'ok')
     from (select public.commit_roster_import('5/2', (select rows from payloads where name = 'err'),
                  '50000000-0000-4000-8000-000000000002') v) s),
  'false false', 'มีแถวผิด = ไม่บันทึกอะไรเลย'
);
select is((select count(*)::int from public.students where student_code ~ '^0?666'), 3, 'ชุดที่ผิดไม่เพิ่มนักเรียนแม้มีแถวที่ถูก');

-- ---------------------------------------------------------------------------
-- E. นำเข้าซ้ำ: แสดงการเปลี่ยนแปลง ไม่ลบคนที่หาย ไม่แตะการผูกบัญชี
-- ---------------------------------------------------------------------------
set local role postgres;
update public.students set account_id = '30000000-0000-4000-8000-000000000002' where student_code = '66600001';
set local role authenticated;
select is(
  (select jsonb_agg(jsonb_build_object('s', x -> 'status', 'c', x -> 'changes', 'b', x -> 'bound') order by (x ->> 'index')::int)
     from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'reimport')) v) s,
          jsonb_array_elements(s.v -> 'rows') x),
  '[{"s": "updated", "c": ["display_name", "roll_number"], "b": true},
    {"s": "updated", "c": ["roll_number"], "b": false},
    {"s": "new", "c": [], "b": false}]'::jsonb,
  'ตัวอย่างนำเข้าซ้ำบอกสิ่งที่เปลี่ยนรายแถว และบอกว่าผูกบัญชีแล้ว'
);
select is(
  (select v -> 'missing' from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'reimport')) v) s),
  '[{"student_code": "66600003", "display_name": "มานี มีนา", "roll_number": 3, "bound": false}]'::jsonb,
  'คนที่อยู่ในห้องแต่ไม่อยู่ในไฟล์ถูกแจ้ง'
);
select is(
  (select v ->> 'committed' from (select public.commit_roster_import('5/2', (select rows from payloads where name = 'reimport'),
                  '50000000-0000-4000-8000-000000000003') v) s),
  'true', 'บันทึกการนำเข้าซ้ำที่สลับเลขที่ 1↔2 ได้'
);
select results_eq(
  $$ select s.student_code, s.display_name, e.roll_number from public.roster_entries e
       join public.students s on s.id = e.student_id where e.group_name = '5/2' order by e.roll_number $$,
  $$ values ('06660002', 'สมหญิง อิ นทร์แก้ว', 1), ('66600001', 'สมชาย ใจดีมาก', 2), ('66600003', 'มานี มีนา', 3), ('66600005', 'ปิติ ยินดี', 4) $$,
  'ชื่อและเลขที่อัปเดต คนที่หายจากไฟล์ยังอยู่ และคนใหม่ถูกเพิ่ม'
);
set local role postgres;
select is((select account_id from public.students where student_code = '66600001'),
  '30000000-0000-4000-8000-000000000002'::uuid, 'การนำเข้าไม่แตะการผูกบัญชี');
set local role authenticated;

-- ---------------------------------------------------------------------------
-- F. ย้ายห้อง เลขที่ชนกับคนที่ไม่อยู่ในไฟล์ และขอบเขตของชุดข้อมูล
-- ---------------------------------------------------------------------------
select is(
  (select (x ->> 'status') || ' จาก ' || (x ->> 'from_group')
     from (select public.preview_roster_import('5/3', (select rows from payloads where name = 'moved')) v) s,
          jsonb_array_elements(s.v -> 'rows') x),
  'moved จาก 5/2', 'นักเรียนที่มีในห้องอื่นของเทอมนี้แสดงเป็นย้ายห้อง'
);
select is(
  (select x -> 'errors' from (select public.preview_roster_import('5/2', (select rows from payloads where name = 'taken')) v) s,
          jsonb_array_elements(s.v -> 'rows') x),
  '["roll_taken"]'::jsonb, 'เลขที่ที่เป็นของคนในห้องที่ไม่อยู่ในไฟล์ถูกแจ้งเป็นข้อผิดพลาด'
);
select is(
  (select v -> 'errors' from (select public.preview_roster_import('5/2', '[]'::jsonb) v) s),
  '["rows_count"]'::jsonb, 'ไฟล์ว่างถูกปฏิเสธ'
);
select is(
  (select v -> 'errors' from (select public.preview_roster_import('  ', (select rows from payloads where name = 'ok')) v) s),
  '["group_invalid"]'::jsonb, 'ต้องระบุห้อง'
);
select is(
  (select v -> 'errors' from (select public.preview_roster_import('5/2',
     (select jsonb_agg(jsonb_build_object('roll_number', g, 'student_code', (66610000 + g)::text, 'first_name', 'ก', 'last_name', 'ข'))
        from generate_series(1, 301) g)) v) s),
  '["rows_count"]'::jsonb, 'เกิน 300 แถวถูกปฏิเสธ'
);

-- ---------------------------------------------------------------------------
-- G. สิทธิ์อ่านผ่าน RLS (policy เรียกฟังก์ชันใน private ได้โดยไม่มี USAGE)
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.students where student_code ~ '^0?666'), 4, 'ครูเห็นนักเรียนทุกคน');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select results_eq($$ select student_code from public.students $$, $$ values ('66600001') $$,
  'นักเรียนเห็นเฉพาะแถวของตัวเอง');
select results_eq($$ select group_name, roll_number from public.roster_entries $$, $$ values ('5/2', 2) $$,
  'นักเรียนเห็นเฉพาะห้องและเลขที่ของตัวเอง');
select ok((select count(*) from public.terms) >= 1, 'นักเรียนเห็นชื่อภาคเรียน');
select throws_ok('select private.is_teacher_or_admin()', '42501', 'permission denied for schema private',
  'เรียกฟังก์ชันช่วยใน private ตรงไม่ได้');
select throws_ok($$ insert into public.students (student_code, display_name) values ('99999', 'ปลอม ตัว') $$,
  '42501', null, 'เขียนตาราง students ตรงไม่ได้');
set local request.jwt.claims to '{"sub": "20000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select is((select count(*)::int from public.students), 0, 'บัญชีที่ยังไม่ผูกชื่อไม่เห็นรายชื่อใคร');
select is((select count(*)::int from public.roster_entries), 0, 'บัญชีที่ยังไม่ผูกชื่อไม่เห็นรายชื่อห้อง');

set local role postgres;
select * from finish();
rollback;
