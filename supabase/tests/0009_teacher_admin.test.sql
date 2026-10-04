-- ทดสอบ 0009_teacher_admin + กติกาโหมดผู้ดูแล (L6) ของ RPC ฝั่งครูทุกตัว
-- ข้อมูลสมมติทั้งหมด (อีเมล @example.com) และ rollback ตอนจบ
-- หมายเหตุ: ข้อ “เอาครูคนสุดท้ายออกไม่ได้” ต้องให้เหลือแถวที่ใช้งานแถวเดียว จึงตั้ง revoked_at ให้แถวอื่น
-- (รวมรายการจริงบน kemi-dev) ชั่วคราวภายใน transaction นี้ — ย้อนทั้งหมดเมื่อ rollback ไม่มีอะไรถูกบันทึก
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

select plan(27);

-- ---------------------------------------------------------------------------
-- A. สิทธิ์
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select f from unnest(array['public.admin_teachers()', 'public.admin_add_teacher(text,uuid,text)',
                                'public.admin_remove_teacher(uuid)']) f
      where has_function_privilege('anon', f, 'EXECUTE') $$,
  'anon เรียก RPC บัญชีครูไม่ได้');
select ok(
  (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE'))
     from unnest(array['public.admin_teachers()', 'public.admin_add_teacher(text,uuid,text)',
                       'public.admin_remove_teacher(uuid)']) f),
  'authenticated เรียกได้ (ตรวจผู้ดูแลภายใน)');
-- RPC ที่ตรวจสิทธิ์ครูทุกตัวต้องรับ p_admin_mode (ผู้ดูแลต้องส่งเมื่อทำแทนครู)
select is_empty(
  $$ select p.oid::regprocedure::text from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.prosrc ~ 'private\.require_(classroom_)?teacher\('
        and not ('p_admin_mode' = any(coalesce(p.proargnames, '{}'))) $$,
  'RPC ฝั่งครูทุกตัวมีพารามิเตอร์ p_admin_mode');

-- ---------------------------------------------------------------------------
-- ข้อมูลสมมติ: ครู 2 คน (ครูหนึ่งมี 2 บัญชี: ตรึงแล้ว 1 · ยังไม่ตรึง 1) ผู้ดูแล 1 นักเรียน 1
-- ---------------------------------------------------------------------------
insert into public.teachers (id, display_name) values
  ('19000000-0000-4000-8000-000000000001', 'ครูหนึ่ง (ทดสอบ 9)'),
  ('19000000-0000-4000-8000-000000000002', 'ครูสอง (ทดสอบ 9)');
insert into private.teacher_allowlist (id, teacher_id, email, provider_subject) values
  ('99000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000001', 'one9@example.com', 'ta-1'),
  ('99000000-0000-4000-8000-000000000002', '19000000-0000-4000-8000-000000000001', 'one9school@example.com', null),
  ('99000000-0000-4000-8000-000000000003', '19000000-0000-4000-8000-000000000002', 'two9@example.com', 'ta-3'),
  -- บัญชี ta-6 ตรงสองแถว: แถว 4 ด้วยอีเมล (ยังไม่ตรึง) และแถว 5 ด้วย provider_subject
  ('99000000-0000-4000-8000-000000000004', '19000000-0000-4000-8000-000000000001', 'dual9@example.com', null),
  ('99000000-0000-4000-8000-000000000005', '19000000-0000-4000-8000-000000000001', 'dual9b@example.com', 'ta-6');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('39000000-0000-4000-8000-000000000001', '29000000-0000-4000-8000-000000000001', 'google', 'ta-1', 'one9@example.com', 'teacher', '19000000-0000-4000-8000-000000000001'),
  ('39000000-0000-4000-8000-000000000002', '29000000-0000-4000-8000-000000000002', 'google', 'ta-2', 'one9school@example.com', 'teacher', '19000000-0000-4000-8000-000000000001'),
  ('39000000-0000-4000-8000-000000000003', '29000000-0000-4000-8000-000000000003', 'google', 'ta-3', 'two9@example.com', 'teacher', '19000000-0000-4000-8000-000000000002'),
  ('39000000-0000-4000-8000-000000000004', '29000000-0000-4000-8000-000000000004', 'google', 'ta-4', 'admin9@example.com', 'admin', null),
  ('39000000-0000-4000-8000-000000000005', '29000000-0000-4000-8000-000000000005', 'google', 'ta-5', 'student9@example.com', 'student', null),
  ('39000000-0000-4000-8000-000000000006', '29000000-0000-4000-8000-000000000006', 'google', 'ta-6', 'dual9@example.com', 'teacher', '19000000-0000-4000-8000-000000000001');

create temp table res (label text primary key, body jsonb not null);
grant select, insert on res to authenticated;
create temp table guard_fail (fn text, got text);
grant insert, select on guard_fail to authenticated;

-- ---------------------------------------------------------------------------
-- B. ใครเรียกได้
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.admin_teachers() $$, 'P0001', 'forbidden', 'ครูเปิดรายการบัญชีครูไม่ได้');
select throws_ok($$ select public.admin_add_teacher('x9@example.com', null, 'ครูใหม่') $$, 'P0001', 'forbidden',
  'ครูเพิ่มบัญชีครูไม่ได้');
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000005", "role": "authenticated"}';
select throws_ok($$ select public.admin_remove_teacher('99000000-0000-4000-8000-000000000003') $$, 'P0001', 'forbidden',
  'นักเรียนเอาบัญชีครูออกไม่ได้');
set local role anon;
select throws_ok($$ select public.admin_teachers() $$, '42501', null, 'anon เรียกไม่ได้');

-- ---------------------------------------------------------------------------
-- C. ผู้ดูแล: รายการ + เพิ่ม
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000004", "role": "authenticated"}';
insert into res values ('list', public.admin_teachers());
select is(
  (select jsonb_agg(x - 'id' - 'teacher_id' - 'created_at' order by x ->> 'email', (x ->> 'signed_in') desc)
     from res, jsonb_array_elements(res.body -> 'allowlist') x
    where res.label = 'list' and x ->> 'teacher_name' like '%(ทดสอบ 9)' and x ->> 'email' not like 'd%'),
  '[{"teacher_name": "ครูหนึ่ง (ทดสอบ 9)", "email": "o•••••@example.com", "signed_in": true},
    {"teacher_name": "ครูหนึ่ง (ทดสอบ 9)", "email": "o•••••@example.com", "signed_in": false},
    {"teacher_name": "ครูสอง (ทดสอบ 9)", "email": "t•••••@example.com", "signed_in": true}]'::jsonb,
  'รายการบัญชีครู: ชื่อครู อีเมลปิดบางส่วน และเคยเข้าสู่ระบบแล้วหรือยัง');
select ok((select body::text !~ '(one9|two9|one9school)@example\.com' and body ->> 'admin_email' = 'a•••••@example.com'
             from res where label = 'list'),
  'ไม่มีอีเมลเต็มในรายการ (รวมอีเมลผู้ดูแล)');
select throws_ok($$ select public.admin_add_teacher('not-an-email', '19000000-0000-4000-8000-000000000001') $$,
  'P0001', 'email_invalid', 'อีเมลผิดรูปแบบ');
select throws_ok($$ select public.admin_add_teacher(' ONE9@example.com ', '19000000-0000-4000-8000-000000000001') $$,
  'P0001', 'teacher_email_exists', 'อีเมลที่อยู่ในรายการแล้ว (ไม่สนตัวพิมพ์)');
select throws_ok($$ select public.admin_add_teacher('new9@example.com') $$,
  'P0001', 'teacher_required', 'ต้องเลือกครูหรือใส่ชื่อครูคนใหม่');
select throws_ok($$ select public.admin_add_teacher('new9@example.com', null, repeat('ก', 61)) $$,
  'P0001', 'teacher_name_invalid', 'ชื่อครูคนใหม่ยาวเกิน 60 ตัวอักษร');
select is(public.admin_add_teacher('New9@Example.com', '19000000-0000-4000-8000-000000000002') - 'id' - 'teacher_id',
  '{"teacher_name": "ครูสอง (ทดสอบ 9)", "email": "n•••••@example.com", "signed_in": false}'::jsonb,
  'เพิ่มบัญชีให้ครูที่มีอยู่');
select is(public.admin_add_teacher('third9@example.com', null, ' ครูสาม (ทดสอบ 9) ') ->> 'teacher_name',
  'ครูสาม (ทดสอบ 9)', 'เพิ่มบัญชีพร้อมสร้างครูคนใหม่');

-- ---------------------------------------------------------------------------
-- D. เอาออก: ครูที่ถูกเอาออกใช้สิทธิ์ครูไม่ได้ทันที
-- ---------------------------------------------------------------------------
select is(public.admin_remove_teacher('99000000-0000-4000-8000-000000000003') - 'id',
  '{"removed": true, "demoted_accounts": 1}'::jsonb, 'เอาบัญชีครูสองออก: บัญชีนั้นกลายเป็นนักเรียน');
select is(public.admin_remove_teacher('99000000-0000-4000-8000-000000000003') ->> 'removed', 'false',
  'เอาออกซ้ำได้ผลเดิม');
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.roster_overview() $$, 'P0001', 'forbidden',
  'ครูที่ถูกเอาออกเรียก RPC ฝั่งครูไม่ได้ทันที (ไม่ต้องรอ ensure_account)');
select is((select count(*) from public.students), 0::bigint, 'ครูที่ถูกเอาออกอ่านรายชื่อนักเรียนผ่าน RLS ไม่ได้ทันที');

-- ครูหนึ่งมี 2 บัญชี: เอาบัญชีที่ตรึงแล้วออก บัญชีโรงเรียนยังเป็นครู
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select is(public.admin_remove_teacher('99000000-0000-4000-8000-000000000001') ->> 'demoted_accounts', '1',
  'เอาบัญชีหนึ่งของครูหนึ่งออก ลดบทบาทเฉพาะบัญชีนั้น');
set local role postgres;
select results_eq(
  $$ select a.provider_subject, a.role from public.accounts a where a.provider_subject in ('ta-1', 'ta-2') order by 1 $$,
  $$ values ('ta-1', 'student'), ('ta-2', 'teacher') $$,
  'บัญชีอีกอันของครูคนเดียวกันที่ยังอยู่ในรายการยังเป็นครู');

set local role authenticated;
select is(public.admin_remove_teacher('99000000-0000-4000-8000-000000000004') ->> 'demoted_accounts', '0',
  'บัญชีที่ยังตรงกับแถวอื่นที่ใช้งานอยู่ (provider_subject) ไม่ถูกลดบทบาท');
set local role postgres;

-- เหลือแถวที่ใช้งานแถวเดียว (ชั่วคราวใน transaction) แล้วลองเอาออก
update private.teacher_allowlist set revoked_at = clock_timestamp()
 where revoked_at is null and id <> '99000000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$ select public.admin_remove_teacher('99000000-0000-4000-8000-000000000002') $$,
  'P0001', 'last_teacher', 'เอาบัญชีครูรายการสุดท้ายออกไม่ได้');
set local role postgres;
select ok((select l.revoked_at is null from private.teacher_allowlist l where l.id = '99000000-0000-4000-8000-000000000002')
  and (select a.role from public.accounts a where a.provider_subject = 'ta-2') = 'teacher',
  'รายการสุดท้ายและบัญชีครูนั้นยังอยู่');

-- ---------------------------------------------------------------------------
-- E. โหมดผู้ดูแล: ผู้ดูแลเรียก RPC ฝั่งครูโดยไม่ส่ง p_admin_mode → admin_mode_required ทุกตัว
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "29000000-0000-4000-8000-000000000004", "role": "authenticated"}';
do $$
declare
  f record;
  v_args text;
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig, p.proargtypes, p.pronargs
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and 'p_admin_mode' = any(coalesce(p.proargnames, '{}'))
  loop
    -- อาร์กิวเมนต์อื่นเป็น null แต่ p_admin_mode (ตัวท้าย) = false
    select string_agg(case when i = f.pronargs - 1 then 'false' else format('null::%s', format_type(t, null)) end, ', ' order by i)
      into v_args
      from unnest(f.proargtypes::oid[]) with ordinality u(t, n), lateral (select n - 1 as i) x;
    begin
      execute format('select %s(%s)', f.oid::regproc, v_args);
      insert into pg_temp.guard_fail values (f.sig, 'no error');
    exception when others then
      if sqlerrm <> 'admin_mode_required' then
        insert into pg_temp.guard_fail values (f.sig, sqlerrm);
      end if;
    end;
  end loop;
end
$$;
set local role postgres;
select is_empty($$ select fn || ' → ' || got from pg_temp.guard_fail $$,
  'ผู้ดูแลเรียก RPC ฝั่งครูทุกตัวโดยไม่ส่ง p_admin_mode ถูกปฏิเสธด้วย admin_mode_required');
select ok((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
             and 'p_admin_mode' = any(coalesce(p.proargnames, '{}'))) >= 8,
  'ตรวจครบทุก RPC ฝั่งครูที่มีอยู่ (อย่างน้อย 8 ตัว)');
set local role authenticated;
select is(jsonb_typeof(public.roster_overview(true)), 'array', 'ผู้ดูแลในโหมดผู้ดูแลเรียก RPC ฝั่งครูได้');

set local role postgres;
select * from finish();
rollback;
