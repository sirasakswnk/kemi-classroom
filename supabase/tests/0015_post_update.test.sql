-- ทดสอบ 0015_post_update: update_post — สิทธิ์, stale version, request key ซ้ำ, ช่องที่ล็อก (ตั้งเวลาล็อกตรงในเทสต์),
-- กติกา content_updated_at (N1), ประกาศรับข้อมูลงานไม่ได้, กำหนดส่ง/วันปิดรับเปลี่ยนไม่ได้ในรอบนี้
-- ข้อมูลสมมติทั้งหมด (@example.com) และ rollback ตอนจบ
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

select plan(44);

select ok(
  has_function_privilege('authenticated', 'public.update_post(uuid,jsonb,integer,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.update_post(uuid,jsonb,integer,uuid,boolean)', 'EXECUTE'),
  'update_post: authenticated เรียกได้ (ตรวจครูภายใน) anon ไม่ได้');

-- ข้อมูลสมมติ: ครู 2 คน ผู้ดูแล นักเรียน 1 คน ห้อง 1 ห้อง การบ้าน H + ประกาศ A (สร้างตรงด้วย postgres)
insert into public.terms (id, name, status) values ('4c000000-0000-4000-8000-000000000001', 'ภาคทดสอบแก้โพสต์', 'active');
insert into public.term_control (term_id) values ('4c000000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values
  ('1c000000-0000-4000-8000-000000000001', 'ครูทดสอบแก้โพสต์'),
  ('1c000000-0000-4000-8000-000000000002', 'ครูทดสอบห้องอื่น');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('3c000000-0000-4000-8000-000000000001', '2c000000-0000-4000-8000-000000000001', 'google', 'up-1', 'teacher15a@example.com', 'teacher', '1c000000-0000-4000-8000-000000000001'),
  ('3c000000-0000-4000-8000-000000000002', '2c000000-0000-4000-8000-000000000002', 'google', 'up-2', 'teacher15b@example.com', 'teacher', '1c000000-0000-4000-8000-000000000002'),
  ('3c000000-0000-4000-8000-000000000003', '2c000000-0000-4000-8000-000000000003', 'google', 'up-3', 'admin15@example.com', 'admin', null),
  ('3c000000-0000-4000-8000-000000000004', '2c000000-0000-4000-8000-000000000004', 'google', 'up-4', 'student15@example.com', 'student', null);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('7c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000001', 'เคมีทดสอบแก้โพสต์', 'ZZZZ29');
insert into public.posts (id, classroom_id, kind, title, body, published_at) values
  ('8c000000-0000-4000-8000-00000000000b', '7c000000-0000-4000-8000-000000000001', 'homework', 'งานเดิม', 'โจทย์เดิม', '2026-10-01 01:00:00+00'),
  ('8c000000-0000-4000-8000-00000000000a', '7c000000-0000-4000-8000-000000000001', 'announcement', 'ประกาศเดิม', 'ข้อความเดิม', '2026-10-01 02:00:00+00');
insert into public.assignments (post_id, full_score, late_penalty_pct, reward_tokens, due_at, close_at) values
  ('8c000000-0000-4000-8000-00000000000b', 10, 50, 1, '2026-11-10 13:00:00+00', null);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
-- ก้อนข้อมูลเต็มของการบ้าน (ค่าปัจจุบันของ H) + ส่วนที่แก้
create function pg_temp.hw(p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('kind', 'homework', 'title', 'งานเดิม', 'body', 'โจทย์เดิม', 'full_score', 10,
                            'late_penalty_pct', 50, 'reward_tokens', 1, 'due_at', '2026-11-10T13:00:00Z',
                            'close_at', null, 'accept_after_solution', false) || p_extra
$$;
create function pg_temp.ver(p_id uuid) returns integer language sql as $$ select version from public.posts where id = p_id $$;
create function pg_temp.cur(p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('kind', 'homework', 'title', p.title, 'body', p.body, 'full_score', a.full_score,
                            'late_penalty_pct', a.late_penalty_pct, 'reward_tokens', a.reward_tokens,
                            'due_at', a.due_at, 'close_at', a.close_at, 'accept_after_solution', a.accept_after_solution) || p_extra
    from public.posts p join public.assignments a on a.post_id = p.id where p.id = '8c000000-0000-4000-8000-00000000000b'
$$;
grant execute on function pg_temp.hw(jsonb), pg_temp.ver(uuid), pg_temp.cur(jsonb) to authenticated;

set local role anon;
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw(), 1, gen_random_uuid()) $$,
  '42501', null, 'anon เรียก update_post ไม่ได้');

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "2c000000-0000-4000-8000-000000000004", "role": "authenticated"}';
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "นักเรียนแก้"}'), 1, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'นักเรียนแก้โพสต์ไม่ได้');
set local request.jwt.claims to '{"sub": "2c000000-0000-4000-8000-000000000002", "role": "authenticated"}';
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "ครูอื่นแก้"}'), 1, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'ครูห้องอื่นแก้ไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-0000000000ff', pg_temp.hw(), 1, gen_random_uuid()) $$,
  'P0001', 'forbidden', 'โพสต์ที่ไม่มีอยู่ → forbidden');
set local request.jwt.claims to '{"sub": "2c000000-0000-4000-8000-000000000003", "role": "authenticated"}';
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "ผู้ดูแลแก้"}'), 1, gen_random_uuid()) $$,
  'P0001', 'admin_mode_required', 'ผู้ดูแลที่ไม่ส่ง p_admin_mode แก้ไม่ได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a',
                    '{"kind": "announcement", "title": "ประกาศเดิม", "body": "ผู้ดูแลแก้ข้อความ"}', 1, gen_random_uuid(), true) $$,
  'ผู้ดูแลในโหมดผู้ดูแลแก้แทนครูได้');

-- ---------------------------------------------------------------------------
-- content_updated_at (N1) และ version
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "2c000000-0000-4000-8000-000000000001", "role": "authenticated"}';
insert into res values ('noop', public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw(), 1, gen_random_uuid()));
select is((select body ->> 'changed' from res where label = 'noop'), 'false', 'ไม่มีอะไรเปลี่ยน: changed = false');
select results_eq($$ select version, content_updated_at is null from public.posts where id = '8c000000-0000-4000-8000-00000000000b' $$,
  $$ values (1, true) $$, 'ไม่มีอะไรเปลี่ยน: ไม่ขยับ version และเวลาแก้ไขโจทย์');
select is(public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "  งานเดิม ", "body": "\n โจทย์เดิม  "}'), 1, gen_random_uuid()) ->> 'changed',
  'false', 'ช่องว่างหัวท้ายต่างกันอย่างเดียวไม่นับว่าเปลี่ยน');

insert into res values ('score', public.update_post('8c000000-0000-4000-8000-00000000000b',
  pg_temp.hw('{"full_score": 20, "late_penalty_pct": 30, "reward_tokens": 3, "accept_after_solution": true}'), 1, gen_random_uuid()));
select is((select body -> 'assignment' from res where label = 'score'),
  '{"full_score": 20, "late_penalty_pct": 30, "reward_tokens": 3, "due_at": "2026-11-10T13:00:00+00:00",
    "close_at": null, "accept_after_solution": true}'::jsonb,
  'แก้คะแนนเต็ม % หัก โทเคน รับหลังเฉลย ได้ก่อนล็อก');
select results_eq($$ select version, content_updated_at is null from public.posts where id = '8c000000-0000-4000-8000-00000000000b' $$,
  $$ values (2, true) $$, 'แก้คะแนน/โทเคน/ตัวเลือก: version + 1 แต่ไม่ขยับเวลาแก้ไขโจทย์ (N1)');

insert into res values ('content', public.update_post('8c000000-0000-4000-8000-00000000000b',
  pg_temp.hw('{"full_score": 20, "late_penalty_pct": 30, "reward_tokens": 3, "accept_after_solution": true, "title": "งานแก้ชื่อ", "body": "โจทย์ใหม่ Fe³⁺"}'),
  2, 'b1000000-0000-4000-8000-000000000001'));
select results_eq(
  $$ select title, body, version, content_updated_at is not null, content_updated_at > published_at
       from public.posts where id = '8c000000-0000-4000-8000-00000000000b' $$,
  $$ values ('งานแก้ชื่อ', 'โจทย์ใหม่ Fe³⁺', 3, true, true) $$,
  'แก้ชื่อ/รายละเอียด: version + 1 และตั้งเวลาแก้ไขโจทย์ล่าสุด');
select is((select body ->> 'content_updated_at' from res where label = 'content') is not null
          and (select (body ->> 'changed')::boolean from res where label = 'content'), true,
  'ผลคืนเวลาแก้ไขโจทย์ล่าสุดและ changed = true');
set local role postgres;
create temp table cu on commit drop as select content_updated_at from public.posts where id = '8c000000-0000-4000-8000-00000000000b';
grant select on cu to authenticated;
set local role authenticated;
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b',
  pg_temp.hw('{"full_score": 25, "late_penalty_pct": 30, "reward_tokens": 3, "accept_after_solution": true, "title": "งานแก้ชื่อ", "body": "โจทย์ใหม่ Fe³⁺"}'),
  3, gen_random_uuid()) $$, 'แก้คะแนนอย่างเดียวหลังแก้โจทย์');
select is((select content_updated_at from public.posts where id = '8c000000-0000-4000-8000-00000000000b'), (select content_updated_at from cu),
  'แก้คะแนนอย่างเดียวภายหลังไม่ขยับเวลาแก้ไขโจทย์เดิม');
set local role postgres;
select ok(pg_get_functiondef('public.update_post(uuid,jsonb,integer,uuid,boolean)'::regprocedure) !~* 'notification',
  'update_post ไม่อ้างถึงแจ้งเตือน (N1)');
set local role authenticated;

-- ---------------------------------------------------------------------------
-- stale version และ request key
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "แก้จากหน้าจอเก่า"}'), 1, gen_random_uuid()) $$,
  'P0001', 'stale_revision', 'version ที่หน้าจอถือไม่ตรง → stale_revision');
select is(public.update_post('8c000000-0000-4000-8000-00000000000b',
  pg_temp.hw('{"full_score": 20, "late_penalty_pct": 30, "reward_tokens": 3, "accept_after_solution": true, "title": "งานแก้ชื่อ", "body": "โจทย์ใหม่ Fe³⁺"}'),
  2, 'b1000000-0000-4000-8000-000000000001'),
  (select body from res where label = 'content'),
  'ส่งซ้ำด้วย request key เดิม (เน็ตหลุด) ได้ผลเดิม ไม่ใช่ stale_revision');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw('{"title": "อีกชื่อ"}'), 2, 'b1000000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่เนื้อหาต่าง → request_key_conflict');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw(), 4, null) $$,
  'P0001', 'request_key_required', 'ไม่มี request key ไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.hw(), null, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ไม่มี version ที่คาดไว้ไม่ได้');

-- ---------------------------------------------------------------------------
-- ช่องที่ล็อก (ตั้งเวลาล็อกตรง ๆ แทนการส่งงาน/ตรวจงาน/เผยแพร่เฉลยที่ยังไม่มี)
-- ---------------------------------------------------------------------------
set local role postgres;
update public.assignments set reward_locked_at = clock_timestamp() where post_id = '8c000000-0000-4000-8000-00000000000b';
set local role authenticated;
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"reward_tokens": 5}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'reward_locked', 'I4: มีการส่งแล้ว เปลี่ยนโทเคนไม่ได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"title": "ชื่อหลังล็อกโทเคน"}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'ส่งค่าเดิมของช่องที่ล็อกพร้อมแก้ชื่อได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"full_score": 30}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'ล็อกแยกกัน: ล็อกโทเคนแล้วยังแก้คะแนนเต็มได้จนบันทึกคะแนนแรก');
set local role postgres;
update public.assignments set full_score_locked_at = clock_timestamp() where post_id = '8c000000-0000-4000-8000-00000000000b';
set local role authenticated;
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"full_score": 40}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'full_score_locked', 'J2/L4: บันทึกคะแนนแรกแล้ว เปลี่ยนคะแนนเต็มไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"late_penalty_pct": 0}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'full_score_locked', 'K2: % หักล็อกพร้อมคะแนนเต็ม');
set local role postgres;
insert into public.solutions (assignment_id, body, published_at) values ('8c000000-0000-4000-8000-00000000000b', 'เฉลย', clock_timestamp());
set local role authenticated;
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"accept_after_solution": false}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'after_solution_locked', 'N2: เผยแพร่เฉลยแล้ว เปลี่ยนรับงานหลังเฉลยไม่ได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"body": "แก้โจทย์ได้ตลอด (N2)"}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'ล็อกครบทุกช่องแล้วยังแก้ชื่อ/รายละเอียดได้ (N2)');

-- ---------------------------------------------------------------------------
-- กำหนดส่ง/วันปิดรับ (M1/M2 มาใน P4-03) และรูปแบบก้อนข้อมูล
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"due_at": "2026-11-11T13:00:00Z"}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'เปลี่ยนกำหนดส่งในรอบนี้ไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"close_at": "2026-11-20T13:00:00Z"}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ตั้งวันปิดรับในรอบนี้ไม่ได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"due_at": "2026-11-10T20:00:00+07:00", "close_at": null}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'ส่งกำหนดส่ง/วันปิดรับค่าเดิมมาได้ (เขียนเวลาไทยก็เท่ากัน)');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur() - 'due_at' - 'close_at', pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'ไม่ส่งกำหนดส่ง/วันปิดรับ = คงค่าเดิม');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"kind": "announcement"}') - 'full_score' - 'late_penalty_pct' - 'reward_tokens' - 'due_at' - 'close_at' - 'accept_after_solution',
                    pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'N2: เปลี่ยนการบ้านเป็นประกาศไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a', '{"kind": "announcement", "title": "ประกาศ", "body": "x", "full_score": 10}', 2, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'ประกาศรับข้อมูลงานไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a', '{"kind": "homework", "title": "ประกาศ"}', 2, gen_random_uuid()) $$,
  'P0001', 'invalid_request', 'N2: เปลี่ยนประกาศเป็นการบ้านไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a', '{"kind": "announcement", "title": "ประกาศ", "body": "  "}', 2, gen_random_uuid()) $$,
  'P0001', 'post_body_required', 'ประกาศต้องมีข้อความ');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a', '{"kind": "announcement", "title": "  ", "body": "x"}', 2, gen_random_uuid()) $$,
  'P0001', 'post_title_invalid', 'ชื่อว่างไม่ได้');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"full_score": 0}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'full_score_invalid', 'คะแนนเต็มต่ำกว่า 1 ไม่ได้ (ตรวจก่อนถึงตัวกันล็อก)');
select throws_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"reward_tokens": -1}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'P0001', 'reward_tokens_invalid', 'โทเคนติดลบไม่ได้');
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000a', '{"kind": "announcement", "body": "แก้แค่ข้อความ"}', 2, gen_random_uuid()) $$,
  'ไม่ส่งชื่อ = คงชื่อเดิม');
select is((select title || ' / ' || body from public.posts where id = '8c000000-0000-4000-8000-00000000000a'), 'ประกาศเดิม / แก้แค่ข้อความ',
  'ประกาศ: แก้ข้อความแล้วชื่อคงเดิม');

-- ไม่จำกัดตามสถานะภาคเรียน (N2: หลังจบภาคเรียนครูยังแก้ได้)
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp();
set local role authenticated;
select lives_ok($$ select public.update_post('8c000000-0000-4000-8000-00000000000b', pg_temp.cur('{"body": "แก้หลังจบภาคเรียน"}'), pg_temp.ver('8c000000-0000-4000-8000-00000000000b'), gen_random_uuid()) $$,
  'จบภาคเรียนแล้วยังแก้โจทย์ได้');
set local role postgres;
update public.term_control set status = 'active', ended_at = null;
select is((select count(*)::integer from private.operation_receipts where account_id = '3c000000-0000-4000-8000-000000000001'
                                                                    and operation like 'update_post:%') > 0, true,
  'บันทึกผลไว้ใน operation_receipts (กดซ้ำได้ผลเดิม)');

select * from finish();
rollback;
