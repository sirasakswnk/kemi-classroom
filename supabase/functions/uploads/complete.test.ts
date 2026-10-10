// unit test ของ POST /uploads/:batch_id/complete — PostgREST และ B2 จำลองด้วย fetch ปลอม ไม่เรียกของจริง
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { detectType } from '../_shared/filetype.ts'
import { createHandler } from './handler.ts'

const BATCH = '0b6d3c1e-6c55-4f4e-9d8b-2f1a3c4d5e6f'
const ACCOUNT = '3f000000-0000-4000-8000-000000000001'
const ASSET = 'a5500000-0000-4000-8000-000000000001'
const STAGING = `staging/${BATCH}/7f3e2d1c-0b9a-4876-9543-210fedcba987`
const FINAL = `files/${ASSET}.pdf`
const SERVICE_KEY = 'service-role-key-for-tests'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://dev.example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
  B2_KEY_ID: '003testkeyid0000000000001',
  B2_APP_KEY: 'K003testapplicationkey000000000',
  B2_BUCKET: 'kemi-dev-files',
  B2_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
}
const PDF16 = new TextEncoder().encode('%PDF-1.7\n%ทด')
const TARGET = {
  account_id: ACCOUNT,
  batch_id: BATCH,
  item: 1,
  staging_key: STAGING,
  file_name: 'โจทย์ Kc.pdf',
  content_type: 'application/pdf',
  size_bytes: 1000,
  asset: null,
}
const BEGUN = {
  asset_id: ASSET,
  final_key: FINAL,
  file_name: 'โจทย์ Kc.pdf',
  content_type: 'application/pdf',
  size_bytes: 1000,
  status: 'copying',
}

interface Call {
  kind: 'rpc' | 'b2'
  name: string // ชื่อ RPC หรือเมธอด B2
  url: URL
  headers: Headers
  body: string
}
type Reply = () => Response | Promise<Response>
const jsonReply =
  (data: unknown, status = 200): Reply =>
  () =>
    new Response(data === undefined ? null : JSON.stringify(data), { status })
const pgError = (status: number, code: string, message: string): Reply =>
  jsonReply({ code, message, details: null, hint: null }, status)

function setup(overrides: Partial<Record<string, Reply>> = {}, env: Record<string, string> = ENV) {
  const replies: Record<string, Reply> = {
    upload_complete_target: jsonReply(TARGET),
    upload_complete_begin: jsonReply(BEGUN),
    upload_complete_finish: jsonReply({ ...BEGUN, status: 'ready' }),
    upload_complete_abort: jsonReply(true),
    record_b2_usage: () => new Response(null, { status: 204 }),
    GET: () =>
      new Response(PDF16, {
        status: 206,
        headers: {
          'x-amz-version-id': '4_zstaging_v1',
          'content-range': 'bytes 0-15/1000',
          etag: '"src-etag"',
        },
      }),
    PUT: () =>
      new Response(
        '<?xml version="1.0"?><CopyObjectResult><LastModified>x</LastModified><ETag>&quot;0123456789abcdef0123456789abcdef&quot;</ETag></CopyObjectResult>',
        {
          status: 200,
          headers: { 'x-amz-version-id': '4_zfinal_v1' },
        },
      ),
    DELETE: () => new Response(null, { status: 204 }),
    ...overrides,
  }
  const calls: Call[] = []
  const handler = createHandler({
    env: (n) => env[n],
    fetch: async (input, init) => {
      const req = input instanceof Request ? input : new Request(String(input), init)
      const url = new URL(req.url)
      const body = req.method === 'GET' || req.method === 'DELETE' ? '' : await req.clone().text()
      const isRpc = url.host === 'dev.example.supabase.co'
      const name = isRpc ? url.pathname.split('/').pop()! : req.method
      calls.push({ kind: isRpc ? 'rpc' : 'b2', name, url, headers: req.headers, body })
      const reply = replies[name]
      if (!reply) throw new Error(`unexpected call ${name}`)
      return reply()
    },
  })
  return { handler, calls, names: () => calls.map((c) => c.name) }
}

function complete(body: unknown = { item: 1 }, headers: Record<string, string> = {}) {
  return new Request(`https://dev.example.supabase.co/uploads/${BATCH}/complete`, {
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
const DONE = {
  batch_id: BATCH,
  item: 1,
  asset_id: ASSET,
  file_name: 'โจทย์ Kc.pdf',
  content_type: 'application/pdf',
  size_bytes: 1000,
  status: 'ready',
}

test('สำเร็จ: target → GET Range ครั้งเดียว → begin → CopyObject ระบุเวอร์ชัน → finish → ลบไฟล์พักเวอร์ชันที่ตรวจ', async () => {
  const { handler, calls, names } = setup()
  const res = await handler(complete())
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), DONE)
  assert.deepEqual(names(), [
    'upload_complete_target',
    'GET',
    'upload_complete_begin',
    'PUT',
    'upload_complete_finish',
    'DELETE',
  ])
  const [target, get, begin, copy, finish, del] = calls
  // ยืนยันเจ้าของด้วย JWT ของผู้ใช้; ขั้นที่เขียนข้อมูลที่ระบบเชื่อใช้ service role
  assert.equal(target.headers.get('authorization'), 'Bearer user.jwt.token')
  assert.equal(target.headers.get('apikey'), 'sb_publishable_test')
  assert.deepEqual(JSON.parse(target.body), { p_batch_id: BATCH, p_item: 1 })
  for (const c of [begin, finish]) {
    assert.equal(c.headers.get('authorization'), `Bearer ${SERVICE_KEY}`)
    assert.equal(c.headers.get('apikey'), SERVICE_KEY)
  }
  // GET แบบ Range ของ staging key จากแถว batch (ไม่ใช่จากหน้าเว็บ) ไม่ระบุเวอร์ชัน = เวอร์ชันล่าสุด
  assert.equal(get.url.pathname, `/kemi-dev-files/${STAGING}`)
  assert.equal(get.url.search, '')
  assert.equal(get.headers.get('range'), 'bytes=0-15')
  assert.match(
    get.headers.get('authorization') ?? '',
    /^AWS4-HMAC-SHA256 Credential=003testkeyid0000000000001\//,
  )
  assert.deepEqual(JSON.parse(begin.body), {
    p_account_id: ACCOUNT,
    p_batch_id: BATCH,
    p_item: 1,
    p_staging_version_id: '4_zstaging_v1',
    p_total_bytes: 1000,
    p_detected_type: 'application/pdf',
    p_read_bytes: 16,
  })
  // CopyObject: ปลายทาง files/{asset}.pdf, ต้นทางระบุเวอร์ชันที่ตรวจ, REPLACE + ชนิดที่ตรวจแล้ว, ลงลายเซ็น x-amz-*
  assert.equal(copy.url.pathname, `/kemi-dev-files/${FINAL}`)
  assert.equal(
    copy.headers.get('x-amz-copy-source'),
    `/kemi-dev-files/${STAGING}?versionId=4_zstaging_v1`,
  )
  assert.equal(copy.headers.get('x-amz-metadata-directive'), 'REPLACE')
  assert.equal(copy.headers.get('content-type'), 'application/pdf')
  assert.match(
    copy.headers.get('authorization') ?? '',
    /SignedHeaders=[^,]*x-amz-copy-source;[^,]*x-amz-metadata-directive/,
  )
  // finish ได้ version ปลายทาง + ETag ที่ตัดเครื่องหมายคำพูดแล้ว
  assert.deepEqual(JSON.parse(finish.body), {
    p_asset_id: ASSET,
    p_version_id: '4_zfinal_v1',
    p_checksum: '0123456789abcdef0123456789abcdef',
  })
  assert.equal(del.url.pathname, `/kemi-dev-files/${STAGING}`)
  assert.equal(del.url.searchParams.get('versionId'), '4_zstaging_v1')
})

test('รับแค่ { item } — ส่ง key/ค่าอื่นหรือ item ผิดรูป → invalid_request โดยไม่เรียกอะไร', async () => {
  const { handler, calls } = setup()
  for (const body of [
    { item: 1, staging_key: STAGING },
    { item: 0 },
    { item: 11 },
    { item: '1' },
    { item: 1.5 },
    {},
    'x',
    [],
  ]) {
    const res = await handler(complete(body))
    assert.equal(res.status, 400, JSON.stringify(body))
    assert.deepEqual(await res.json(), { code: 'P0001', message: 'invalid_request' })
  }
  assert.equal(calls.length, 0)
})

test('เรียกซ้ำหลัง complete แล้ว (เน็ตหลุด) → ผลเดิมโดยไม่เรียก B2', async () => {
  const { handler, names } = setup({
    upload_complete_target: jsonReply({ ...TARGET, asset: { id: ASSET, status: 'ready' } }),
  })
  const res = await handler(complete())
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), DONE)
  assert.deepEqual(names(), ['upload_complete_target'])
})

test('ไฟล์กำลังคัดลอกอยู่ (เรียกพร้อมกัน) → 409 upload_in_progress; ถูกตัดสินลบแล้ว → upload_failed', async () => {
  for (const [status, code, http] of [
    ['copying', 'upload_in_progress', 409],
    ['deleting', 'upload_failed', 502],
  ] as const) {
    const { handler, names } = setup({
      upload_complete_target: jsonReply({ ...TARGET, asset: { id: ASSET, status } }),
    })
    const res = await handler(complete())
    assert.equal(res.status, http)
    assert.deepEqual(await res.json(), { code: 'P0001', message: code })
    assert.deepEqual(names(), ['upload_complete_target'])
  }
})

test('ไม่ใช่เจ้าของ batch / batch หมดอายุ → ส่งรหัสจาก RPC ต่อโดยไม่เรียก B2', async () => {
  for (const [code, http] of [
    ['forbidden', 403],
    ['upload_expired', 410],
    ['account_required', 403],
  ] as const) {
    const { handler, names } = setup({ upload_complete_target: pgError(400, 'P0001', code) })
    const res = await handler(complete())
    assert.equal(res.status, http, code)
    assert.deepEqual(await res.json(), { code: 'P0001', message: code })
    assert.deepEqual(names(), ['upload_complete_target'])
  }
})

test('ยังไม่มีไฟล์พัก (GET 404) → upload_not_found และนับคำขอ', async () => {
  const { handler, calls, names } = setup({
    GET: () => new Response('<Error><Code>NoSuchKey</Code></Error>', { status: 404 }),
  })
  const res = await handler(complete())
  assert.equal(res.status, 404)
  assert.deepEqual(await res.json(), { code: 'P0001', message: 'upload_not_found' })
  assert.deepEqual(names(), ['upload_complete_target', 'GET', 'record_b2_usage'])
  assert.deepEqual(JSON.parse(calls[2].body), { p_source: 'complete', p_requests: 1, p_bytes: 0 })
  assert.equal(calls[2].headers.get('apikey'), SERVICE_KEY)
})

test('GET เกินเพดาน B2 (403 cap exceeded) → download_budget_reached ไม่สร้าง asset', async () => {
  const capBody =
    '<Error><Code>AccessDenied</Code><Message>Cannot download file, download bandwidth or transaction (Class B) cap exceeded.</Message></Error>'
  const { handler, names } = setup({ GET: () => new Response(capBody, { status: 403 }) })
  const res = await handler(complete())
  assert.equal(res.status, 503)
  assert.deepEqual(await res.json(), { code: 'P0001', message: 'download_budget_reached' })
  assert.deepEqual(names(), ['upload_complete_target', 'GET'])
})

test('GET ได้ผลใช้ไม่ได้ (403 อื่น, ไม่มี version, ไฟล์ว่าง) → ปฏิเสธโดยไม่สร้าง asset', async () => {
  const cases: [Reply, string][] = [
    [
      () => new Response('<Error><Code>AccessDenied</Code></Error>', { status: 403 }),
      'upload_failed',
    ],
    [
      () => new Response(PDF16, { status: 206, headers: { 'content-range': 'bytes 0-15/1000' } }),
      'upload_failed',
    ],
    [() => new Response(PDF16, { status: 200 }), 'upload_failed'],
    [
      () => new Response(null, { status: 416, headers: { 'content-range': 'bytes */0' } }),
      'upload_size_mismatch',
    ],
  ]
  for (const [reply, code] of cases) {
    const { handler, names } = setup({ GET: reply })
    const res = await handler(complete())
    assert.equal((await res.json()).message, code)
    assert.ok(!names().includes('upload_complete_begin'))
  }
})

test('ขนาด/ชนิดไม่ตรงที่ประกาศ → ส่งรหัสต่อ (422) และลบไฟล์พักเวอร์ชันที่ตรวจทันที ไม่คัดลอก', async () => {
  for (const code of ['upload_size_mismatch', 'upload_type_mismatch']) {
    const { handler, calls, names } = setup({ upload_complete_begin: jsonReply({ code }) })
    const res = await handler(complete())
    assert.equal(res.status, 422)
    assert.deepEqual(await res.json(), { code: 'P0001', message: code })
    assert.deepEqual(names(), ['upload_complete_target', 'GET', 'upload_complete_begin', 'DELETE'])
    assert.equal(calls[3].url.searchParams.get('versionId'), '4_zstaging_v1')
  }
})

test('magic number ไม่ใช่ JPEG/PNG/PDF → ส่ง p_detected_type = null ให้ฐานข้อมูลตัดสิน', async () => {
  const { handler, calls } = setup({
    GET: () =>
      new Response(new TextEncoder().encode('<html>not a pdf'), {
        status: 206,
        headers: { 'x-amz-version-id': '4_zstaging_v1', 'content-range': 'bytes 0-14/1000' },
      }),
    upload_complete_begin: jsonReply({ code: 'upload_type_mismatch' }),
  })
  const res = await handler(complete())
  assert.equal((await res.json()).message, 'upload_type_mismatch')
  const args = JSON.parse(calls[2].body)
  assert.equal(args.p_detected_type, null)
  assert.equal(args.p_read_bytes, 15)
})

test('begin เจอ asset ของไฟล์นี้แล้ว (อีกคำขอแซงระหว่าง GET) → ไม่คัดลอกซ้ำ', async () => {
  const cases: [string, number][] = [
    ['copying', 409],
    ['ready', 200],
  ]
  for (const [status, http] of cases) {
    const { handler, names } = setup({
      upload_complete_begin: jsonReply({ asset_id: ASSET, status, existing: true }),
    })
    const res = await handler(complete())
    assert.equal(res.status, http)
    assert.deepEqual(names(), ['upload_complete_target', 'GET', 'upload_complete_begin'])
  }
})

test('CopyObject ถูกปฏิเสธแน่นอน (4xx) → abort แถว copying; เกินเพดาน → download_budget_reached', async () => {
  const cap =
    '<Error><Code>AccessDenied</Code><Message>Cannot download file, download bandwidth or transaction (Class B) cap exceeded.</Message></Error>'
  const cases: [Reply, string][] = [
    [() => new Response(cap, { status: 403 }), 'download_budget_reached'],
    [
      () => new Response('<Error><Code>NoSuchVersion</Code></Error>', { status: 404 }),
      'upload_failed',
    ],
  ]
  for (const [reply, code] of cases) {
    const { handler, calls, names } = setup({ PUT: reply })
    const res = await handler(complete())
    assert.equal((await res.json()).message, code)
    assert.deepEqual(names(), [
      'upload_complete_target',
      'GET',
      'upload_complete_begin',
      'PUT',
      'upload_complete_abort',
    ])
    assert.deepEqual(JSON.parse(calls[4].body), { p_asset_id: ASSET })
  }
})

test('CopyObject ผลไม่แน่นอน (5xx, 200 ที่มี <Error>, เน็ตหลุด) → ไม่ abort ปล่อยให้ sweeper ตัดสิน', async () => {
  const cases: Reply[] = [
    () => new Response('<Error><Code>InternalError</Code></Error>', { status: 500 }),
    () =>
      new Response('<Error><Code>InternalError</Code></Error>', {
        status: 200,
        headers: { 'x-amz-version-id': 'v' },
      }),
    () => {
      throw new TypeError('network')
    },
    () => new Response('<CopyObjectResult><ETag>"e"</ETag></CopyObjectResult>', { status: 200 }), // ไม่มี version ปลายทาง
  ]
  for (const reply of cases) {
    const { handler, names } = setup({ PUT: reply })
    const res = await handler(complete())
    assert.equal(res.status, 502)
    assert.equal((await res.json()).message, 'upload_failed')
    assert.deepEqual(names(), ['upload_complete_target', 'GET', 'upload_complete_begin', 'PUT'])
  }
})

test('CopyObject ไม่ส่ง ETag → ใช้ ETag ของต้นทางเวอร์ชันเดียวกันจาก GET', async () => {
  const { handler, calls } = setup({
    PUT: () =>
      new Response('<CopyObjectResult></CopyObjectResult>', {
        status: 200,
        headers: { 'x-amz-version-id': '4_zfinal_v1' },
      }),
  })
  assert.equal((await handler(complete())).status, 200)
  assert.equal(JSON.parse(calls[4].body).p_checksum, 'src-etag')
})

test('finish ล้ม (sweeper ตัดสินไปก่อน) → upload_failed และไม่ลบไฟล์พัก', async () => {
  const { handler, names } = setup({
    upload_complete_finish: pgError(400, 'P0001', 'upload_failed'),
  })
  const res = await handler(complete())
  assert.equal(res.status, 502)
  assert.deepEqual(names(), [
    'upload_complete_target',
    'GET',
    'upload_complete_begin',
    'PUT',
    'upload_complete_finish',
  ])
})

test('ไม่มีกุญแจ service role → 500 ก่อนเรียกอะไร; กุญแจถูกปฏิเสธ → internal_error (ไม่ใช่ not_authenticated)', async () => {
  const missing = setup({}, { ...ENV, SUPABASE_SERVICE_ROLE_KEY: '' })
  const res = await missing.handler(complete())
  assert.equal(res.status, 500)
  assert.equal(missing.calls.length, 0)
  const rejected = setup({ upload_complete_begin: pgError(401, 'PGRST301', 'JWT invalid') })
  const res2 = await rejected.handler(complete())
  assert.equal(res2.status, 500)
  assert.deepEqual(await res2.json(), { code: 'P0001', message: 'internal_error' })
})

test('ไฟล์ที่ลบไฟล์พักไม่สำเร็จยังตอบสำเร็จ (lifecycle ของ staging/ ล้างให้)', async () => {
  const { handler } = setup({ DELETE: () => new Response('<Error/>', { status: 500 }) })
  assert.equal((await handler(complete())).status, 200)
})

test('detectType: JPEG/PNG/PDF จาก magic number; อย่างอื่นและไฟล์สั้นได้ null', () => {
  const b = (...xs: number[]) => new Uint8Array(xs)
  assert.equal(detectType(b(0xff, 0xd8, 0xff, 0xe0, 0, 0x10)), 'image/jpeg')
  assert.equal(detectType(b(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0)), 'image/png')
  assert.equal(detectType(new TextEncoder().encode('%PDF-1.4\n')), 'application/pdf')
  assert.equal(detectType(new TextEncoder().encode('%PDF')), null)
  assert.equal(detectType(b(0xff, 0xd8)), null)
  assert.equal(detectType(new TextEncoder().encode('GIF89a')), null)
  assert.equal(
    detectType(b(0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63)),
    null,
  ) // HEIC
  assert.equal(detectType(b()), null)
})
