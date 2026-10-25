// unit test ของ POST /files/exports (exports.ts) — fetch ปลอมแทน PostgREST ไม่เรียก B2/Supabase จริง
// งบดาวน์โหลดจำลองด้วยคำตอบของ files_sign_begin (ไม่ใช้งบ B2 จริง — TECHNICAL_DESIGN 9.3 ข้อ 6)
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHandler } from './handler.ts'
import { parseExportRequest } from './exports.ts'

const TERM = '7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f'
const A1 = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
const A2 = '1b2c3d4e-5f6a-4b7c-9d8e-0f1a2b3c4d5e'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://dev.example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-from-env',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-test',
  B2_KEY_ID: '003testkeyid0000000000001',
  B2_APP_KEY: 'K003testapplicationkey000000000',
  B2_BUCKET: 'kemi-dev-files',
  B2_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
}
const NOW = new Date('2026-10-25T03:04:05.678Z')
const STUDENT_NAME = 'อนุชา ทดสอบ'
const STUDENT = {
  student_id: '2c3d4e5f-6a7b-4c8d-8e9f-0a1b2c3d4e5f',
  student_code: '01234',
  display_name: STUDENT_NAME,
  group_name: '5/4',
  roll_number: 3,
}
const FILE_1 = {
  asset_id: A1,
  file_name: 'ใบงาน เคมี.pdf',
  content_type: 'application/pdf',
  size_bytes: 40000,
  purpose: 'post',
  position: 1,
  classroom_id: '3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a',
  classroom_name: 'เคมี 5/4',
  post_id: '4e5f6a7b-8c9d-4e0f-9a1b-2c3d4e5f6a7b',
  post_kind: 'assignment',
  post_title: 'สมดุลเคมี',
  student: null as typeof STUDENT | null,
}
const FILE_2 = {
  ...FILE_1,
  asset_id: A2,
  file_name: 'งานส่ง.jpg',
  content_type: 'image/jpeg',
  size_bytes: 900000,
  purpose: 'submission',
  student: STUDENT,
}
const PAGE = {
  term_id: TERM,
  fingerprint: 'f'.repeat(32),
  total_count: 23,
  total_bytes: 13504143,
  next_after: A2,
  files: [FILE_1, FILE_2],
}
const target = (f: typeof FILE_1, v: string) => ({
  id: f.asset_id,
  final_key: `files/${f.asset_id}.${f.content_type === 'image/jpeg' ? 'jpg' : 'pdf'}`,
  version_id: v,
  content_type: f.content_type,
  size_bytes: f.size_bytes,
  file_name: f.file_name,
})
const TARGETS = {
  files: [target(FILE_1, '4_z_f1_v1'), target(FILE_2, '4_z_f2_v2')],
}

type Call = { url: string; init: RequestInit }
type Rpc = (fn: string, body: Record<string, unknown>) => Response

const ok = (data: unknown) => new Response(JSON.stringify(data), { status: 200 })
const fail = (code: string, status = 400) =>
  new Response(JSON.stringify({ code: 'P0001', message: code }), { status })

const allow: Rpc = (fn) => (fn === 'export_files_page' ? ok(PAGE) : ok(TARGETS))

function setup(rpc: Rpc = allow) {
  const calls: Call[] = []
  const handler = createHandler({
    env: (n) => ENV[n],
    fetch: async (input, init) => {
      const url = String(input)
      calls.push({ url, init: init ?? {} })
      const fn = /\/rest\/v1\/rpc\/([a-z_]+)$/.exec(url)?.[1]
      if (!fn) throw new Error(`unexpected fetch ${url}`)
      return rpc(fn, JSON.parse(String(init?.body ?? '{}')))
    },
    now: () => NOW,
  })
  return { handler, calls }
}

function post(body: unknown, path = '/functions/v1/files/exports', method = 'POST') {
  return new Request(`https://dev.example.supabase.co${path}`, {
    method,
    headers: {
      Authorization: 'Bearer user-jwt',
      apikey: 'publishable-from-web',
      'Content-Type': 'application/json',
      Origin: 'http://localhost:5173',
    },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  })
}

const errorOf = async (res: Response) => ((await res.json()) as { message: string }).message
const headerOf = (c: Call, name: string) => new Headers(c.init.headers).get(name)
const bodyOf = (c: Call) => JSON.parse(String(c.init.body)) as Record<string, unknown>

/** เก็บ console.error ระหว่างรัน fn — ตรวจว่าไม่มี key ของ B2 หรือชื่อนักเรียนหลุดลง log */
async function captureErrors(fn: () => Promise<void>): Promise<string[]> {
  const logged: string[] = []
  const original = console.error
  console.error = (...args: unknown[]) => logged.push(args.map(String).join(' '))
  try {
    await fn()
  } finally {
    console.error = original
  }
  return logged
}

type ExportBody = Omit<typeof PAGE, 'files'> & {
  expires_at: string
  files: (typeof FILE_2 & {
    url: string
    final_key?: string
    version_id?: string
  })[]
}

test('หน้าไฟล์ภาคเรียนเก่า: รายการในนามผู้ใช้ → นับงบด้วย service role → ลิงก์ attachment ระบุเวอร์ชัน', async () => {
  const { handler, calls } = setup()
  const res = await handler(post({ term_id: TERM, after: null, limit: 20 }))
  assert.equal(res.status, 200)
  assert.equal(res.headers.get('access-control-allow-origin'), 'http://localhost:5173')
  assert.equal(res.headers.get('cache-control'), 'no-store')

  assert.equal(calls.length, 2)
  assert.match(calls[0].url, /\/rest\/v1\/rpc\/export_files_page$/)
  assert.equal(headerOf(calls[0], 'authorization'), 'Bearer user-jwt')
  assert.equal(headerOf(calls[0], 'apikey'), 'publishable-from-web')
  assert.deepEqual(bodyOf(calls[0]), {
    p_term_id: TERM,
    p_after: null,
    p_limit: 20,
    p_admin_mode: false,
  })
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/files_sign_begin$/)
  assert.equal(headerOf(calls[1], 'authorization'), 'Bearer service-role-test')
  assert.deepEqual(bodyOf(calls[1]), { p_asset_ids: [A1, A2] })

  const body = (await res.json()) as ExportBody
  assert.equal(body.term_id, TERM)
  assert.equal(body.fingerprint, PAGE.fingerprint)
  assert.equal(body.total_count, 23)
  assert.equal(body.total_bytes, 13504143)
  assert.equal(body.next_after, A2)
  assert.equal(body.expires_at, '2026-10-25T03:14:05.678Z')
  // ข้อมูลประกอบ manifest ส่งต่อครบ (ห้อง งาน นักเรียน) — ไม่มี key/เวอร์ชันแยก
  assert.deepEqual(
    body.files.map(({ url: _url, ...meta }) => meta),
    [FILE_1, FILE_2],
  )
  assert.ok(body.files.every((f) => !('final_key' in f) && !('version_id' in f)))

  const url = new URL(body.files[1].url)
  assert.equal(
    url.origin + url.pathname,
    `https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/files/${A2}.jpg`,
  )
  assert.equal(url.searchParams.get('versionId'), '4_z_f2_v2')
  assert.equal(url.searchParams.get('response-content-type'), 'image/jpeg')
  assert.match(url.searchParams.get('response-content-disposition') ?? '', /^attachment; /)
  assert.equal(url.searchParams.get('X-Amz-Expires'), '600')
  assert.equal(url.searchParams.get('X-Amz-Date'), '20261025T030405Z')
})

test('ค่าตั้งต้น: after null, หน้าละ 20, ไม่ใช่โหมดผู้ดูแล · ส่งต่อ after/limit/admin_mode ตามที่ขอ', async () => {
  const first = setup()
  await first.handler(post({ term_id: TERM.toUpperCase() }))
  assert.deepEqual(bodyOf(first.calls[0]), {
    p_term_id: TERM,
    p_after: null,
    p_limit: 20,
    p_admin_mode: false,
  })
  const next = setup((fn) =>
    fn === 'export_files_page'
      ? ok({ ...PAGE, files: [FILE_2] })
      : ok({ files: [TARGETS.files[1]] }),
  )
  const res = await next.handler(post({ term_id: TERM, after: A1, limit: 1, admin_mode: true }))
  assert.equal(res.status, 200)
  assert.deepEqual(bodyOf(next.calls[0]), {
    p_term_id: TERM,
    p_after: A1,
    p_limit: 1,
    p_admin_mode: true,
  })
})

test('คำขอผิดรูปแบบ → invalid_request ไม่เรียก RPC', async () => {
  const bad: unknown[] = [
    null,
    [],
    {},
    { term_id: 'x' },
    { term_id: TERM, after: 'x' },
    { term_id: TERM, limit: 0 },
    { term_id: TERM, limit: 21 },
    { term_id: TERM, limit: 1.5 },
    { term_id: TERM, limit: '5' },
    { term_id: TERM, admin_mode: 'true' },
    { term_id: TERM, scope: 'files' },
  ]
  for (const body of bad) {
    assert.equal(parseExportRequest(body), null, JSON.stringify(body))
    const { handler, calls } = setup()
    const res = await handler(post(body))
    assert.equal(res.status, 400)
    assert.equal(await errorOf(res), 'invalid_request')
    assert.equal(calls.length, 0)
  }
})

test('รหัสจาก export_files_page ส่งต่อตรง ๆ และไม่ขอลิงก์/ไม่นับงบ', async () => {
  const cases: [string, number][] = [
    ['teacher_required', 403],
    ['admin_mode_required', 403],
    ['invalid_request', 400], // ภาคเรียนที่ยังเปิด/ไม่มีอยู่
    ['rate_limited', 429],
    ['account_required', 403],
  ]
  for (const [code, status] of cases) {
    const { handler, calls } = setup((fn) =>
      fn === 'export_files_page' ? fail(code) : ok(TARGETS),
    )
    const res = await handler(post({ term_id: TERM }))
    assert.equal(res.status, status, code)
    assert.equal(await errorOf(res), code)
    assert.equal(calls.length, 1)
  }
  // JWT ไม่ถูกต้อง (PostgREST 401) → not_authenticated
  const { handler } = setup((fn) =>
    fn === 'export_files_page' ? new Response('{"code":"PGRST301"}', { status: 401 }) : ok(TARGETS),
  )
  assert.equal(await errorOf(await handler(post({ term_id: TERM }))), 'not_authenticated')
})

test('หน้าว่าง (ไม่มีไฟล์/เลยไฟล์สุดท้าย) → ไม่เรียก files_sign_begin ไม่นับงบ', async () => {
  const { handler, calls } = setup((fn) =>
    fn === 'export_files_page'
      ? ok({
          ...PAGE,
          total_count: 0,
          total_bytes: 0,
          next_after: null,
          files: [],
        })
      : ok(TARGETS),
  )
  const res = await handler(post({ term_id: TERM }))
  assert.equal(res.status, 200)
  assert.equal(calls.length, 1)
  const body = (await res.json()) as ExportBody
  assert.deepEqual(body.files, [])
  assert.equal(body.next_after, null)
  assert.equal(body.total_count, 0)
})

test('งบวันนี้ไม่พอ → export_budget_reached (503) ทั้งหน้า ไม่มีลิงก์ — ขอหน้าเดิมอีกครั้งวันถัดไปได้', async () => {
  let budgetLeft = false
  const { handler, calls } = setup((fn) =>
    fn === 'export_files_page'
      ? ok(PAGE)
      : budgetLeft
        ? ok(TARGETS)
        : fail('download_budget_reached'),
  )
  const res = await handler(post({ term_id: TERM, after: A1 }))
  assert.equal(res.status, 503)
  assert.equal(await errorOf(res), 'export_budget_reached')
  const raw = JSON.stringify(await (await handler(post({ term_id: TERM, after: A1 }))).json())
  assert.ok(!raw.includes('backblazeb2'))

  // รอบวันใหม่: คำขอเดิม (after เดิม) ได้หน้าเดิมพร้อมลิงก์ — ไม่ต้องเริ่มใหม่จากหน้าแรก
  budgetLeft = true
  const again = await handler(post({ term_id: TERM, after: A1 }))
  assert.equal(again.status, 200)
  assert.equal(((await again.json()) as ExportBody).files.length, 2)
  assert.deepEqual(
    calls.filter((c) => c.url.endsWith('/export_files_page')).map((c) => bodyOf(c).p_after),
    [A1, A1, A1],
  )
})

test('ไฟล์ในหน้าถูกลบระหว่างทาง (files_sign_begin forbidden) → export_mismatch (409)', async () => {
  const { handler } = setup((fn) => (fn === 'export_files_page' ? ok(PAGE) : fail('forbidden')))
  const res = await handler(post({ term_id: TERM }))
  assert.equal(res.status, 409)
  assert.equal(await errorOf(res), 'export_mismatch')
})

test('ผลจากฐานข้อมูลผิดรูปแบบ → internal_error ไม่ออกลิงก์ และ log ไม่มี key/ชื่อไฟล์/ชื่อนักเรียน', async () => {
  const pages: unknown[] = [
    { ...PAGE, files: [FILE_1, FILE_1] }, // id ซ้ำ
    { ...PAGE, files: [{ ...FILE_1, size_bytes: '40000' }] },
    { ...PAGE, next_after: 'x' },
    { ...PAGE, files: undefined },
  ]
  const logs = await captureErrors(async () => {
    for (const page of pages) {
      const { handler, calls } = setup((fn) =>
        fn === 'export_files_page' ? ok(page) : ok(TARGETS),
      )
      const res = await handler(post({ term_id: TERM }))
      assert.equal(await errorOf(res), 'internal_error')
      assert.equal(calls.length, 1)
    }
    // หน้าเกิน limit ที่ขอ
    const { handler } = setup((fn) => (fn === 'export_files_page' ? ok(PAGE) : ok(TARGETS)))
    assert.equal(await errorOf(await handler(post({ term_id: TERM, limit: 1 }))), 'internal_error')

    // files_sign_begin คืนขนาด/ลำดับไม่ตรงหน้า หรือ key ผิดรูปแบบ (ลงลายเซ็นไม่ได้)
    const targets: unknown[] = [
      { files: [{ ...TARGETS.files[0], size_bytes: 1 }, TARGETS.files[1]] },
      { files: [TARGETS.files[1], TARGETS.files[0]] },
      { files: [TARGETS.files[0]] },
      {
        files: [
          { ...TARGETS.files[0], final_key: `uploads/${STUDENT_NAME}.pdf` },
          TARGETS.files[1],
        ],
      },
    ]
    for (const t of targets) {
      const { handler: h } = setup((fn) => (fn === 'export_files_page' ? ok(PAGE) : ok(t)))
      assert.equal(await errorOf(await h(post({ term_id: TERM }))), 'internal_error')
    }
  })
  assert.ok(logs.length >= 8)
  for (const line of logs) {
    for (const secret of [A1, A2, 'files/', STUDENT_NAME, '01234', 'ใบงาน', 'งานส่ง', '4_z_f']) {
      assert.ok(!line.includes(secret), `log มี ${secret}: ${line}`)
    }
  }
})

test('เส้นทาง: GET/ชื่อเส้นทางอื่น → not_found · ไม่มี JWT → not_authenticated', async () => {
  const { handler, calls } = setup()
  assert.equal(
    await errorOf(await handler(post(null, '/functions/v1/files/exports', 'GET'))),
    'not_found',
  )
  assert.equal(
    await errorOf(await handler(post({ term_id: TERM }, '/functions/v1/files/exportsx'))),
    'not_found',
  )
  const noAuth = new Request('https://dev.example.supabase.co/functions/v1/files/exports', {
    method: 'POST',
    body: JSON.stringify({ term_id: TERM }),
  })
  assert.equal(await errorOf(await handler(noAuth)), 'not_authenticated')
  assert.equal(calls.length, 0)
  // ทับ / ท้ายได้เหมือน /files/sign
  assert.equal((await handler(post({ term_id: TERM }, '/functions/v1/files/exports/'))).status, 200)
})
