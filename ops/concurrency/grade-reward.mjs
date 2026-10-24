// P5-02 (ก): grade_submission ผ่านพร้อมกัน → โทเคนเพิ่มครั้งเดียว — Postgres ในเครื่องเท่านั้น (local-db.mjs)
// แต่ละรอบใช้นักเรียนใหม่ 1 คน งาน 3 งาน (2, 3, 4 โทเคน) ส่งทันทุกงาน แล้วยิงสองการเชื่อมต่อพร้อมกัน:
//   B  ตรวจผ่านงาน a กับ b ของนักเรียนคนเดียวกันพร้อมกัน ขณะยังไม่มีแถวกระเป๋า → สำเร็จทั้งคู่ ยอด 5 (ไม่หาย ไม่ซ้ำ)
//      และตัวหนึ่งต้องรออีกตัว commit (ชนแถวกระเป๋าจริง) — วัดจากเวลาที่ทั้งสองจบห่างกัน ≥ 0.25 วินาที
//   A  ตรวจผ่านงาน c ตัวเดียวกันพร้อมกัน (ทั้งคู่เห็นว่ายังไม่เคยตรวจ) → สำเร็จ 1 อีกตัว stale_revision ยอด 9 รุ่น 3
// ข้อมูลสมมติสร้างแล้ว commit ในฐานข้อมูลในเครื่อง และลบทิ้งตอนจบ (รวมเมื่อมีรอบล้ม)
// ใช้: node ops/concurrency/grade-reward.mjs [--rounds 10]   (ต้อง npm run db:start ก่อน)
import { psqlOk, race, requireLocalDb, sqlText } from './local-db.mjs'

const roundsArg = process.argv.indexOf('--rounds')
const ROUNDS = roundsArg > 0 ? Number(process.argv[roundsArg + 1]) : 10
if (!Number.isInteger(ROUNDS) || ROUNDS < 1) throw new Error('--rounds ต้องเป็นจำนวนเต็มบวก')

requireLocalDb()

// ครู + ห้องในเทอมกระเป๋าปัจจุบัน + ต่อรอบ: นักเรียน 1 งาน 3 งานส่ง 3 (ทันทั้งหมด) — คืน JSON ของ id
const [fixture] = await psqlOk(`
with t as (insert into public.teachers (display_name) values ('ครูทดสอบพร้อมกัน') returning id),
acc as (
  insert into public.accounts (auth_user_id, provider, provider_subject, email, role, teacher_id)
  select gen_random_uuid(), 'google', 'race-' || gen_random_uuid(), 'race-' || left(md5(random()::text), 8) || '@example.com',
         'teacher', t.id from t
  returning auth_user_id, id, teacher_id),
c as (
  insert into public.classrooms (term_id, teacher_id, name, join_code)
  select tc.term_id, acc.teacher_id, 'ห้องทดสอบพร้อมกัน', private.new_join_code() from public.term_control tc, acc
  returning id),
st as (
  insert into public.students (student_code, display_name)
  select '99' || lpad((floor(random() * 1e12))::bigint::text, 12, '0') || n, 'นักเรียนทดสอบพร้อมกัน ' || n
    from generate_series(1, ${ROUNDS}) n
  returning id),
p as (
  insert into public.posts (classroom_id, kind, title, published_at)
  select c.id, 'homework', 'งานทดสอบพร้อมกัน ' || k, clock_timestamp() - interval '2 days'
    from c, st, generate_series(1, 3) k
  returning id, title),
a as (
  insert into public.assignments (post_id, full_score, due_at, reward_tokens)
  select p.id, 10, date_trunc('minute', clock_timestamp()) + interval '1 day', right(p.title, 1)::integer + 1 from p
  returning post_id, reward_tokens),
s as (
  -- งาน k ของนักเรียนลำดับ i: จับคู่ด้วยลำดับแถว (ทุกนักเรียนได้งาน 2, 3, 4 โทเคนครบชุด)
  insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at)
  select x.post_id, y.id, clock_timestamp() - interval '1 day', clock_timestamp() - interval '1 day'
    from (select a.post_id, a.reward_tokens, row_number() over (partition by a.reward_tokens order by a.post_id) rn from a) x
    join (select st.id, row_number() over (order by st.id) rn from st) y on y.rn = x.rn
  returning id, student_id, assignment_id),
sa as (select s.id, s.student_id, a.reward_tokens tokens from s join a on a.post_id = s.assignment_id)
select json_build_object(
  'auth', (select auth_user_id from acc), 'account', (select id from acc), 'teacher', (select teacher_id from acc),
  'classroom', (select id from c),
  'rounds', (select json_agg(json_build_object('student', g.student_id, 'a', g.a, 'b', g.b, 'c', g.c))
               from (select student_id,
                            max(id::text) filter (where tokens = 2) a, max(id::text) filter (where tokens = 3) b,
                            max(id::text) filter (where tokens = 4) c
                       from sa group by student_id) g))::text;
`)
const fx = JSON.parse(fixture)

const grade = (sub, key) =>
  `public.grade_submission(${sqlText(sub)}::uuid, 9, true, null, null, 1, 0, ${sqlText(key)}::uuid)`
const key = () => crypto.randomUUID()

let failed = 0
try {
  for (const [i, r] of fx.rounds.entries()) {
    const problems = []
    const b = await race(fx.auth, [grade(r.a, key()), grade(r.b, key())])
    if (!b.every((x) => x.ok)) problems.push(`B: คาดสำเร็จทั้งคู่ ได้ ${b.map((x) => x.err ?? 'ok').join(' | ')}`)
    const gapMs = b.every((x) => x.at) ? Math.abs(Date.parse(b[0].at) - Date.parse(b[1].at)) : 0
    if (gapMs < 250) problems.push(`B: ไม่ได้รอกันจริง (จบห่างกัน ${gapMs} ms)`)

    const a = await race(fx.auth, [grade(r.c, key()), grade(r.c, key())])
    const wins = a.filter((x) => x.ok)
    const stale = a.filter((x) => !x.ok && /stale_revision/.test(x.err))
    if (wins.length !== 1 || stale.length !== 1) {
      problems.push(`A: คาดสำเร็จ 1 + stale_revision 1 ได้ ${a.map((x) => x.err ?? 'ok').join(' | ')}`)
    }

    const [state] = await psqlOk(`
select json_build_object(
  'wallet', (select json_build_array(w.balance, w.version) from public.wallets w
              join public.term_control tc on tc.term_id = w.term_id where w.student_id = ${sqlText(r.student)}::uuid),
  'granted', (select count(*) from public.submissions s
               where s.student_id = ${sqlText(r.student)}::uuid and s.reward_granted))::text;`)
    const st = JSON.parse(state)
    if (JSON.stringify(st.wallet) !== '[9,3]' || st.granted !== 3) {
      problems.push(`ยอด/รุ่น ${JSON.stringify(st.wallet)} (คาด [9,3]) reward_granted ${st.granted}/3`)
    }
    if (problems.length) failed++
    console.log(`รอบ ${i + 1}: ${problems.length ? 'ล้ม — ' + problems.join('; ') : `ผ่าน (B รอกัน ${gapMs} ms, ยอด 9 รุ่น 3)`}`)
  }
} finally {
  const ids = fx.rounds.map((r) => sqlText(r.student)).join(', ')
  await psqlOk(`
begin;
delete from private.operation_receipts where account_id = ${sqlText(fx.account)}::uuid;
delete from public.grades where submission_id in (select id from public.submissions where student_id in (${ids}));
delete from public.submissions where student_id in (${ids});
delete from public.wallets where student_id in (${ids});
delete from public.posts where classroom_id = ${sqlText(fx.classroom)}::uuid;
delete from public.classrooms where id = ${sqlText(fx.classroom)}::uuid;
delete from public.students where id in (${ids});
delete from public.accounts where id = ${sqlText(fx.account)}::uuid;
delete from public.teachers where id = ${sqlText(fx.teacher)}::uuid;
commit;`)
}

console.log(`สรุป: ${fx.rounds.length - failed}/${fx.rounds.length} รอบผ่าน`)
process.exitCode = failed ? 1 : 0
