-- ทดสอบ 0036_wallet_ops: เอฟเฟกต์ได้รับโทเคน (รวมยอด/ตั้งดูแล้วตามรายการ), ปรับยอดมือ (รุ่นยอด, ไม่ติดลบ, คำขอซ้ำ),
-- ข้อมูลรางวัลใน submission_status / teacher_submission_list และยอดใน roster_overview (TECHNICAL_DESIGN ส่วน 7)
-- ข้อมูลสมมติ rollback ตอนจบ
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

select plan(42);

-- ข้อมูลสมมติ: เทอมกระเป๋า T1 + เทอมเก่า T0; ครู + ผู้ดูแล; นักเรียน N1 (ห้อง C1, C0) และ N2 (ห้อง C1) อยู่ในรายชื่อ T1
-- H1 (C1, 2 โทเคน): S1 N1 ทัน · S4 N2 ทัน · H2 (C1, 3): S2 N1 ทัน · H3 (C1, 1): S3 N1 สาย
-- H0 (C0, 2): S0 N1 ทัน ได้รางวัลไปแล้วตอนยังเป็นเทอมปัจจุบัน (เอฟเฟกต์ยังไม่ดู)
insert into public.terms (id, name, status) values ('40360000-0000-4000-8000-000000000001', 'ภาคทดสอบกระเป๋า', 'active');
insert into public.terms (id, name, status, ended_at, superseded_at) values
  ('40360000-0000-4000-8000-000000000002', 'ภาคเก่าทดสอบกระเป๋า', 'superseded', '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z');
insert into public.term_control (term_id) values ('40360000-0000-4000-8000-000000000001')
on conflict (singleton) do update set term_id = excluded.term_id, status = 'active', ended_at = null;
insert into public.teachers (id, display_name) values ('10360000-0000-4000-8000-000000000001', 'ครูกระเป๋า');
insert into public.accounts (id, auth_user_id, provider, provider_subject, email, role, teacher_id) values
  ('30360000-0000-4000-8000-000000000001', '20360000-0000-4000-8000-000000000001', 'google', 'wo-1', 't36@example.com', 'teacher', '10360000-0000-4000-8000-000000000001'),
  ('30360000-0000-4000-8000-000000000002', '20360000-0000-4000-8000-000000000002', 'google', 'wo-2', 'a36@example.com', 'admin', null),
  ('30360000-0000-4000-8000-000000000011', '20360000-0000-4000-8000-000000000011', 'google', 'wo-11', 's1-36@example.com', 'student', null),
  ('30360000-0000-4000-8000-000000000012', '20360000-0000-4000-8000-000000000012', 'google', 'wo-12', 's2-36@example.com', 'student', null);
insert into public.students (id, student_code, display_name, account_id) values
  ('60360000-0000-4000-8000-000000000001', '93600000000361', 'หนึ่ง กระเป๋า', '30360000-0000-4000-8000-000000000011'),
  ('60360000-0000-4000-8000-000000000002', '93600000000362', 'สอง กระเป๋า', '30360000-0000-4000-8000-000000000012');
insert into public.roster_entries (term_id, student_id, group_name, roll_number) values
  ('40360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000001', 'ทดสอบ36', 1),
  ('40360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000002', 'ทดสอบ36', 2);
insert into public.classrooms (id, term_id, teacher_id, name, join_code) values
  ('70360000-0000-4000-8000-000000000001', '40360000-0000-4000-8000-000000000001', '10360000-0000-4000-8000-000000000001', 'เคมีกระเป๋า', 'ZZZZ37'),
  ('70360000-0000-4000-8000-000000000002', '40360000-0000-4000-8000-000000000002', '10360000-0000-4000-8000-000000000001', 'เคมีกระเป๋าเก่า', 'ZZZZ38');
insert into public.memberships (classroom_id, student_id) values
  ('70360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000001'),
  ('70360000-0000-4000-8000-000000000002', '60360000-0000-4000-8000-000000000001'),
  ('70360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000002');
insert into public.posts (id, classroom_id, kind, title, published_at) values
  ('80360000-0000-4000-8000-000000000001', '70360000-0000-4000-8000-000000000001', 'homework', 'H1', '2026-09-20T01:00:00Z'),
  ('80360000-0000-4000-8000-000000000002', '70360000-0000-4000-8000-000000000001', 'homework', 'H2', '2026-09-20T01:00:00Z'),
  ('80360000-0000-4000-8000-000000000003', '70360000-0000-4000-8000-000000000001', 'homework', 'H3', '2026-09-20T01:00:00Z'),
  ('80360000-0000-4000-8000-000000000004', '70360000-0000-4000-8000-000000000002', 'homework', 'H0', '2026-04-20T01:00:00Z');
insert into public.assignments (post_id, full_score, due_at, reward_tokens) values
  ('80360000-0000-4000-8000-000000000001', 10, '2026-09-30T13:00:00Z', 2),
  ('80360000-0000-4000-8000-000000000002', 10, '2026-09-30T13:00:00Z', 3),
  ('80360000-0000-4000-8000-000000000003', 10, '2026-09-30T13:00:00Z', 1),
  ('80360000-0000-4000-8000-000000000004', 10, '2026-04-30T13:00:00Z', 2);
insert into public.submissions (id, assignment_id, student_id, first_submitted_at, last_submitted_at, first_after_solution, reward_granted) values
  ('50360000-0000-4000-8000-000000000001', '80360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false, false),
  ('50360000-0000-4000-8000-000000000002', '80360000-0000-4000-8000-000000000002', '60360000-0000-4000-8000-000000000001', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false, false),
  ('50360000-0000-4000-8000-000000000003', '80360000-0000-4000-8000-000000000003', '60360000-0000-4000-8000-000000000001', '2026-10-01T01:00:00Z', '2026-10-01T01:00:00Z', false, false),
  ('50360000-0000-4000-8000-000000000004', '80360000-0000-4000-8000-000000000001', '60360000-0000-4000-8000-000000000002', '2026-09-29T01:00:00Z', '2026-09-29T01:00:00Z', false, false),
  ('50360000-0000-4000-8000-000000000000', '80360000-0000-4000-8000-000000000004', '60360000-0000-4000-8000-000000000001', '2026-04-29T01:00:00Z', '2026-04-29T01:00:00Z', false, true);
-- ยอดของเทอมเก่า (ต้องไม่ถูกแตะ)
insert into public.wallets (student_id, term_id, balance) values
  ('60360000-0000-4000-8000-000000000001', '40360000-0000-4000-8000-000000000002', 7);

create temp table res (label text primary key, body jsonb) on commit drop;
grant select, insert on res to authenticated;
create function pg_temp.r(p_label text) returns jsonb language sql stable as $$ select body from res where label = p_label $$;
grant execute on function pg_temp.r(text) to authenticated;
create function pg_temp.as_user(p_sub text) returns void language sql as
  $$ select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true) $$;
grant execute on function pg_temp.as_user(text) to authenticated;
create function pg_temp.st(n integer) returns uuid language sql immutable as
  $$ select ('60360000-0000-4000-8000-00000000000' || n)::uuid $$;
grant execute on function pg_temp.st(integer) to authenticated;
create function pg_temp.sub(n integer) returns uuid language sql immutable as
  $$ select ('50360000-0000-4000-8000-00000000000' || n)::uuid $$;
grant execute on function pg_temp.sub(integer) to authenticated;
create function pg_temp.post(n integer) returns uuid language sql immutable as
  $$ select ('80360000-0000-4000-8000-00000000000' || n)::uuid $$;
grant execute on function pg_temp.post(integer) to authenticated;
-- ตรวจผ่านด้วย request key ใหม่ (ไฟล์รุ่น 1)
create function pg_temp.pass(n integer) returns jsonb language sql as $$
  select public.grade_submission(pg_temp.sub(n), 9, true, null, null, 1,
           coalesce((select g.version from public.grades g where g.submission_id = pg_temp.sub(n)), 0), gen_random_uuid())
$$;
grant execute on function pg_temp.pass(integer) to authenticated;
-- แถวของนักเรียน n ในผลรายชื่อ T05 / T03
create function pg_temp.roster(n integer) returns jsonb language sql as $$
  select jsonb_build_array(x -> 'wallet_balance', x -> 'wallet_version')
    from jsonb_array_elements(public.roster_overview()) x where (x ->> 'student_id')::uuid = pg_temp.st(n)
$$;
grant execute on function pg_temp.roster(integer) to authenticated;
create function pg_temp.trow(p_post integer, n integer) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.teacher_submission_list(pg_temp.post(p_post)) -> 'rows') x
   where (x ->> 'student_id')::uuid = pg_temp.st(n)
$$;
grant execute on function pg_temp.trow(integer, integer) to authenticated;
-- ยอด [balance, version] ของนักเรียน n ในเทอมกระเป๋า T1 (ไม่มีแถว = null)
create function pg_temp.w(n integer) returns jsonb language sql stable as $$
  select jsonb_build_array(w.balance, w.version) from public.wallets w
   where w.student_id = pg_temp.st(n) and w.term_id = '40360000-0000-4000-8000-000000000001'
$$;
grant execute on function pg_temp.w(integer) to authenticated;
create function pg_temp.adj(n integer, p_delta integer, p_version integer) returns jsonb language sql as $$
  select public.wallet_adjust(pg_temp.st(n), p_delta, p_version, gen_random_uuid())
$$;
grant execute on function pg_temp.adj(integer, integer, integer) to authenticated;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- ก: ข้อมูลรางวัลฝั่งครู (T03) ก่อนและหลังตรวจผ่าน
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20360000-0000-4000-8000-000000000001');
select is((select jsonb_build_array(l -> 'reward_tokens', l -> 'current_term')
             from public.teacher_submission_list(pg_temp.post(1)) l),
  '[2, true]'::jsonb, 'T03: โทเคนของงานและงานอยู่ในเทอมกระเป๋าปัจจุบัน');
select is(pg_temp.trow(1, 1) -> 'reward_granted', 'false'::jsonb, 'T03: ก่อนตรวจผ่าน reward_granted = false');
select is(public.teacher_submission_list(pg_temp.post(4)) -> 'current_term', 'false'::jsonb,
  'T03: งานของห้องเทอมก่อน current_term = false (ผลที่คาด “งานเทอมเก่า”)');
select is(pg_temp.trow(3, 1) -> 'timing', '"late"'::jsonb, 'T03: งานส่งสายยังบอก timing ให้แสดง “ส่งสาย”');

select is(pg_temp.pass(1) -> 'reward_tokens_granted', '2'::jsonb, 'ตรวจผ่าน S1 ได้ 2');
select is(pg_temp.pass(2) -> 'reward_tokens_granted', '3'::jsonb, 'ตรวจผ่าน S2 ได้ 3');
select is(pg_temp.trow(1, 1) -> 'reward_granted', 'true'::jsonb, 'T03: หลังตรวจผ่าน reward_granted = true (ผลที่คาด “ได้แล้ว”)');
select ok(pg_temp.trow(1, 1) ?& array['student_id', 'roll_number', 'display_name', 'member', 'submission_id',
  'first_submitted_at', 'last_submitted_at', 'content_revision', 'timing', 'graded', 'file_count'],
  'T03: ฟิลด์เดิมของแถวยังอยู่ครบ');

-- ---------------------------------------------------------------------------
-- ข: สถานะงานของนักเรียน (S03)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('20360000-0000-4000-8000-000000000011');
select is((select jsonb_build_array(s -> 'reward_tokens', s -> 'reward_granted', s -> 'current_term')
             from public.submission_status(pg_temp.post(1)) s),
  '[2, true, true]'::jsonb, 'S03: งานครบถ้วน · ได้รับ 2 โทเคนแล้ว');
select is((select jsonb_build_array(s -> 'reward_tokens', s -> 'reward_granted', s -> 'current_term')
             from public.submission_status(pg_temp.post(3)) s),
  '[1, false, true]'::jsonb, 'S03: งานสายยังไม่ได้โทเคน');
select is(public.submission_status(pg_temp.post(4)) -> 'current_term', 'false'::jsonb,
  'S03: งานห้องเทอมก่อน current_term = false (“งานภาคเรียนก่อน”)');
select ok(public.submission_status(pg_temp.post(1)) ?& array['intake', 'outcome', 'blocked', 'submission', 'permission_open'],
  'S03: ฟิลด์เดิมยังอยู่ครบ');

-- ---------------------------------------------------------------------------
-- ค: เอฟเฟกต์ได้รับโทเคน — รวมยอดครั้งเดียว ตั้งดูแล้วเฉพาะรายการที่แสดง
-- ---------------------------------------------------------------------------
select is(public.reward_effects(),
  jsonb_build_object('tokens', 5, 'works', 2, 'submission_ids', jsonb_build_array(pg_temp.sub(1), pg_temp.sub(2))),
  'เอฟเฟกต์ค้าง: +5 โทเคน จาก 2 งาน (งานเทอมก่อนที่ยังไม่ดูไม่นับ)');
select is(public.mark_reward_effect_seen(array[pg_temp.sub(1)]), '{"marked": 1}'::jsonb, 'ตั้งดูแล้ว 1 งาน');
select is(public.reward_effects() -> 'tokens', '3'::jsonb, 'เหลือเอฟเฟกต์ +3 จากงานที่ยังไม่ได้แสดง');
select is(public.mark_reward_effect_seen(array[pg_temp.sub(1), pg_temp.sub(2), pg_temp.sub(4), pg_temp.sub(3),
                                               gen_random_uuid()]),
  '{"marked": 1}'::jsonb, 'รายการปน (ดูแล้ว / ของคนอื่น / ยังไม่ได้รางวัล / ไม่มีจริง) ตั้งเฉพาะของตนที่ค้าง');
select is(public.reward_effects(), '{"tokens": 0, "works": 0, "submission_ids": []}'::jsonb, 'ไม่มีเอฟเฟกต์ค้าง');
select is(public.mark_reward_effect_seen(array[pg_temp.sub(1), pg_temp.sub(2)]), '{"marked": 0}'::jsonb,
  'เรียกซ้ำได้ ไม่มีผลเพิ่ม');
select throws_ok($$ select public.mark_reward_effect_seen(array[]::uuid[]) $$, 'P0001', 'invalid_request',
  'รายการว่าง → invalid_request');
select throws_ok($$ select public.wallet_adjust(pg_temp.st(1), 1, 2, gen_random_uuid()) $$, 'P0001', 'forbidden',
  'นักเรียนปรับยอดไม่ได้');

select pg_temp.as_user('20360000-0000-4000-8000-000000000012');
select is(public.reward_effects() -> 'works', '0'::jsonb, 'นักเรียนอื่นไม่เห็นเอฟเฟกต์ของเพื่อน');

select pg_temp.as_user('20360000-0000-4000-8000-000000000001');
select throws_ok($$ select public.reward_effects() $$, 'P0001', 'forbidden', 'ครูเรียก reward_effects ไม่ได้');
select throws_ok($$ select public.mark_reward_effect_seen(array[pg_temp.sub(4)]) $$, 'P0001', 'forbidden',
  'ครูตั้งดูแล้วแทนนักเรียนไม่ได้');

-- ---------------------------------------------------------------------------
-- ง: ปรับยอดมือ — รุ่นยอด, ไม่ติดลบ, คำขอซ้ำ, สิทธิ์
-- ---------------------------------------------------------------------------
select is(pg_temp.roster(1), '[5, 2]'::jsonb, 'T05: ยอด 5 รุ่น 2 ของ N1');
select is(pg_temp.roster(2), '[0, 0]'::jsonb, 'T05: ยังไม่มีแถวกระเป๋า = ยอด 0 รุ่น 0');

insert into res values ('a1', public.wallet_adjust(pg_temp.st(2), 3, 0, 'c0360000-0000-4000-8000-000000000001'));
select is(pg_temp.r('a1') - 'student_id' - 'term_id', '{"balance": 3, "version": 1}'::jsonb, 'เพิ่ม 3 จากยอดว่าง → 3 รุ่น 1');
select is(public.wallet_adjust(pg_temp.st(2), 3, 0, 'c0360000-0000-4000-8000-000000000001'), pg_temp.r('a1'),
  'คำขอซ้ำด้วย request key เดิมคืนผลเดิม ไม่เพิ่มซ้ำ');
select throws_ok($$ select public.wallet_adjust(pg_temp.st(2), 4, 0, 'c0360000-0000-4000-8000-000000000001') $$,
  'P0001', 'request_key_conflict', 'request key เดิมแต่จำนวนต่าง → request_key_conflict');
select throws_ok($$ select pg_temp.adj(2, 1, 0) $$, 'P0001', 'stale_revision', 'รุ่นยอดเก่า (หน้าจออื่นปรับแล้ว) → stale_revision');

select throws_ok($$ select pg_temp.adj(1, -6, 2) $$, 'P0001', 'insufficient_balance', 'ลดเกินยอด → insufficient_balance');
select is(pg_temp.adj(1, -5, 2) - 'student_id' - 'term_id', '{"balance": 0, "version": 3}'::jsonb, 'ลดจนเหลือ 0 ได้');
select throws_ok($$ select pg_temp.adj(1, -1, 3) $$, 'P0001', 'insufficient_balance', 'ยอด 0 ลดต่อไม่ได้ (ไม่ติดลบ)');

-- ตรวจผ่านหลังปรับมือ: รุ่นยอดเพิ่ม ปรับด้วยรุ่นที่เห็นก่อนตรวจจึงถูกปฏิเสธ
select is(pg_temp.pass(4) -> 'wallet_balance', '5'::jsonb, 'ตรวจผ่าน S4 ต่อยอดที่ปรับมือ (3 + 2)');
select throws_ok($$ select pg_temp.adj(2, -1, 1) $$, 'P0001', 'stale_revision', 'รุ่นก่อนตรวจผ่าน → stale_revision');

select throws_ok($$ select pg_temp.adj(1, 0, 3) $$, 'P0001', 'invalid_request', 'จำนวน 0 → invalid_request');
select throws_ok($$ select pg_temp.adj(1, 1001, 3) $$, 'P0001', 'invalid_request', 'เกิน 1,000 ต่อครั้ง → invalid_request');
select throws_ok($$ select public.wallet_adjust(pg_temp.st(1), 1, 3, null) $$, 'P0001', 'request_key_required',
  'ไม่มี request key → request_key_required');
select throws_ok($$ select public.wallet_adjust(gen_random_uuid(), 1, 0, gen_random_uuid()) $$, 'P0001', 'student_not_found',
  'ไม่พบนักเรียน → student_not_found');

select pg_temp.as_user('20360000-0000-4000-8000-000000000002');
select throws_ok($$ select pg_temp.adj(1, 1, 3) $$, 'P0001', 'admin_mode_required', 'ผู้ดูแลนอกโหมดผู้ดูแลปรับไม่ได้');
select is(public.wallet_adjust(pg_temp.st(1), 2, 3, gen_random_uuid(), true) -> 'balance', '2'::jsonb,
  'ผู้ดูแลในโหมดผู้ดูแลปรับได้');

-- จบภาคเรียนแล้ว (K5) ยังปรับได้ — ปรับเฉพาะเทอมกระเป๋าปัจจุบัน
set local role postgres;
update public.term_control set status = 'ended', ended_at = clock_timestamp() where singleton;
set local role authenticated;
select pg_temp.as_user('20360000-0000-4000-8000-000000000001');
select is(pg_temp.adj(1, 1, 4) - 'student_id' - 'term_id', '{"balance": 3, "version": 5}'::jsonb,
  'จบภาคเรียนแล้วครูยังปรับยอดได้');
select is((select w.balance from public.wallets w
            where w.student_id = pg_temp.st(1) and w.term_id = '40360000-0000-4000-8000-000000000002'),
  7, 'ยอดของเทอมเก่าไม่ถูกแตะ');

select * from finish();
rollback;
