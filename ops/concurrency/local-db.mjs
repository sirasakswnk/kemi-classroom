// ตัวช่วยทดสอบคำขอพร้อมกันกับ Postgres ในเครื่องเท่านั้น (ผู้ใช้กำหนด 19 ต.ค. 2026 — ห้ามใช้กับ kemi-dev/prod)
// ต่อผ่าน psql ในคอนเทนเนอร์ของ `supabase start` (docker exec) จึงไปถึงฐานข้อมูลนอกเครื่องไม่ได้ และไม่ต้องเพิ่ม dependency
// หนึ่งการเรียก psql() = หนึ่งการเชื่อมต่อ; race() เปิดหลายการเชื่อมต่อพร้อมกันแล้วให้ทุกตัวเริ่มคำสั่งที่เวลาเดียวกันของเซิร์ฟเวอร์
import { execFileSync, spawn } from 'node:child_process'

export const LOCAL_DB_CONTAINER = 'supabase_db_kemi-classroom'

/** ตรวจว่าคอนเทนเนอร์ฐานข้อมูลในเครื่องเปิดอยู่ ไม่งั้นโยน error พร้อมวิธีแก้ */
export function requireLocalDb() {
  let names = ''
  try {
    names = execFileSync('docker', ['ps', '--format', '{{.Names}}'], { encoding: 'utf8' })
  } catch {
    throw new Error('เรียก docker ไม่ได้ — เปิด Docker Desktop ก่อน')
  }
  if (!names.split(/\r?\n/).includes(LOCAL_DB_CONTAINER)) {
    throw new Error(`ไม่พบคอนเทนเนอร์ ${LOCAL_DB_CONTAINER} — รัน npm run db:start ก่อน`)
  }
}

/** รัน SQL หนึ่งชุดในการเชื่อมต่อใหม่ (role postgres) คืน { code, out, err } — ไม่โยน error เมื่อ SQL ล้ม */
export function psql(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', [
      'exec', '-i', LOCAL_DB_CONTAINER,
      'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1',
    ])
    let out = ''
    let err = ''
    child.stdout.setEncoding('utf8').on('data', (d) => (out += d))
    child.stderr.setEncoding('utf8').on('data', (d) => (err += d))
    child.on('error', reject)
    child.on('close', (code) => resolve({ code, out, err }))
    child.stdin.end(`set client_encoding to 'UTF8';
${sql}`)
  })
}

/** เหมือน psql() แต่โยน error เมื่อ SQL ล้ม และคืนบรรทัดผลที่ไม่ว่าง */
export async function psqlOk(sql) {
  const r = await psql(sql)
  if (r.code !== 0) throw new Error(`SQL ล้ม: ${r.err.trim()}`)
  return r.out.split(/\r?\n/).filter((l) => l !== '')
}

export const sqlText = (s) => `'${String(s).replaceAll("'", "''")}'`

/**
 * รัน body ของแต่ละตัวพร้อมกัน ตัวละหนึ่งการเชื่อมต่อ ในนาม authenticated ของ authUserId
 * ทุกตัวรอถึงเวลาเดียวกันของเซิร์ฟเวอร์ (pg_sleep_until) ก่อนเริ่ม body แล้วถือ transaction ไว้ holdSeconds
 * ก่อน commit (ให้อีกตัวต้องรอล็อกจริง) — คืน [{ ok, json, err, at }] (at = เวลาเซิร์ฟเวอร์หลัง body จบ
 * ทั้งกรณีสำเร็จและล้ม: ตัวที่ล้มหลังรอล็อกจึงวัดได้ว่ารอจริง)
 */
export async function race(authUserId, bodies, holdSeconds = 0.3) {
  const [startAt] = await psqlOk(`select (clock_timestamp() + interval '1.5 seconds')::text;`)
  const claims = JSON.stringify({ sub: authUserId, role: 'authenticated' })
  const runs = bodies.map((body) =>
    psql(`begin;
select set_config('request.jwt.claims', ${sqlText(claims)}, true) is null;
set local role authenticated;
select pg_sleep_until(${sqlText(startAt)}::timestamptz) is null;
\\set ON_ERROR_STOP 0
select 'JSON ' || (${body})::text;
\\set ON_ERROR_STOP 1
\\if :ERROR
rollback;
select 'AT ' || clock_timestamp()::text;
\\else
select 'AT ' || clock_timestamp()::text;
select pg_sleep(${holdSeconds}) is null;
commit;
\\endif
`),
  )
  return (await Promise.all(runs)).map((r) => {
    const line = (p) => r.out.split(/\r?\n/).find((l) => l.startsWith(p))?.slice(p.length)
    const json = r.code === 0 ? line('JSON ') : undefined
    return {
      ok: json !== undefined,
      json: json !== undefined ? JSON.parse(json) : null,
      at: line('AT ') ?? null,
      err: json !== undefined ? null : r.err.trim(),
    }
  })
}
