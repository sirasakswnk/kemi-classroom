// P7-04: ตรวจความปลอดภัยแบบอ่านอย่างเดียว (TECHNICAL_BUILD_PLAN ส่วน 11) — รันซ้ำกับ prod ได้หลัง P7-06
//   node ops/security-check.mjs [--publishable-key <sb_publishable_…>] [--origin https://kemi-classroom.pages.dev] [--dist web/dist]
// ทำอะไร (ไม่เขียนข้อมูลใด ๆ):
//   1. ฐานข้อมูลของโปรเจกต์ที่ `supabase link` ผูกอยู่: ops/security/checks.sql (SELECT คำสั่งเดียว) ผ่าน
//      `supabase db query --linked` — รายการฟังก์ชันที่ตั้งใจไว้ดึงจาก supabase/tests/function_privileges.test.sql
//   2. ค่า Auth สาธารณะ: GET /auth/v1/settings (ต้องมี publishable key — ไม่ใช่ความลับ) → Email/Phone/Anonymous ปิด, Google เปิด
//   3. Edge Functions: เรียกโดยไม่มี JWT/รหัสลับต้องถูกปฏิเสธ; CORS ตอบเฉพาะ origin ของเรา (preflight เท่านั้น ไม่ส่งข้อมูล)
//   4. --dist: ค้นไฟล์ build หาสิ่งที่ห้ามมี (service role, sb_secret_, JWT, กุญแจ B2)
// ผล: ตาราง ผ่าน/ไม่ผ่าน/ข้อมูล — มีข้อไม่ผ่าน = exit 1 · โปรเจกต์ที่ไม่ใช่ kemi-dev ถือเป็น prod (allow_test_logins ต้องไม่เปิด)
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DEV_PROJECT } from './check-dev-db.mjs'

const root = fileURLToPath(new URL('..', import.meta.url))

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`)
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback
}

/** รายการ signature ใน `insert into <table> values …;` ของไฟล์ pgTAP */
export function signaturesOf(sql, table) {
  const start = sql.indexOf(`insert into ${table} values`)
  if (start < 0) throw new Error(`ไม่พบรายการ ${table} ใน function_privileges.test.sql`)
  // จบที่บรรทัดแรกที่ลงท้าย `');` — คอมเมนต์ในรายการมี `;` ได้
  const tail = /'\);[ \t]*$/m.exec(sql.slice(start))
  if (!tail) throw new Error(`หาจุดจบรายการ ${table} ไม่เจอ`)
  const list = [
    ...sql
      .slice(start, start + tail.index + 3)
      .matchAll(/\('((?:public|private)\.[a-z0-9_]+\([^)]*\))'\)/g),
  ].map((m) => m[1])
  if (list.length === 0) throw new Error(`รายการ ${table} ว่าง`)
  return list
}

/** แทนรายการลง checks.sql เป็น values ('a'), ('b') */
export function buildSql(template, lists) {
  const values = (xs) => xs.map((x) => `('${x.replaceAll("'", "''")}')`).join(', ')
  return template
    .replace('/*AUTH*/', values(lists.auth))
    .replace('/*SERVICE*/', values(lists.service))
    .replace('/*PGONLY*/', values(lists.pgOnly))
}

/** สิ่งที่ห้ามอยู่ในไฟล์ build ของหน้าเว็บ (publishable key `sb_publishable_` อยู่ได้ตามแบบ) */
export const DIST_PATTERNS = [
  ['service_role', /service_role/],
  ['sb_secret_', /sb_secret_[A-Za-z0-9_-]{8,}/],
  ['JWT (legacy anon/service key)', /eyJhbGciOi[A-Za-z0-9_-]{10,}/],
  // กุญแจ B2 ยาว 31 ตัวขึ้นต้น K00 (เช่น K003…)
  ['B2 application key', /\bK00[0-9A-Za-z+/]{28}\b/],
  ['B2_APP_KEY / B2_KEY_ID', /B2_(APP_KEY|KEY_ID)/],
  ['JOBS_SECRET', /JOBS_SECRET|x-jobs-secret/],
]

export function scanText(text) {
  return DIST_PATTERNS.filter(([, re]) => re.test(text)).map(([label]) => label)
}

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })
}

const results = []
const add = (status, check, detail = '') => results.push({ status, check, detail })

function linkedProject() {
  const temp = join(root, 'supabase', '.temp')
  const ref = readFileSync(join(temp, 'project-ref'), 'utf8').trim()
  let name = ''
  try {
    name = JSON.parse(readFileSync(join(temp, 'linked-project.json'), 'utf8')).name ?? ''
  } catch {
    name = ''
  }
  return { ref, name }
}

function runDbChecks(isDev) {
  const tests = readFileSync(
    join(root, 'supabase', 'tests', 'function_privileges.test.sql'),
    'utf8',
  )
  const sql = buildSql(readFileSync(join(root, 'ops', 'security', 'checks.sql'), 'utf8'), {
    auth: signaturesOf(tests, 'expected_authenticated'),
    service: signaturesOf(tests, 'expected_service_only'),
    pgOnly: signaturesOf(tests, 'postgres_only'),
  })
  const dir = mkdtempSync(join(tmpdir(), 'kemi-sec-'))
  const file = join(dir, 'checks.sql')
  writeFileSync(file, sql)
  try {
    // ใช้ shell บน Windows (npx เป็น .cmd) — ส่งเป็นคำสั่งเดียว เส้นทางไฟล์มาจาก mkdtemp ไม่มีข้อมูลจากผู้ใช้
    const run = spawnSync(`npx supabase db query --linked -f "${file}" --output-format json`, {
      cwd: root,
      encoding: 'utf8',
      shell: true,
    })
    const out = run.stdout ?? ''
    const json = JSON.parse(out.slice(out.indexOf('{')))
    for (const row of json.rows) {
      if (row.check === 'allow_test_logins_on') {
        if (isDev)
          add('ข้อมูล', 'db: allow_test_logins (dev เปิดได้ตามแบบ)', row.ok ? 'ปิด' : row.detail)
        else add(row.ok ? 'ผ่าน' : 'ไม่ผ่าน', 'db: allow_test_logins ไม่เปิด (prod)', row.detail)
        continue
      }
      add(
        row.ok ? 'ผ่าน' : 'ไม่ผ่าน',
        `db: ${row.check}`,
        row.ok ? '' : `${row.n} รายการ: ${row.detail}`,
      )
    }
  } catch (e) {
    add('ไม่ผ่าน', 'db: รัน checks.sql', `อ่านผลไม่ได้ (${e.message})`)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

async function runAuthSettings(url, key) {
  if (!key) return add('ข้อมูล', 'auth: /auth/v1/settings', 'ข้าม — ไม่ได้ใส่ --publishable-key')
  try {
    const s = await (await fetch(`${url}/auth/v1/settings`, { headers: { apikey: key } })).json()
    const ext = s.external ?? {}
    add(ext.email === false ? 'ผ่าน' : 'ไม่ผ่าน', 'auth: Email provider ปิด', `email=${ext.email}`)
    add(ext.phone === false ? 'ผ่าน' : 'ไม่ผ่าน', 'auth: Phone ปิด', `phone=${ext.phone}`)
    add(
      ext.anonymous_users === false ? 'ผ่าน' : 'ไม่ผ่าน',
      'auth: Anonymous ปิด',
      `anonymous_users=${ext.anonymous_users}`,
    )
    add(ext.google === true ? 'ผ่าน' : 'ไม่ผ่าน', 'auth: Google เปิด', `google=${ext.google}`)
    const others = Object.entries(ext)
      .filter(([k, v]) => v === true && k !== 'google')
      .map(([k]) => k)
    add(
      others.length === 0 ? 'ผ่าน' : 'ไม่ผ่าน',
      'auth: ไม่มี provider อื่นเปิด',
      others.join(', '),
    )
  } catch (e) {
    add('ไม่ผ่าน', 'auth: /auth/v1/settings', e.message)
  }
}

async function codeOf(res) {
  try {
    return (await res.json()).message ?? (await res.text())
  } catch {
    return ''
  }
}

async function runEdgeChecks(url, origin) {
  const fn = (p) => `${url}/functions/v1/${p}`
  const noAuth = [
    ['files/sign', { asset_ids: ['00000000-0000-4000-8000-000000000000'], mode: 'view' }],
    ['files/exports', { term_id: '00000000-0000-4000-8000-000000000000' }],
    ['uploads', { files: [] }],
  ]
  for (const [path, body] of noAuth) {
    const res = await fetch(fn(path), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    const code = await codeOf(res)
    add(
      res.status === 401 ? 'ผ่าน' : 'ไม่ผ่าน',
      `edge: ${path} ไม่มี JWT → 401`,
      `${res.status} ${code}`,
    )
  }
  const jobs = await fetch(fn('process-jobs'), {
    method: 'POST',
    headers: { 'x-jobs-secret': 'wrong' },
  })
  add(
    jobs.status === 401 ? 'ผ่าน' : 'ไม่ผ่าน',
    'edge: process-jobs รหัสลับผิด → 401',
    `${jobs.status}`,
  )
  const jobsNone = await fetch(fn('process-jobs'), { method: 'POST' })
  add(
    jobsNone.status === 401 ? 'ผ่าน' : 'ไม่ผ่าน',
    'edge: process-jobs ไม่มีรหัสลับ → 401',
    `${jobsNone.status}`,
  )

  for (const path of ['files/sign', 'uploads']) {
    const pre = (o) =>
      fetch(fn(path), {
        method: 'OPTIONS',
        headers: { Origin: o, 'Access-Control-Request-Method': 'POST' },
      })
    const evil = (await pre('https://evil.example')).headers.get('access-control-allow-origin')
    add(evil === null ? 'ผ่าน' : 'ไม่ผ่าน', `edge: CORS ${path} ไม่ตอบ origin อื่น`, `ACAO=${evil}`)
    const ours = (await pre(origin)).headers.get('access-control-allow-origin')
    add(ours === origin ? 'ผ่าน' : 'ไม่ผ่าน', `edge: CORS ${path} ตอบ ${origin}`, `ACAO=${ours}`)
  }
}

function runDistScan(dir) {
  const files = walk(dir)
  const hits = files.flatMap((f) => {
    const found = scanText(readFileSync(f, 'latin1'))
    return found.map((label) => `${f.slice(dir.length + 1)}: ${label}`)
  })
  add(
    hits.length === 0 ? 'ผ่าน' : 'ไม่ผ่าน',
    `dist: ไม่มีความลับใน build (${files.length} ไฟล์)`,
    hits.join(' · '),
  )
}

async function main() {
  const { ref, name } = linkedProject()
  const isDev = ref === DEV_PROJECT.ref
  const url = `https://${ref}.supabase.co`
  console.log(
    `โปรเจกต์ที่ผูกอยู่: ${name || '-'} (${ref}) → ตรวจแบบ ${isDev ? 'dev' : 'prod'} · อ่านอย่างเดียว`,
  )
  runDbChecks(isDev)
  await runAuthSettings(url, arg('publishable-key'))
  await runEdgeChecks(url, arg('origin', 'https://kemi-classroom.pages.dev'))
  const dist = arg('dist')
  if (dist) runDistScan(join(root, dist))

  for (const r of results)
    console.log(`[${r.status}] ${r.check}${r.detail ? ` — ${r.detail}` : ''}`)
  const failed = results.filter((r) => r.status === 'ไม่ผ่าน').length
  console.log(
    `สรุป: ผ่าน ${results.filter((r) => r.status === 'ผ่าน').length} · ไม่ผ่าน ${failed} · ข้อมูล ${results.filter((r) => r.status === 'ข้อมูล').length}`,
  )
  process.exit(failed > 0 ? 1 : 0)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main()
