// P5-04 (ข): draw_charm สองครั้งพร้อมกัน — Postgres ในเครื่องเท่านั้น (local-db.mjs)
// แต่ละรอบใช้นักเรียนใหม่ 2 คน (บัญชีนักเรียนผูกชื่อแล้ว) ทั้งสองแท็บโหลดอัตราชุดเดียวกันแล้วกดสุ่มพร้อมกัน:
//   A  ยอด 1 สุ่มสองครั้งพร้อมกัน (คนละ request key) → สำเร็จ 1 อีกตัว insufficient_balance ยอด 0 ไม่ติดลบ ได้ 1 ชิ้น
//      และตัวหนึ่งต้องรออีกตัว commit (ชนแถวกระเป๋าจริง) — วัดจากเวลาที่ทั้งสองจบห่างกัน ≥ 0.25 วินาที
//   B  ยอด 2 สุ่มสองครั้งพร้อมกันด้วยอัตราชุดเดียวกัน → สำเร็จ 1 อีกตัว stale_revision (ของที่เหลือเปลี่ยนแล้ว
//      ต้องโหลดอัตราใหม่ ไม่สุ่มด้วยอัตราที่ไม่ได้แสดง) ยอด 1 ได้ 1 ชิ้น
//   C  ต่อจาก B (ยอด 1) ส่ง request key เดียวกันสองครั้งพร้อมกัน (กดซ้ำ/ส่งซ้ำ) → ได้ผลเดียวกันทั้งคู่ หักครั้งเดียว
//      ยอด 0 ได้ 2 ชิ้นไม่ซ้ำ
// ข้อมูลสมมติสร้างแล้ว commit ในฐานข้อมูลในเครื่อง และลบทิ้งตอนจบ (รวมเมื่อมีรอบล้ม)
// ใช้: node ops/concurrency/draw-charm.mjs [--rounds 10]   (ต้อง npm run db:start ก่อน และมี seed เครื่องราง)
import { psqlOk, race, requireLocalDb, sqlText } from './local-db.mjs'

const roundsArg = process.argv.indexOf('--rounds')
const ROUNDS = roundsArg > 0 ? Number(process.argv[roundsArg + 1]) : 10
if (!Number.isInteger(ROUNDS) || ROUNDS < 1) throw new Error('--rounds ต้องเป็นจำนวนเต็มบวก')

requireLocalDb()

const [catalog] = await psqlOk(`select count(*) from public.charms;`)
if (Number(catalog) < 2) throw new Error('ต้องมีเครื่องรางอย่างน้อย 2 ชิ้น — รัน npm run db:reset (seed) ก่อน')

// ต่อรอบ: นักเรียน 2 คน (a: ยอด 1, b: ยอด 2) พร้อมบัญชีนักเรียนที่ผูกชื่อแล้ว และแถวกระเป๋าในเทอมปัจจุบัน
const [fixture] = await psqlOk(`
with n as (select g, k from generate_series(1, ${ROUNDS}) g, (values ('a', 1), ('b', 2)) v(k, bal)),
acc as (
  insert into public.accounts (auth_user_id, provider, provider_subject, email, role)
  select gen_random_uuid(), 'google', 'race-draw-' || gen_random_uuid(),
         'race-draw-' || left(md5(random()::text), 10) || '@example.com', 'student'
    from n
  returning id, auth_user_id),
acc_n as (select id, auth_user_id, row_number() over (order by id) rn from acc),
n_n as (select g, k, row_number() over (order by g, k) rn from n),
st as (
  insert into public.students (student_code, display_name, account_id)
  select '98' || lpad((floor(random() * 1e11))::bigint::text, 11, '0') || lpad(n_n.rn::text, 3, '0'),
         'นักเรียนสุ่มพร้อมกัน ' || n_n.g || n_n.k, acc_n.id
    from n_n join acc_n using (rn)
  returning id, account_id),
w as (
  insert into public.wallets (student_id, term_id, balance)
  select st.id, tc.term_id, case n_n.k when 'a' then 1 else 2 end
    from st join acc_n on acc_n.id = st.account_id join n_n using (rn), public.term_control tc
  returning student_id)
select json_agg(json_build_object('round', n_n.g, 'kind', n_n.k, 'student', st.id, 'account', acc_n.id,
                                  'auth', acc_n.auth_user_id) order by n_n.g, n_n.k)::text
  from st join acc_n on acc_n.id = st.account_id join n_n using (rn)
 where st.id in (select student_id from w);
`)
const people = JSON.parse(fixture)

// อัตราที่หน้าจอของนักเรียนคนนี้แสดงอยู่ (rates_key)
async function ratesKey(auth) {
  const claims = JSON.stringify({ sub: auth, role: 'authenticated' })
  const lines = await psqlOk(`
begin;
select set_config('request.jwt.claims', ${sqlText(claims)}, true) is null;
set local role authenticated;
select 'KEY ' || (public.get_draw_options() ->> 'rates_key');
commit;`)
  return lines.find((l) => l.startsWith('KEY ')).slice(4)
}

async function state(student) {
  const [row] = await psqlOk(`
select json_build_object(
  'wallet', (select json_build_array(w.balance, w.version) from public.wallets w
              join public.term_control tc on tc.term_id = w.term_id where w.student_id = ${sqlText(student)}::uuid),
  'owned', (select count(*) from public.owned_charms o where o.student_id = ${sqlText(student)}::uuid),
  'distinct', (select count(distinct o.charm_id) from public.owned_charms o
                where o.student_id = ${sqlText(student)}::uuid))::text;`)
  return JSON.parse(row)
}

const draw = (rates, key) => `public.draw_charm(${sqlText(rates)}, ${sqlText(key)}::uuid)`
const key = () => crypto.randomUUID()
const errs = (rs) => rs.map((x) => x.err?.match(/ERROR:\s+(\S+)/)?.[1] ?? x.err ?? 'ok').join(' | ')

let failed = 0
try {
  for (let i = 1; i <= ROUNDS; i++) {
    const a = people.find((p) => p.round === i && p.kind === 'a')
    const b = people.find((p) => p.round === i && p.kind === 'b')
    const problems = []

    // A: ยอด 1 สองแท็บ
    const ra = await ratesKey(a.auth)
    const resA = await race(a.auth, [draw(ra, key()), draw(ra, key())])
    const okA = resA.filter((x) => x.ok)
    const poorA = resA.filter((x) => !x.ok && /insufficient_balance/.test(x.err))
    if (okA.length !== 1 || poorA.length !== 1) problems.push(`A: คาดสำเร็จ 1 + insufficient_balance 1 ได้ ${errs(resA)}`)
    const gapMs = resA.every((x) => x.at) ? Math.abs(Date.parse(resA[0].at) - Date.parse(resA[1].at)) : 0
    if (gapMs < 250) problems.push(`A: ไม่ได้รอกันจริง (จบห่างกัน ${gapMs} ms)`)
    const sa = await state(a.student)
    if (JSON.stringify(sa) !== JSON.stringify({ wallet: [0, 2], owned: 1, distinct: 1 })) {
      problems.push(`A: สถานะ ${JSON.stringify(sa)} (คาด ยอด [0,2] ได้ 1 ชิ้น)`)
    }

    // B: ยอด 2 สองแท็บที่แสดงอัตราชุดเดียวกัน
    const rb = await ratesKey(b.auth)
    const resB = await race(b.auth, [draw(rb, key()), draw(rb, key())])
    const okB = resB.filter((x) => x.ok)
    const staleB = resB.filter((x) => !x.ok && /stale_revision/.test(x.err))
    if (okB.length !== 1 || staleB.length !== 1) problems.push(`B: คาดสำเร็จ 1 + stale_revision 1 ได้ ${errs(resB)}`)
    const sb = await state(b.student)
    if (JSON.stringify(sb) !== JSON.stringify({ wallet: [1, 2], owned: 1, distinct: 1 })) {
      problems.push(`B: สถานะ ${JSON.stringify(sb)} (คาด ยอด [1,2] ได้ 1 ชิ้น)`)
    }

    // C: request key เดียวกันสองครั้งพร้อมกัน
    const rc = await ratesKey(b.auth)
    const same = key()
    const resC = await race(b.auth, [draw(rc, same), draw(rc, same)])
    if (!resC.every((x) => x.ok) || JSON.stringify(resC[0].json) !== JSON.stringify(resC[1].json)) {
      problems.push(`C: คาดผลเดียวกันทั้งคู่ ได้ ${errs(resC)}`)
    }
    const gapC = resC.every((x) => x.at) ? Math.abs(Date.parse(resC[0].at) - Date.parse(resC[1].at)) : 0
    if (gapC < 250) problems.push(`C: ตัวที่สองไม่ได้รอ request key เดียวกัน (ห่างกัน ${gapC} ms)`)
    const sc = await state(b.student)
    if (JSON.stringify(sc) !== JSON.stringify({ wallet: [0, 3], owned: 2, distinct: 2 })) {
      problems.push(`C: สถานะ ${JSON.stringify(sc)} (คาด ยอด [0,3] ได้ 2 ชิ้นไม่ซ้ำ)`)
    }

    if (problems.length) failed++
    console.log(`รอบ ${i}: ${problems.length ? 'ล้ม — ' + problems.join('; ') : `ผ่าน (A รอกัน ${gapMs} ms, C รอกัน ${gapC} ms)`}`)
  }
} finally {
  const students = people.map((p) => sqlText(p.student)).join(', ')
  const accounts = people.map((p) => sqlText(p.account)).join(', ')
  await psqlOk(`
begin;
delete from private.operation_receipts where account_id in (${accounts});
delete from public.student_equipment where student_id in (${students});
delete from public.owned_charms where student_id in (${students});
delete from public.wallets where student_id in (${students});
delete from public.students where id in (${students});
delete from public.accounts where id in (${accounts});
commit;`)
}

console.log(`สรุป: ${ROUNDS - failed}/${ROUNDS} รอบผ่าน`)
process.exitCode = failed ? 1 : 0
