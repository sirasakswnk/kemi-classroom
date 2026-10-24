// P5-08 (ค): grade_submission ชน terms_start → ยอดไม่ผิด — Postgres ในเครื่องเท่านั้น (local-db.mjs)
// แต่ละรอบสร้างห้องใหม่ในเทอมปัจจุบัน + นักเรียน 1 คนส่งงาน (2 โทเคน) ทันแล้ว แล้วยิงสองการเชื่อมต่อพร้อมกัน:
// ครูตรวจผ่านงานนั้น กับครูกดเริ่มภาคเรียนใหม่ — สลับให้ฝั่งหนึ่งออกตัวช้า 0.1 วินาทีเพื่อบังคับลำดับทั้งสองแบบ
//   ตรวจก่อน  → ได้ 2 โทเคนเข้ายอดเทอมเดิม (แล้วยอดนั้นถูกล้างพร้อมเทอมเดิม) ยอดเทอมใหม่ไม่มี
//   เริ่มก่อน → ตรวจเห็นเทอมใหม่ งานอยู่เทอมเก่าจึงไม่ให้โทเคน (I5) ไม่มียอดทั้งสองเทอม
//   ทั้งสองแบบ: สำเร็จทั้งคู่, คะแนนบันทึก, ตัวหนึ่งต้องรออีกตัว commit (ชน term_control จริง) — วัดจากเวลาจบ
// ตัวควบคุมบวก: หลังจบทุกรอบ ใส่ยอดเทอมใหม่ปลอมให้นักเรียนรอบแรก แล้วตัวตรวจต้องรายงานว่าผิด
// ข้อมูลสมมติ commit ในฐานข้อมูลในเครื่อง แล้วลบทิ้งและคืนภาคเรียนเดิมตอนจบ (รวมเมื่อมีข้อผิดพลาด)
// ใช้: node ops/concurrency/term-start.mjs [--rounds 10]   (ต้อง npm run db:start ก่อน)
import { psqlOk, race, requireLocalDb, sqlText } from './local-db.mjs'

const roundsArg = process.argv.indexOf('--rounds')
const ROUNDS = roundsArg > 0 ? Number(process.argv[roundsArg + 1]) : 10
if (!Number.isInteger(ROUNDS) || ROUNDS < 1) throw new Error('--rounds ต้องเป็นจำนวนเต็มบวก')

requireLocalDb()

// ภาคเรียนเดิม (คืนค่าตอนจบ) + ครู
const [saved] = await psqlOk(`
select json_build_object('control', row_to_json(c), 'term', row_to_json(t))::text
  from public.term_control c join public.terms t on t.id = c.term_id where c.singleton;`)
const orig = JSON.parse(saved)
const [teacher] = await psqlOk(`
with t as (insert into public.teachers (display_name) values ('ครูทดสอบเริ่มเทอม') returning id),
acc as (
  insert into public.accounts (auth_user_id, provider, provider_subject, email, role, teacher_id)
  select gen_random_uuid(), 'google', 'race-term-' || gen_random_uuid(),
         'race-term-' || left(md5(random()::text), 8) || '@example.com', 'teacher', t.id from t
  returning auth_user_id, id, teacher_id)
select json_build_object('auth', auth_user_id, 'account', id, 'teacher', teacher_id)::text from acc;`)
const fx = JSON.parse(teacher)
const tag = Math.random().toString(36).slice(2, 8)
const rounds = []
const terms = []

// ห้องใหม่ในเทอมปัจจุบัน + นักเรียน + การบ้าน 2 โทเคน (กำหนดพรุ่งนี้) + งานส่งทัน
async function setupRound(i) {
  const [row] = await psqlOk(`
with c as (
  insert into public.classrooms (term_id, teacher_id, name, join_code)
  select tc.term_id, ${sqlText(fx.teacher)}::uuid, 'ห้องทดสอบเริ่มเทอม ${i}', private.new_join_code()
    from public.term_control tc where tc.singleton
  returning id, term_id),
st as (
  insert into public.students (student_code, display_name)
  values ('97' || lpad((floor(random() * 1e12))::bigint::text, 12, '0') || ${i}, 'นักเรียนทดสอบเริ่มเทอม ${i}')
  returning id),
p as (
  insert into public.posts (classroom_id, kind, title, published_at)
  select c.id, 'homework', 'งานทดสอบเริ่มเทอม', clock_timestamp() - interval '2 days' from c
  returning id),
a as (
  insert into public.assignments (post_id, full_score, due_at, reward_tokens)
  select p.id, 10, date_trunc('minute', clock_timestamp()) + interval '1 day', 2 from p
  returning post_id),
s as (
  insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at)
  select a.post_id, st.id, clock_timestamp() - interval '1 day', clock_timestamp() - interval '1 day' from a, st
  returning id, student_id)
select json_build_object('classroom', (select id from c), 'term', (select term_id from c),
                         'student', (select student_id from s), 'sub', (select id from s))::text;`)
  return JSON.parse(row)
}

// ยอดหลังรอบ: ทั้งสองฝั่งสำเร็จแล้ว term_control ชี้เทอมใหม่
async function stateOf(r) {
  const [row] = await psqlOk(`
select json_build_object(
  'old', (select w.balance from public.wallets w where w.student_id = ${sqlText(r.student)}::uuid and w.term_id = ${sqlText(r.term)}::uuid),
  'new', (select w.balance from public.wallets w join public.term_control tc on tc.singleton and tc.term_id = w.term_id
           where w.student_id = ${sqlText(r.student)}::uuid),
  'granted', (select s.reward_granted from public.submissions s where s.id = ${sqlText(r.sub)}::uuid),
  'graded', (select g.raw_score = 9 and g.passed from public.grades g where g.submission_id = ${sqlText(r.sub)}::uuid))::text;`)
  return JSON.parse(row)
}

function check(r, gradeFirst, st) {
  const problems = []
  if (st.graded !== true) problems.push('คะแนนไม่ถูกบันทึก')
  if (st.new !== null) problems.push(`มียอดเทอมใหม่ ${st.new} (คาดไม่มี)`)
  const want = gradeFirst ? { old: 2, granted: true } : { old: null, granted: false }
  if (st.old !== want.old || st.granted !== want.granted) {
    problems.push(`ยอดเทอมเดิม ${st.old} reward_granted ${st.granted} (คาด ${want.old} / ${want.granted})`)
  }
  return problems
}

const delayed = (expr) => `(select ${expr} from pg_sleep(0.1))`
const key = () => crypto.randomUUID()

let failed = 0
try {
  for (let i = 1; i <= ROUNDS; i++) {
    const r = await setupRound(i)
    rounds.push(r)
    const gradeFirst = i % 2 === 1
    const grade = `public.grade_submission(${sqlText(r.sub)}::uuid, 9, true, null, null, 1, 0, ${sqlText(key())}::uuid)`
    const start = `public.terms_start(${sqlText(`ภาคทดสอบพร้อมกัน ${tag}-${i}`)}, ${sqlText(r.term)}::uuid, ${sqlText(key())}::uuid)`
    const [g, s] = await race(fx.auth, gradeFirst ? [grade, delayed(start)] : [delayed(grade), start])
    if (s.ok) terms.push(s.json.term_id)

    const problems = []
    if (!g.ok || !s.ok) problems.push(`คาดสำเร็จทั้งคู่ ได้ ตรวจ: ${g.err ?? 'ok'} | เริ่มเทอม: ${s.err ?? 'ok'}`)
    const gapMs = g.at && s.at ? Date.parse(gradeFirst ? s.at : g.at) - Date.parse(gradeFirst ? g.at : s.at) : 0
    if (gapMs < 250) problems.push(`ตัวที่ออกตัวช้าไม่ได้รออีกตัว commit (จบหลังกัน ${gapMs} ms)`)
    if (g.ok && (g.json.reward_tokens_granted ?? 0) !== (gradeFirst ? 2 : 0)) {
      problems.push(`ผลตรวจบอกได้ ${g.json.reward_tokens_granted} โทเคน`)
    }
    problems.push(...check(r, gradeFirst, await stateOf(r)))
    if (problems.length) failed++
    const order = gradeFirst ? 'ตรวจก่อน → +2 เทอมเดิม' : 'เริ่มเทอมก่อน → ไม่ให้ (I5)'
    console.log(`รอบ ${i} (${order}): ${problems.length ? 'ล้ม — ' + problems.join('; ') : `ผ่าน (รอกัน ${gapMs} ms)`}`)
  }

  // ตัวควบคุมบวก: ยอดเทอมใหม่ปลอมของนักเรียนรอบแรก ต้องถูกตัวตรวจจับได้
  const r1 = rounds[0]
  await psqlOk(`insert into public.wallets (student_id, term_id, balance)
select ${sqlText(r1.student)}::uuid, tc.term_id, 2 from public.term_control tc where tc.singleton;`)
  const caught = check(r1, true, await stateOf(r1))
  await psqlOk(`delete from public.wallets w using public.term_control tc
 where tc.singleton and w.term_id = tc.term_id and w.student_id = ${sqlText(r1.student)}::uuid;`)
  if (caught.length === 0) {
    failed++
    console.log('ตัวควบคุมบวก: ล้ม — ตัวตรวจไม่จับยอดเทอมใหม่ปลอม')
  } else {
    console.log(`ตัวควบคุมบวก: ผ่าน (ตัวตรวจรายงาน “${caught.join('; ')}”)`)
  }
} finally {
  const students = rounds.map((r) => sqlText(r.student)).join(', ') || 'null'
  const classrooms = rounds.map((r) => sqlText(r.classroom)).join(', ') || 'null'
  const created = terms.map((t) => sqlText(t)).join(', ') || 'null'
  const c = orig.control
  const t = orig.term
  await psqlOk(`
begin;
delete from private.operation_receipts where account_id = ${sqlText(fx.account)}::uuid;
delete from public.grades where submission_id in (select id from public.submissions where student_id in (${students}));
delete from public.submissions where student_id in (${students});
delete from public.wallets where student_id in (${students});
delete from public.posts where classroom_id in (${classrooms});
delete from public.classrooms where id in (${classrooms});
delete from public.students where id in (${students});
delete from public.accounts where id = ${sqlText(fx.account)}::uuid;
delete from public.teachers where id = ${sqlText(fx.teacher)}::uuid;
update public.term_control
   set term_id = ${sqlText(c.term_id)}::uuid, epoch = ${Number(c.epoch)}, status = ${sqlText(c.status)},
       started_at = ${sqlText(c.started_at)}::timestamptz,
       ended_at = ${c.ended_at === null ? 'null' : `${sqlText(c.ended_at)}::timestamptz`},
       updated_at = ${sqlText(c.updated_at)}::timestamptz
 where singleton;
update public.terms
   set status = ${sqlText(t.status)},
       ended_at = ${t.ended_at === null ? 'null' : `${sqlText(t.ended_at)}::timestamptz`},
       superseded_at = ${t.superseded_at === null ? 'null' : `${sqlText(t.superseded_at)}::timestamptz`}
 where id = ${sqlText(t.id)}::uuid;
delete from public.terms where id in (${created});
commit;`)
  const [left] = await psqlOk(`
select (select count(*) from public.terms where name like 'ภาคทดสอบพร้อมกัน ${tag}-%') || ' '
    || (select (term_id = ${sqlText(c.term_id)}::uuid and epoch = ${Number(c.epoch)})::text from public.term_control where singleton);`)
  console.log(`เก็บกวาด: เทอมทดสอบที่เหลือ ${left.split(' ')[0]} · คืนภาคเรียนเดิม ${left.split(' ')[1]}`)
}

console.log(`สรุป: ${failed ? `ล้ม ${failed} จุด (รอบ/ตัวควบคุมบวก)` : `ผ่านทั้ง ${ROUNDS} รอบ + ตัวควบคุมบวก`}`)
process.exitCode = failed ? 1 : 0
