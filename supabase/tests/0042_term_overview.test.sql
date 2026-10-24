-- ทดสอบ 0042_term_overview: สิทธิ์, ตัวเลขรวมของภาคเรียนปัจจุบัน, ภาคเรียนเก่าและวันครบอายุ (J9.2)
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

select plan(10);

-- ข้อมูลสมมติ: T1 ปัจจุบัน (active) · T0 เก่าแบบเริ่มเทอมทับ · TE เก่าแบบกดจบแล้วเริ่มใหม่ · TX เทอมอื่นที่ไม่เกี่ยว
-- ห้อง C1, C2 (T1) และ C0 (T0) · S1 อยู่ C1+C2, S2 อยู่ C1, S3 อยู่ C0
-- H1 (C1): S1 ส่งแล้วตรวจแล้ว, S2 ส่งยังไม่ตรวจ · H0 (C0): S3 ส่งยังไม่ตรวจ (ไม่นับ — เทอมเก่า)
-- ยอด T1: S1 4 + S2 3 = 7 · ยอด T0: S3 9 (ไม่นับ)
insert into public.terms (id, name, status, started_at) values
  ('40420000-0000-4000-8000-000000000001', 'ภาคภาพรวม ปัจจุบัน', 'active', '2026-10-01T00:00:00Z');
insert into public.terms (id, name, status, started_at, ended_at, superseded_at) values
  ('40420000-0000-4000-8000-000000000002', 'ภาคภาพรวม เก่า', 'superseded', '2026-05-01T00:00:00Z', null, '2026-10-01T00:00:00Z'),
  ('40420000-0000-4000-8000-000000000003', 'ภาคภาพรวม จบแล้ว', 'ended', '2025-11-01T00:00:00Z', '2026-03-15T03:00:00Z', null);
insert into public.term_control (term_id) values ('40420000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10420000-0000-4000-8000-000000000001', 'ครูภาพรวม');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30420000-0000-4000-8000-000000000001', '20420000-0000-4000-8000-000000000001', 'google', 'ov-1', 't42@example.com', 'teacher', '10420000-0000-4000-8000-000000000001'),
  ('30420000-0000-4000-8000-000000000002', '20420000-0000-4000-8000-000000000002', 'google', 'ov-2', 'a42@example.com', 'admin', null),
  ('30420000-0000-4000-8000-000000000011', '20420000-0000-4000-8000-000000000011', 'google', 'ov-11', 's42@example.com', 'student', null);
insert into public.students (id, student_code, display_name) values
  ('60420000-0000-4000-8000-000000000001', '942000000000421', 'หนึ่ง ภาพรวม'),
  ('60420000-0000-4000-8000-000000000002', '942000000000422', 'สอง ภาพรวม'),
  ('60420000-0000-4000-8000-000000000003', '942000000000423', 'สาม ภาพรวม');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70420000-0000-4000-8000-000000000001', '40420000-0000-4000-8000-000000000001', '10420000-0000-4000-8000-000000000001', 'ภาพรวม 1', 'ZZZZ4B'),
  ('70420000-0000-4000-8000-000000000002', '40420000-0000-4000-8000-000000000001', '10420000-0000-4000-8000-000000000001', 'ภาพรวม 2', 'ZZZZ4C'),
  ('70420000-0000-4000-8000-000000000003', '40420000-0000-4000-8000-000000000002', '10420000-0000-4000-8000-000000000001', 'ภาพรวมเก่า', 'ZZZZ4D');
insert into public.memberships (classroom_id, student_id) values
  ('70420000-0000-4000-8000-000000000001', '60420000-0000-4000-8000-000000000001'),
  ('70420000-0000-4000-8000-000000000002', '60420000-0000-4000-8000-000000000001'),
  ('70420000-0000-4000-8000-000000000001', '60420000-0000-4000-8000-000000000002'),
  ('70420000-0000-4000-8000-000000000003', '60420000-0000-4000-8000-000000000003');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80420000-0000-4000-8000-000000000001', '70420000-0000-4000-8000-000000000001', 'homework', 'H1', '2026-10-02T01:00:00Z'),
  ('80420000-0000-4000-8000-000000000002', '70420000-0000-4000-8000-000000000003', 'homework', 'H0', '2026-06-02T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, reward_tokens) values
  ('80420000-0000-4000-8000-000000000001', 10, '2026-10-10T13:00:00Z', 2),
  ('80420000-0000-4000-8000-000000000002', 10, '2026-06-10T13:00:00Z', 2);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at) values
  ('50420000-0000-4000-8000-000000000001', '80420000-0000-4000-8000-000000000001', '60420000-0000-4000-8000-000000000001', '2026-10-05T01:00:00Z', '2026-10-05T01:00:00Z'),
  ('50420000-0000-4000-8000-000000000002', '80420000-0000-4000-8000-000000000001', '60420000-0000-4000-8000-000000000002', '2026-10-05T01:00:00Z', '2026-10-05T01:00:00Z'),
  ('50420000-0000-4000-8000-000000000003', '80420000-0000-4000-8000-000000000002', '60420000-0000-4000-8000-000000000003', '2026-06-05T01:00:00Z', '2026-06-05T01:00:00Z');
insert into public.wallets (student_id, term_id, balance) values
  ('60420000-0000-4000-8000-000000000001', '40420000-0000-4000-8000-000000000001', 4),
  ('60420000-0000-4000-8000-000000000002', '40420000-0000-4000-8000-000000000001', 3),
  ('60420000-0000-4000-8000-000000000003', '40420000-0000-4000-8000-000000000002', 9);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
-- ตรวจผ่าน S1 ด้วยสิทธิ์ครู
set local role authenticated;
select pg_temp.as_user('20420000-0000-4000-8000-000000000001');
insert into res values ('g', public.grade_submission('50420000-0000-4000-8000-000000000001', 8, true, null, null, 1, 0, gen_random_uuid()));

-- สิทธิ์
select pg_temp.as_user('20420000-0000-4000-8000-000000000011');
select throws_ok($$ select public.term_overview() $$, 'P0001', 'forbidden', 'นักเรียนเรียกไม่ได้');
select pg_temp.as_user('20420000-0000-4000-8000-000000000002');
select throws_ok($$ select public.term_overview() $$, 'P0001', 'admin_mode_required', 'ผู้ดูแลต้องอยู่ในโหมดผู้ดูแล');
select lives_ok($$ select public.term_overview(true) $$, 'ผู้ดูแลในโหมดผู้ดูแลเรียกได้');

select pg_temp.as_user('20420000-0000-4000-8000-000000000001');
insert into res values ('ov', public.term_overview());
select is(pg_temp.r('ov') -> 'term' ->> 'term_id', '40420000-0000-4000-8000-000000000001', 'ภาคเรียนปัจจุบัน');
select is(jsonb_build_array(pg_temp.r('ov') -> 'classrooms', pg_temp.r('ov') -> 'students'), '[2, 2]'::jsonb,
  'ห้อง 2 ห้อง นักเรียนไม่ซ้ำ 2 คน (ไม่นับห้องเทอมเก่า)');
select is((pg_temp.r('ov') ->> 'tokens')::integer, 9, 'โทเคนคงเหลือรวมเฉพาะเทอมปัจจุบัน (4+3 + 2 จากการตรวจผ่าน)');
select is((pg_temp.r('ov') ->> 'waiting')::integer, 1, 'งานรอตรวจเฉพาะเทอมปัจจุบัน');
select is((select jsonb_agg(jsonb_build_array(x ->> 'name', x ->> 'how') order by ord)
             from jsonb_array_elements(pg_temp.r('ov') -> 'old_terms') with ordinality o(x, ord)
            where x ->> 'name' like 'ภาคภาพรวม%'),
  '[["ภาคภาพรวม เก่า", "start"], ["ภาคภาพรวม จบแล้ว", "end"]]'::jsonb,
  'ภาคเรียนเก่าเรียงใหม่ → เก่า บอกวิธีสิ้นสุด ไม่รวมภาคเรียนที่ยังเปิด');
select is((select jsonb_build_array((x ->> 'files_due')::timestamptz, (x ->> 'data_due')::timestamptz)
             from jsonb_array_elements(pg_temp.r('ov') -> 'old_terms') x where x ->> 'name' = 'ภาคภาพรวม จบแล้ว'),
  jsonb_build_array('2026-05-14T03:00:00Z'::timestamptz, '2027-03-15T03:00:00Z'::timestamptz),
  'วันครบอายุ: ไฟล์ +60 วัน คะแนน +1 ปี นับจาก ended_at');

-- กดจบภาคเรียนปัจจุบัน → ขึ้นในข้อมูลภาคเรียนเก่า
insert into res values ('end', public.terms_end('40420000-0000-4000-8000-000000000001', gen_random_uuid()));
select is((public.term_overview() -> 'old_terms' -> 0) ->> 'name', 'ภาคภาพรวม ปัจจุบัน',
  'ภาคเรียนที่เพิ่งกดจบขึ้นเป็นแถวแรกของข้อมูลเก่า');

select * from finish();
rollback;
