-- ทดสอบ 0014_post_rpcs: create_post — สิทธิ์ (ครู/ผู้ดูแลในโหมดผู้ดูแล), request key, เพดานตาม 0010_posts,
-- กติกาภาคเรียน K5 และนักเรียนในห้องอ่านโพสต์ที่สร้างผ่าน RLS เดิม — ข้อมูลสมมติทั้งหมด (@example.com) rollback ตอนจบ
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

select plan(50);

select ok(
  has_function_privilege('authenticated', 'public.create_post(uuid,jsonb,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.create_post(uuid,jsonb,uuid,boolean)', 'EXECUTE'),
  'create_post: authenticated เรียกได้ (ตรวจครูภายใน) anon ไม่ได้');
select is_empty(
  $$ select f from unnest(array['private.jsonb_int(jsonb)', 'private.jsonb_timestamptz(jsonb)', 'private.trim_text(text)']) f,
                  unnest(array['anon', 'authenticated', 'service_role']) r
      where has_function_privilege(r, f, 'EXECUTE') $$,
  'ฟังก์ชันช่วยของ 0014 ใช้ภายในเท่านั้น');

-- ข้อมูลสมมติ: เทอมปัจจุบัน + เทอมเก่า, ครู 2 คน, ผู้ดูแล, นักเรียนสมาชิก 1 คน
insert into public.terms (id, name, status) values
  ('4f000000-0000-4000-8000-000000000001', 'ภาคทดสอบโพสต์ใหม่', 'active'),
  ('4f000000-0000-4000-8000-000000000002', 'ภาคทดสอบโพสต์เก่า', 'superseded');
insert into public.term_control (term_id) values ('4f000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1f000000-0000-4000-8000-000000000001', 'ครูทดสอบสร้างโพสต์'),
  ('1f000000-0000-4000-8000-000000000002', 'ครูทดสอบห้องอื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3f000000-0000-4000-8000-000000000001', '2f000000-0000-4000-8000-000000000001', 'google', 'cp-1', 'teacher14a@example.com', 'teacher', '1f000000-0000-4000-8000-000000000001'),
  ('3f000000-0000-4000-8000-000000000002', '2f000000-0000-4000-8000-000000000002', 'google', 'cp-2', 'teacher14b@example.com', 'teacher', '1f000000-0000-4000-8000-000000000002'),
  ('3f000000-0000-4000-8000-000000000003', '2f000000-0000-4000-8000-000000000003', 'google', 'cp-3', 'admin14@example.com', 'admin', null),
  ('3f000000-0000-4000-8000-000000000004', '2f000000-0000-4000-8000-000000000004', 'google', 'cp-4', 'student14@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('6f000000-0000-4000-8000-000000000001', '940000000000001', 'สมาชิก ห้องสร้างโพสต์', '3f000000-0000-4000-8000-000000000004');
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7f000000-0000-4000-8000-000000000001', '4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000001', 'เคมีทดสอบสร้างโพสต์', 'YYYY27'),
  ('7f000000-0000-4000-8000-000000000002', '4f000000-0000-4000-8000-000000000002', '1f000000-0000-4000-8000-000000000001', 'เคมีเทอมเก่า', 'YYYY28');
insert into public.memberships (classroom_id, student_id) values
  ('7f000000-0000-4000-8000-000000000001', '6f000000-0000-4000-8000-000000000001');

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.hw(p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('kind', 'homework', 'title', 'งานสมดุลเคมี', 'body', 'ข้อ 1–5 H₂ + I₂ ⇌ 2HI',
                            'full_score', 10, 'late_penalty_pct', 30, 'reward_tokens', 2,
                            'due_at', '2026-11-10T13:00:00.000Z', 'close_at', '2026-11-17T13:00:00Z',
                            'accept_after_solution', true) || p_extra
$$;
grant execute on function pg_temp.hw(jsonb) to authenticated;

set local role anon;
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), gen_random_uuid()) $$,
  '42501', null, 'anon เรียก create_post ไม่ได้');

-- ---------------------------------------------------------------------------
-- ครูเจ้าของห้องสร้างการบ้านและประกาศ
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('hw', public.create_post('7f000000-0000-4000-8000-000000000001',
  pg_temp.hw('{"title": "  งานสมดุลเคมี  ", "body": "\n  ข้อ 1–5 H₂ + I₂ ⇌ 2HI \n\n"}'), 'a1000000-0000-4000-8000-000000000001'));
select is((select body - 'post_id' - 'published_at' from res where label = 'hw'),
  '{"classroom_id": "7f000000-0000-4000-8000-000000000001", "kind": "homework", "title": "งานสมดุลเคมี",
    "body": "ข้อ 1–5 H₂ + I₂ ⇌ 2HI", "version": 1, "files": [],
    "assignment": {"full_score": 10, "late_penalty_pct": 30, "reward_tokens": 2, "due_at": "2026-11-10T13:00:00+00:00",
                   "close_at": "2026-11-17T13:00:00+00:00", "accept_after_solution": true}}'::jsonb,
  'การบ้าน: ตัดช่องว่างหัวท้ายชื่อและรายละเอียด (ตัวห้อยเป็นอักขระ Unicode) เก็บกำหนดส่ง/ปิดรับเป็น UTC');
set local role postgres;
select results_eq(
  $$ select p.kind, p.title, a.full_score, a.late_penalty_pct, a.reward_tokens, a.due_at, a.accept_after_solution, a.reward_locked_at is null
       from public.posts p join public.assignments a on a.post_id = p.id
      where p.id = ((select body from res where label = 'hw') ->> 'post_id')::uuid $$,
  $$ values ('homework', 'งานสมดุลเคมี', 10, 30, 2, '2026-11-10 13:00:00+00'::timestamptz, true, true) $$,
  'บันทึก posts + assignments (ยังไม่ล็อกโทเคน)');
set local role authenticated;

insert into res values ('defaults', public.create_post('7f000000-0000-4000-8000-000000000001',
  '{"kind": "homework", "title": "งานค่าเริ่มต้น", "full_score": 150, "due_at": "2026-11-11T20:00:00+07:00"}', gen_random_uuid()));
select is((select body -> 'assignment' from res where label = 'defaults'),
  '{"full_score": 150, "late_penalty_pct": 50, "reward_tokens": 1, "due_at": "2026-11-11T13:00:00+00:00",
    "close_at": null, "accept_after_solution": false}'::jsonb,
  'ค่าเริ่มต้น: หัก 50% (J1) โทเคน 1 ไม่ตั้งวันปิดรับ ไม่รับหลังเฉลย · คะแนนเต็มเกิน 100 ได้ (K1) · เวลาไทย +07:00 แปลงเป็น UTC');
select is((select body ->> 'body' from res where label = 'defaults'), null, 'การบ้านไม่ใส่รายละเอียดได้');

insert into res values ('ann', public.create_post('7f000000-0000-4000-8000-000000000001',
  '{"kind": "announcement", "title": "นัดสอบย่อย", "body": "วันศุกร์นี้ คาบ 3"}', gen_random_uuid()));
select is((select body -> 'assignment' from res where label = 'ann'), 'null'::jsonb, 'ประกาศไม่มีข้อมูลงาน');
set local role postgres;
select ok(not exists (select 1 from public.assignments where post_id = ((select body from res where label = 'ann') ->> 'post_id')::uuid),
  'ประกาศไม่มีแถว assignments');
set local role authenticated;

-- กดซ้ำด้วย request key เดิม
select is(public.create_post('7f000000-0000-4000-8000-000000000001',
  pg_temp.hw('{"title": "  งานสมดุลเคมี  ", "body": "\n  ข้อ 1–5 H₂ + I₂ ⇌ 2HI \n\n"}'), 'a1000000-0000-4000-8000-000000000001'),
  (select body from res where label = 'hw'), 'กดซ้ำด้วย request key เดิม: ได้ผลเดิม');
set local role postgres;
select is((select count(*)::integer from public.posts where classroom_id = '7f000000-0000-4000-8000-000000000001' and title = 'งานสมดุลเคมี'), 1,
  'กดซ้ำได้โพสต์เดียว');
set local role authenticated;
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"title": "เปลี่ยนชื่อ"}'), 'a1000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่เนื้อหาต่าง → request_key_conflict');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), null) $$,
  'P0001', 'request_key_required', 'ไม่มี request key ไม่ได้');
select lives_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"due_at": "2020-01-01T00:00:00Z", "close_at": null}'), gen_random_uuid()) $$,
  'กำหนดส่งที่ผ่านไปแล้วรับได้ (T02 เตือนสีเหลือง J7)');

-- ---------------------------------------------------------------------------
-- เนื้อหา: เพดานเดียวกับ 0010_posts และรูปแบบก้อนข้อมูล
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"title": "   "}'), gen_random_uuid()) $$,
  'P0001', 'post_title_invalid', 'ชื่อว่างไม่ได้');
select throws_ok(format($f$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(jsonb_build_object('title', %L)), gen_random_uuid()) $f$, repeat('ก', 121)),
  'P0001', 'post_title_invalid', 'ชื่อยาวเกิน 120 ไม่ได้');
select lives_ok(format($f$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(jsonb_build_object('title', %L)), gen_random_uuid()) $f$, repeat('ก', 120)),
  'ชื่อยาว 120 ตัวพอดีได้');
select throws_ok(format($f$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(jsonb_build_object('body', %L)), gen_random_uuid()) $f$, repeat('ข', 10001)),
  'P0001', 'post_body_too_long', 'รายละเอียดเกิน 10,000 ตัวไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', '{"kind": "announcement", "title": "ประกาศว่าง", "body": "  "}', gen_random_uuid()) $$,
  'P0001', 'post_body_required', 'ประกาศต้องมีข้อความ');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"full_score": 0}'), gen_random_uuid()) $$,
  'P0001', 'full_score_invalid', 'K1: คะแนนเต็มต่ำกว่า 1 ไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"full_score": 9.5}'), gen_random_uuid()) $$,
  'P0001', 'full_score_invalid', 'K1: คะแนนเต็มต้องเป็นจำนวนเต็ม');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"full_score": "10"}'), gen_random_uuid()) $$,
  'P0001', 'full_score_invalid', 'คะแนนเต็มต้องเป็นตัวเลข ไม่ใช่ข้อความ');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"full_score": 1000001}'), gen_random_uuid()) $$,
  'P0001', 'full_score_invalid', 'คะแนนเต็มเกินเพดานกันค่าผิดพลาดไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"late_penalty_pct": 101}'), gen_random_uuid()) $$,
  'P0001', 'late_penalty_invalid', 'J1: % หักเกิน 100 ไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"late_penalty_pct": -1}'), gen_random_uuid()) $$,
  'P0001', 'late_penalty_invalid', 'J1: % หักติดลบไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"reward_tokens": -1}'), gen_random_uuid()) $$,
  'P0001', 'reward_tokens_invalid', 'โทเคนติดลบไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"reward_tokens": 1001}'), gen_random_uuid()) $$,
  'P0001', 'reward_tokens_invalid', 'โทเคนเกินเพดานกันค่าผิดพลาดไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"due_at": "2026-11-10T13:00:30Z"}'), gen_random_uuid()) $$,
  'P0001', 'due_at_invalid', 'กำหนดส่งต้องเป็นนาทีเต็ม');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"due_at": "2026-11-10T13:00:00"}'), gen_random_uuid()) $$,
  'P0001', 'due_at_invalid', 'กำหนดส่งต้องระบุเขตเวลา (ไม่ขึ้นกับ TimeZone ของ session)');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"due_at": "2026-13-40T13:00:00Z"}'), gen_random_uuid()) $$,
  'P0001', 'due_at_invalid', 'วันที่ที่ไม่มีจริงไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw() - 'due_at', gen_random_uuid()) $$,
  'P0001', 'due_at_invalid', 'การบ้านต้องมีกำหนดส่ง');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"close_at": "2026-11-10T12:59:00Z"}'), gen_random_uuid()) $$,
  'P0001', 'close_before_due', 'วันปิดรับต้องไม่ก่อนกำหนดส่ง');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"close_at": "เมื่อไรก็ได้"}'), gen_random_uuid()) $$,
  'P0001', 'close_at_invalid', 'วันปิดรับรูปแบบผิดไม่ได้');
select lives_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"close_at": "2026-11-10T13:00:00Z"}'), gen_random_uuid()) $$,
  'วันปิดรับเท่ากับกำหนดส่งได้ (ไม่มีช่วงรับงานสาย)');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"kind": "quiz"}'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ชนิดโพสต์อื่นไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"reward_locked_at": "2026-01-01T00:00:00Z"}'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'คีย์ที่ไม่รู้จัก (เช่นช่องล็อก) ไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', '{"kind": "announcement", "title": "ประกาศ", "body": "x", "full_score": 10}', gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ประกาศมีช่องคะแนน/เวลา/รางวัลไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw('{"accept_after_solution": "yes"}'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'รับหลังเฉลยต้องเป็น true/false');

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนโพสต์ไม่ได้');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูอีกคนโพสต์ในห้องที่ไม่ได้สอนไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-0000000000ff', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ห้องที่ไม่มีอยู่ → forbidden');
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลที่ไม่ส่ง p_admin_mode โพสต์ไม่ได้');
select lives_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001',
                    '{"kind": "announcement", "title": "ประกาศจากผู้ดูแล", "body": "ทำแทนครู"}', gen_random_uuid(), true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลโพสต์แทนครูได้');

-- ---------------------------------------------------------------------------
-- ข: ภาคเรียน (K5)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000001", "role": "authenticated"}';
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000002', '{"kind": "announcement", "title": "ห้องเก่า", "body": "x"}', gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ห้องของเทอมเก่า: ประกาศไม่ได้');
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000002', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'term_ended', 'ห้องของเทอมเก่า: การบ้านไม่ได้');
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp();
set local role authenticated;
select throws_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', pg_temp.hw(), gen_random_uuid()) $$,
  'P0001', 'term_ended', 'จบภาคเรียนแล้ว (ended): สร้างการบ้านไม่ได้');
select lives_ok($$ select public.create_post('7f000000-0000-4000-8000-000000000001', '{"kind": "announcement", "title": "แจ้งคะแนน", "body": "ดูคะแนนได้แล้ว"}', gen_random_uuid()) $$,
  'จบภาคเรียนแล้ว (ended): ประกาศยังโพสต์ได้');
set local role postgres;
update public.term_control set status = 'active', ended_at = null;

-- ---------------------------------------------------------------------------
-- นักเรียนในห้องอ่านโพสต์ที่สร้างผ่าน RLS เดิม (S02)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2f000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select ok((select count(*) from public.posts where id = ((select body from res where label = 'hw') ->> 'post_id')::uuid) = 1
          and (select count(*) from public.assignments where post_id = ((select body from res where label = 'hw') ->> 'post_id')::uuid) = 1,
  'สมาชิกห้องเห็นการบ้านที่สร้างพร้อมข้อมูลงาน');
select ok(exists (select 1 from public.posts where id = ((select body from res where label = 'ann') ->> 'post_id')::uuid),
  'สมาชิกห้องเห็นประกาศ');
set local role postgres;
delete from public.memberships where student_id = '6f000000-0000-4000-8000-000000000001';
set local role authenticated;
select is_empty($$ select id from public.posts where classroom_id = '7f000000-0000-4000-8000-000000000001' $$,
  'ถูกเอาออกแล้วไม่เห็นโพสต์ (S02 แสดง not_member จาก classroom_view)');

select * from finish();
rollback;
