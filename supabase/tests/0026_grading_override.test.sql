-- ทดสอบ 0026_grading_override: % หักรายคนคงอยู่เมื่อเลื่อนกำหนดจนงานนับเป็นส่งทัน และกลับมาใช้เมื่อสายอีก
-- (TECHNICAL_DESIGN ส่วน 6 "ยืนยัน L2" ฉบับ 17 ต.ค. 2026) — ข้อมูลสมมติ rollback ตอนจบ
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

select plan(10);

-- ข้อมูลสมมติ: ครู 1 ห้อง 1; H1 เต็ม 10 หัก 50% กำหนด 30 ก.ย. 20:00 น.; N1 ส่งครั้งแรก 1 ต.ค. (สาย)
insert into public.terms (id, name, status) values ('4f000000-0000-4000-8000-000000000001', 'ภาคทดสอบปรับรายคน', 'active');
insert into public.term_control (term_id) values ('4f000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('1f000000-0000-4000-8000-000000000001', 'ครูปรับหนึ่ง');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3f000000-0000-4000-8000-000000000001', '2f000000-0000-4000-8000-000000000001', 'google', 'ov-1', 't26a@example.com', 'teacher', '1f000000-0000-4000-8000-000000000001');
insert into public.students (id, student_code, display_name) values
  ('6f000000-0000-4000-8000-000000000001', '926000000000261', 'หนึ่ง ปรับ');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000001', 'เคมีปรับ 1', 'ZZZZ76');
insert into public.memberships (classroom_id, student_id) values
  ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000001');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('8f000000-0000-4000-8000-000000000001', '7f000000-0000-4000-8000-000000000001', 'homework', 'งานปรับหนึ่ง', '2026-09-20T01:00:00Z');
insert into public.assignments (post_id, full_score, late_penalty_pct, due_at) values
  ('8f000000-0000-4000-8000-000000000001', 10, 50, '2026-09-30T13:00:00Z');
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('5f000000-0000-4000-8000-000000000001', '8f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000001', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z');

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
-- [raw, timing, pct ที่ใช้, net, override, version]
create function pg_temp.brief(p jsonb) returns jsonb language sql immutable as
  $$ select jsonb_build_array(p -> 'raw_score', p -> 'timing', p -> 'applied_penalty_pct', p -> 'net_score',
                              p -> 'penalty_override_pct', p -> 'version') $$;
grant execute on function pg_temp.brief(jsonb) to authenticated;
create function pg_temp.move_due(p_due timestamptz) returns void language sql security definer set search_path = '' as
  $$ update public.assignments set due_at = p_due where post_id = '8f000000-0000-4000-8000-000000000001' $$;
grant execute on function pg_temp.move_due(timestamptz) to authenticated;

set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';

-- 1) สาย: ตั้ง override 20% พร้อมเหตุผล
insert into res values ('late_set', public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, 20, 'ป่วย', 1, 0, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('late_set')), '[7, "late", 20, 6, 20, 1]'::jsonb, 'สาย: ตั้งปรับเฉพาะคน 20% → 6');

-- 2) ขยายกำหนดจนนับเป็นส่งทัน → บันทึกใหม่ด้วยค่าเดิมผ่าน ไม่หัก ค่าและเหตุผลเดิมคงอยู่
select pg_temp.move_due('2026-10-05T13:00:00Z');
insert into res values ('on_time_same', public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, 20, null, 1, 1, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('on_time_same')), '[7, "on_time", 0, 7, 20, 2]'::jsonb,
  'ส่งทันแล้ว: ส่งค่าเดิมกลับมาผ่าน ไม่หัก และ override ยังเก็บไว้');
select is(pg_temp.r('on_time_same') -> 'override_comment_id', pg_temp.r('late_set') -> 'override_comment_id',
  'เหตุผลเดิมยังผูกกับผลตรวจ');
select throws_ok($$ select public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, 30, 'เปลี่ยน', 1, 2, gen_random_uuid()) $$,
  'P0001', 'penalty_not_late', 'ส่งทัน: เปลี่ยนค่า override ไม่ได้');
select throws_ok($$ select public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, 20, 'ซ้ำ', 1, 2, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ส่งเหตุผลโดยไม่เปลี่ยนค่า → invalid_request');
select throws_ok($$ select public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, null, null, 1, 2, gen_random_uuid()) $$,
  'P0001', 'reason_required', 'ส่งทัน: ล้าง override ก็ต้องมีเหตุผล (ไม่ล้างเองเงียบ ๆ)');

-- 3) เลื่อนกำหนดกลับจนสาย → บันทึกใหม่ใช้ override เดิม
select pg_temp.move_due('2026-09-30T13:00:00Z');
insert into res values ('late_again', public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, 20, null, 1, 2, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('late_again')), '[7, "late", 20, 6, 20, 3]'::jsonb, 'สายอีกครั้ง: ใช้ override เดิม 20% → 6');

-- 4) ล้างพร้อมเหตุผลตอนส่งทันได้ (สร้างความคิดเห็นใหม่)
select pg_temp.move_due('2026-10-05T13:00:00Z');
insert into res values ('clear', public.grade_submission('5f000000-0000-4000-8000-000000000001', 7, true, null, 'ยกเลิกการปรับ', 1, 3, gen_random_uuid()));
select is(pg_temp.brief(pg_temp.r('clear')), '[7, "on_time", 0, 7, null, 4]'::jsonb, 'ส่งทัน: ล้าง override พร้อมเหตุผลได้');
select isnt(pg_temp.r('clear') -> 'override_comment_id', pg_temp.r('late_set') -> 'override_comment_id',
  'การล้างผูกกับเหตุผลใหม่');
select is((select count(*)::integer from public.comments where student_id = '6f000000-0000-4000-8000-000000000001'), 2,
  'สร้างความคิดเห็นเฉพาะตอนตั้งและตอนล้าง (2 ข้อความ)');

select * from finish();
rollback;
