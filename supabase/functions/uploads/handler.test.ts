// unit test ของ uploads/handler.ts — fetch ปลอมแทน PostgREST ไม่เรียก B2/Supabase จริง
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHandler } from './handler.ts'

const BATCH = '0b6d3c1e-6c55-4f4e-9d8b-2f1a3c4d5e6f'
const CLASSROOM = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d'
const REQUEST_KEY = '1d2c3b4a-5f6e-4d7c-9b8a-0f1e2d3c4b5a'
const APP_KEY = 'K003testapplicationkey000000000'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://dev.example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-from-env',
  B2_KEY_ID: '003testkeyid0000000000001',
  B2_APP_KEY: APP_KEY,
  B2_BUCKET: 'kemi-dev-files',
  B2_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
}
const BATCH_RESULT = {
  batch_id: BATCH,
  purpose: 'post',
  expires_at: '2026-10-05T05:04:05.678+00:00',
  reserved_bytes: 940000,
  files: [
    {
      staging_key: `staging/${BATCH}/7f3e2d1c-0b9a-4876-9543-210fedcba987`,
      file_name: 'โจทย์.jpg',
      content_type: 'image/jpeg',
      size_bytes: 900000,
    },
    {
      staging_key: `staging/${BATCH}/8e4f3a2b-1c0d-4e9f-8a7b-6c5d4e3f2a1b`,
      file_name: 'ตาราง.pdf',
      content_type: 'application/pdf',
      size_bytes: 40000,
    },
  ],
}
const BODY = {
  purpose: 'post',
  classroom_id: CLASSROOM,
  files: [
    { file_name: 'โจทย์.jpg', content_type: 'image/jpeg', size_bytes: 900000 },
    { file_name: 'ตาราง.pdf', content_type: 'application/pdf', size_bytes: 40000 },
  ],
  request_key: REQUEST_KEY,
}

type Call = { url: string; init: RequestInit }

function setup(rpc: () => Response, env: Record<string, string> = ENV) {
  const calls: Call[] = []
  const handler = createHandler({
    env: (n) => env[n],
    fetch: async (input, init) => {
      calls.push({ url: String(input), init: init ?? {} })
      return rpc()
    },
    now: () => new Date('2026-10-05T03:04:05.678Z'),
  })
  return { handler, calls }
}

const ok = (data: unknown) => () => new Response(JSON.stringify(data), { status: 200 })
const pgError = (status: number, code: string, message: string) => () =>
  new Response(JSON.stringify({ code, message, details: null, hint: null }), { status })

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request('https://dev.example.supabase.co/uploads', {
    method: 'POST',
    headers: {
      authorization: 'Bearer user.jwt.token',
      apikey: 'sb_publishable_test',
      origin: 'https://kemi-classroom.pages.dev',
      ...headers,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

test('preflight: เว็บ production/preview/localhost ได้ CORS — origin อื่นไม่ได้', async () => {
  const { handler, calls } = setup(ok(BATCH_RESULT))
  const preflight = (origin: string) =>
    handler(
      new Request('https://dev.example.supabase.co/uploads', {
        method: 'OPTIONS',
        headers: { origin },
      }),
    )
  for (const origin of [
    'https://kemi-classroom.pages.dev',
    'https://phase-3.kemi-classroom.pages.dev',
    'http://localhost:5173',
  ]) {
    const res = await preflight(origin)
    assert.equal(res.status, 204)
    assert.equal(res.headers.get('access-control-allow-origin'), origin)
    assert.match(
      res.headers.get('access-control-allow-headers') ?? '',
      /authorization, apikey, content-type/,
    )
  }
  for (const origin of [
    'https://evil.example.com',
    'https://a.b.kemi-classroom.pages.dev',
    'https://kemi-classroom.pages.dev.evil.com',
    'https://.kemi-classroom.pages.dev',
    'http://localhost:4173',
  ]) {
    const res = await preflight(origin)
    assert.equal(res.headers.get('access-control-allow-origin'), null, origin)
  }
  assert.equal(calls.length, 0)
})

test('WEB_ORIGINS แทนรายการเริ่มต้นได้ (prod ใช้ production อย่างเดียว)', async () => {
  const { handler } = setup(ok(BATCH_RESULT), {
    ...ENV,
    WEB_ORIGINS: 'https://kemi-classroom.pages.dev',
  })
  const res = await handler(post(BODY, { origin: 'https://phase-3.kemi-classroom.pages.dev' }))
  assert.equal(res.headers.get('access-control-allow-origin'), null)
})

test('สำเร็จ: เรียก RPC ในนามผู้ใช้ แล้วคืนลิงก์ PUT ต่อไฟล์ (ไม่มีกุญแจลับในคำตอบ)', async () => {
  const { handler, calls } = setup(ok(BATCH_RESULT))
  const res = await handler(post(BODY))
  assert.equal(res.status, 200)
  assert.equal(res.headers.get('access-control-allow-origin'), 'https://kemi-classroom.pages.dev')
  assert.equal(res.headers.get('cache-control'), 'no-store')
  assert.equal(calls.length, 1)
  assert.equal(calls[0].url, 'https://dev.example.supabase.co/rest/v1/rpc/create_upload_batch')
  const headers = calls[0].init.headers as Record<string, string>
  assert.equal(headers.Authorization, 'Bearer user.jwt.token')
  assert.equal(headers.apikey, 'sb_publishable_test')
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), {
    p_purpose: 'post',
    p_classroom_id: CLASSROOM,
    p_post_id: null,
    p_files: BODY.files,
    p_request_key: REQUEST_KEY,
    p_admin_mode: false,
  })
  const text = await res.text()
  assert.ok(!text.includes(APP_KEY))
  const body = JSON.parse(text)
  assert.equal(body.batch_id, BATCH)
  assert.equal(body.url_expires_in, 300)
  assert.equal(body.files.length, 2)
  body.files.forEach(
    (f: { staging_key: string; upload_url: string; size_bytes: number }, i: number) => {
      assert.equal(f.staging_key, BATCH_RESULT.files[i].staging_key)
      const url = new URL(f.upload_url)
      assert.equal(
        `${url.origin}${url.pathname}`,
        `https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/${f.staging_key}`,
      )
      assert.equal(url.searchParams.get('X-Amz-SignedHeaders'), 'content-length;content-type;host')
      assert.equal(url.searchParams.get('X-Amz-Expires'), '300')
    },
  )
})

test('ไม่มี apikey จากหน้าเว็บ → ใช้ SUPABASE_ANON_KEY; admin_mode และ post_id ส่งต่อ', async () => {
  const { handler, calls } = setup(ok({ ...BATCH_RESULT, purpose: 'solution' }))
  const req = post({ ...BODY, purpose: 'solution', post_id: BATCH, admin_mode: true })
  req.headers.delete('apikey')
  assert.equal((await handler(req)).status, 200)
  assert.equal((calls[0].init.headers as Record<string, string>).apikey, 'anon-from-env')
  const args = JSON.parse(String(calls[0].init.body))
  assert.equal(args.p_post_id, BATCH)
  assert.equal(args.p_admin_mode, true)
})

test('รูปเครื่องราง: classroom_id = null ส่งต่อให้ RPC ตรวจ (P5-07)', async () => {
  const { handler, calls } = setup(ok({ ...BATCH_RESULT, purpose: 'charm' }))
  const res = await handler(post({ ...BODY, purpose: 'charm', classroom_id: null }))
  assert.equal(res.status, 200)
  const args = JSON.parse(String(calls[0].init.body))
  assert.equal(args.p_purpose, 'charm')
  assert.equal(args.p_classroom_id, null)
})

test('ไม่มี JWT → 401 not_authenticated โดยไม่เรียก RPC', async () => {
  const { handler, calls } = setup(ok(BATCH_RESULT))
  for (const authorization of ['', 'Basic abc', 'Bearer ']) {
    const res = await handler(post(BODY, { authorization }))
    assert.equal(res.status, 401)
    assert.deepEqual(await res.json(), { code: 'P0001', message: 'not_authenticated' })
  }
  assert.equal(calls.length, 0)
})

test('ค่าตั้ง B2 ไม่ครบ → 500 และไม่เรียก RPC (ไม่จองพื้นที่) และไม่บอกค่าใน log', async () => {
  for (const missing of ['B2_APP_KEY', 'B2_ENDPOINT', 'SUPABASE_URL']) {
    const { handler, calls } = setup(ok(BATCH_RESULT), { ...ENV, [missing]: '' })
    const res = await handler(post(BODY))
    assert.equal(res.status, 500)
    assert.deepEqual(await res.json(), { code: 'P0001', message: 'internal_error' })
    assert.equal(calls.length, 0)
  }
})

test('คำขอผิดรูป → 400 invalid_request โดยไม่เรียก RPC', async () => {
  const { handler, calls } = setup(ok(BATCH_RESULT))
  const bad = [
    'not json',
    [],
    { ...BODY, classroom_id: 'abc' },
    { ...BODY, classroom_id: undefined },
    { ...BODY, request_key: undefined },
    { ...BODY, post_id: 'x' },
    { ...BODY, files: {} },
    { ...BODY, admin_mode: 'yes' },
    { ...BODY, staging_key: 'files/x' },
    {
      ...BODY,
      files: [{ file_name: 'a'.repeat(20000), content_type: 'image/png', size_bytes: 1 }],
    },
  ]
  for (const body of bad) {
    const res = await handler(post(body))
    assert.equal(res.status, 400, JSON.stringify(body).slice(0, 60))
    assert.deepEqual(await res.json(), { code: 'P0001', message: 'invalid_request' })
  }
  assert.equal(calls.length, 0)
})

test('รหัสจาก RPC ส่งต่อพร้อมสถานะ HTTP (พื้นที่เต็ม 507, เพดานครั้ง 429, สิทธิ์ 403)', async () => {
  const cases: [number, string, string, number][] = [
    [400, 'P0001', 'storage_full', 507],
    [400, 'P0001', 'rate_limited', 429],
    [400, 'P0001', 'forbidden', 403],
    [400, 'P0001', 'term_ended', 409],
    [400, 'P0001', 'file_too_large', 400],
    [401, 'PGRST301', 'JWT expired', 401],
    [401, '42501', 'permission denied for function create_upload_batch', 401],
  ]
  for (const [status, code, message, expected] of cases) {
    const { handler } = setup(pgError(status, code, message))
    const res = await handler(post(BODY))
    assert.equal(res.status, expected, message)
    const body = await res.json()
    assert.equal(body.code, 'P0001')
    assert.equal(body.message, status === 401 ? 'not_authenticated' : message)
  }
  const { handler } = setup(pgError(500, 'XX000', 'boom'))
  assert.deepEqual(await (await handler(post(BODY))).json(), {
    code: 'P0001',
    message: 'internal_error',
  })
})

test('กันพลาด: ไม่ลงลายเซ็น key นอก staging/ ของ batch นี้', async () => {
  const other = '11111111-2222-4333-8444-555555555555'
  for (const key of ['files/abc', `staging/${other}/7f3e2d1c-0b9a-4876-9543-210fedcba987`]) {
    const { handler } = setup(
      ok({ ...BATCH_RESULT, files: [{ ...BATCH_RESULT.files[0], staging_key: key }] }),
    )
    const res = await handler(post(BODY))
    assert.equal(res.status, 500)
    assert.ok(!(await res.text()).includes('X-Amz-Signature'))
  }
})

test('เส้นทาง/เมธอดอื่น → 404', async () => {
  const { handler } = setup(ok(BATCH_RESULT))
  assert.equal((await handler(new Request('https://x/uploads', { method: 'GET' }))).status, 404)
  assert.equal(
    (await handler(new Request('https://x/uploads/abc/complete', { method: 'POST' }))).status,
    404,
  )
})
