// unit test ของ files/handler.ts (POST /files/sign) — fetch ปลอมแทน PostgREST ไม่เรียก B2/Supabase จริง
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHandler } from './handler.ts'

const A1 = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
const A2 = '1b2c3d4e-5f6a-4b7c-9d8e-0f1a2b3c4d5e'
const KEY_ID = '003testkeyid0000000000001'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://dev.example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-from-env',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-test',
  B2_KEY_ID: KEY_ID,
  B2_APP_KEY: 'K003testapplicationkey000000000',
  B2_BUCKET: 'kemi-dev-files',
  B2_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
}
// ชื่อไทย: filename= สำรองเป็น ASCII, filename*= เป็น UTF-8 (RFC 6266 + 8187) — วงเล็บเข้ารหัสด้วย
const THAI_NAME = 'ใบงาน เคมี (1).pdf'
const THAI_ENCODED =
  '%E0%B9%83%E0%B8%9A%E0%B8%87%E0%B8%B2%E0%B8%99%20%E0%B9%80%E0%B8%84%E0%B8%A1%E0%B8%B5%20%281%29.pdf'
const NOW = new Date('2026-10-05T03:04:05.678Z')
const TARGETS = {
  files: [
    {
      id: A1,
      final_key: `files/${A1}.pdf`,
      version_id: '4_z0a1b2c3d_f1_v1',
      content_type: 'application/pdf',
      size_bytes: 40000,
      file_name: THAI_NAME,
    },
    {
      id: A2,
      final_key: `files/${A2}.jpg`,
      version_id: '4_z0a1b2c3d_f2_v2',
      content_type: 'image/jpeg',
      size_bytes: 900000,
      file_name: 'photo.jpg',
    },
  ],
}

type Call = { url: string; init: RequestInit }
type Rpc = (fn: string, body: Record<string, unknown>) => Response

const ok = (data: unknown) => new Response(JSON.stringify(data), { status: 200 })
const fail = (code: string, status = 400) =>
  new Response(JSON.stringify({ code: 'P0001', message: code }), { status })

const allow: Rpc = (fn, body) => (fn === 'authorize_files' ? ok(body.p_asset_ids) : ok(TARGETS))

const oneFile: Rpc = (fn, body) =>
  fn === 'authorize_files' ? ok(body.p_asset_ids) : ok({ files: [TARGETS.files[0]] })

function setup(rpc: Rpc = allow, env: Record<string, string> = ENV) {
  const calls: Call[] = []
  const handler = createHandler({
    env: (n) => env[n],
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

function post(
  body: unknown,
  headers: Record<string, string> = {},
  path = '/functions/v1/files/sign',
) {
  return new Request(`https://dev.example.supabase.co${path}`, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer user-jwt',
      apikey: 'publishable-from-web',
      'Content-Type': 'application/json',
      Origin: 'http://localhost:5173',
      ...headers,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

async function errorOf(res: Response) {
  return ((await res.json()) as { message: string }).message
}

const headerOf = (c: Call, name: string) => new Headers(c.init.headers).get(name)

test('ออกลิงก์เปิดดู: ตรวจสิทธิ์ด้วย JWT ผู้ใช้ → งบด้วย service role → ลิงก์ GET ระบุเวอร์ชัน/ชนิด/inline/แคช', async () => {
  const { handler, calls } = setup()
  const res = await handler(post({ asset_ids: [A1, A2], mode: 'view' }))
  assert.equal(res.status, 200)
  assert.equal(res.headers.get('access-control-allow-origin'), 'http://localhost:5173')
  assert.equal(res.headers.get('cache-control'), 'no-store')

  // เรียก Supabase 2 ครั้งเท่านั้น (ไม่เรียก B2): authorize ในนามผู้ใช้ แล้ว begin ด้วย service role
  assert.equal(calls.length, 2)
  assert.match(calls[0].url, /\/rest\/v1\/rpc\/authorize_files$/)
  assert.equal(headerOf(calls[0], 'authorization'), 'Bearer user-jwt')
  assert.equal(headerOf(calls[0], 'apikey'), 'publishable-from-web')
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), {
    p_asset_ids: [A1, A2],
  })
  assert.match(calls[1].url, /\/rest\/v1\/rpc\/files_sign_begin$/)
  assert.equal(headerOf(calls[1], 'authorization'), 'Bearer service-role-test')
  assert.equal(headerOf(calls[1], 'apikey'), 'service-role-test')
  assert.deepEqual(JSON.parse(String(calls[1].init.body)), {
    p_asset_ids: [A1, A2],
  })

  const body = (await res.json()) as {
    mode: string
    expires_at: string
    files: {
      asset_id: string
      url: string
      file_name: string
      content_type: string
      size_bytes: number
    }[]
  }
  assert.equal(body.mode, 'view')
  assert.equal(body.expires_at, '2026-10-05T03:14:05.678Z')
  assert.deepEqual(
    body.files.map((f) => [f.asset_id, f.file_name, f.content_type, f.size_bytes]),
    [
      [A1, THAI_NAME, 'application/pdf', 40000],
      [A2, 'photo.jpg', 'image/jpeg', 900000],
    ],
  )
  // ไม่ส่ง key/เวอร์ชันแยกให้หน้าเว็บ (อยู่ในลิงก์เท่านั้น)
  assert.ok(body.files.every((f) => !('final_key' in f) && !('version_id' in f)))

  const url = new URL(body.files[0].url)
  assert.equal(
    url.origin + url.pathname,
    `https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/files/${A1}.pdf`,
  )
  const q = url.searchParams
  assert.equal(q.get('versionId'), '4_z0a1b2c3d_f1_v1')
  assert.equal(q.get('response-content-type'), 'application/pdf')
  assert.equal(
    q.get('response-content-disposition'),
    `inline; filename="_____ ____ (1).pdf"; filename*=UTF-8''${THAI_ENCODED}`,
  )
  assert.equal(q.get('response-cache-control'), 'private,max-age=600')
  assert.equal(q.get('X-Amz-Expires'), '600')
  assert.equal(q.get('X-Amz-Algorithm'), 'AWS4-HMAC-SHA256')
  assert.equal(q.get('X-Amz-Date'), '20261005T030405Z')
  assert.equal(q.get('X-Amz-Credential'), `${KEY_ID}/20261005/eu-central-003/s3/aws4_request`)
  assert.equal(q.get('X-Amz-SignedHeaders'), 'host')
  assert.match(q.get('X-Amz-Signature') ?? '', /^[0-9a-f]{64}$/)
  // query เข้ารหัสช่องว่างเป็น %20 (ไม่ใช่ +) ให้ตรงกับที่ B2 คำนวณลายเซ็น
  assert.ok(!body.files[0].url.includes('+'))
  assert.equal(new URL(body.files[1].url).searchParams.get('versionId'), '4_z0a1b2c3d_f2_v2')
})

test('โหมดดาวน์โหลด: attachment พร้อมชื่อไทยแบบ filename*=UTF-8', async () => {
  const { handler } = setup(oneFile)
  const res = await handler(post({ asset_ids: [A1], mode: 'download' }))
  assert.equal(res.status, 200)
  const body = (await res.json()) as { files: { url: string }[] }
  const disposition = new URL(body.files[0].url).searchParams.get('response-content-disposition')
  assert.equal(
    disposition,
    `attachment; filename="_____ ____ (1).pdf"; filename*=UTF-8''${THAI_ENCODED}`,
  )
})

test('ลิงก์เดียวกันลงลายเซ็นใหม่ได้ผลเดิมที่เวลาเดียวกัน (ไม่มีค่าสุ่ม) และต่างกันเมื่อโหมดต่าง', async () => {
  const sign = async (mode: string) => {
    const res = await setup(oneFile).handler(post({ asset_ids: [A1], mode }))
    return ((await res.json()) as { files: { url: string }[] }).files[0].url
  }
  assert.equal(await sign('view'), await sign('view'))
  assert.notEqual(await sign('view'), await sign('download'))
})

test('id ซ้ำ/ตัวพิมพ์ใหญ่ตัดเหลือชุดเดียวก่อนเรียก RPC', async () => {
  const { handler, calls } = setup(oneFile)
  const res = await handler(post({ asset_ids: [A1, A1.toUpperCase(), A1], mode: 'view' }))
  assert.equal(res.status, 200)
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), {
    p_asset_ids: [A1],
  })
})

test('ได้สิทธิ์ไม่ครบทุก id → forbidden ทั้งชุด ไม่นับงบ ไม่ออกลิงก์', async () => {
  const { handler, calls } = setup((fn) => (fn === 'authorize_files' ? ok([A1]) : ok(TARGETS)))
  const res = await handler(post({ asset_ids: [A1, A2], mode: 'view' }))
  assert.equal(res.status, 403)
  assert.equal(await errorOf(res), 'forbidden')
  assert.equal(calls.length, 1)
})

test('ไม่มีสิทธิ์เลย (คืนรายการว่าง) → forbidden', async () => {
  const { handler, calls } = setup((fn) => (fn === 'authorize_files' ? ok([]) : ok(TARGETS)))
  const res = await handler(post({ asset_ids: [A1], mode: 'download' }))
  assert.equal(res.status, 403)
  assert.equal(await errorOf(res), 'forbidden')
  assert.equal(calls.length, 1)
})

test('ครบงบเปิดดูของวัน → 503 download_budget_reached ไม่มีลิงก์', async () => {
  const { handler } = setup((fn, body) =>
    fn === 'authorize_files' ? ok(body.p_asset_ids) : fail('download_budget_reached'),
  )
  const res = await handler(post({ asset_ids: [A1, A2], mode: 'view' }))
  assert.equal(res.status, 503)
  const body = (await res.json()) as Record<string, unknown>
  assert.deepEqual(body, { code: 'P0001', message: 'download_budget_reached' })
})

test('ข้อผิดพลาดจาก authorize_files ส่งต่อตามรหัส (rate_limited 429, not_authenticated 401)', async () => {
  let res = await setup(() => fail('rate_limited')).handler(post({ asset_ids: [A1], mode: 'view' }))
  assert.equal(res.status, 429)
  assert.equal(await errorOf(res), 'rate_limited')
  res = await setup(
    () =>
      new Response(JSON.stringify({ code: 'PGRST301', message: 'JWT expired' }), { status: 401 }),
  ).handler(post({ asset_ids: [A1], mode: 'view' }))
  assert.equal(res.status, 401)
  assert.equal(await errorOf(res), 'not_authenticated')
})

test('ผล files_sign_begin ไม่ตรง id ที่ขอ → internal_error ไม่ออกลิงก์', async () => {
  const { handler } = setup((fn, body) =>
    fn === 'authorize_files'
      ? ok(body.p_asset_ids)
      : ok({ files: [TARGETS.files[1], TARGETS.files[0]] }),
  )
  const res = await handler(post({ asset_ids: [A1, A2], mode: 'view' }))
  assert.equal(res.status, 500)
  assert.equal(await errorOf(res), 'internal_error')
})

test('key ในฐานข้อมูลผิดรูปแบบ → internal_error (ไม่ลงลายเซ็น key นอก files/)', async () => {
  const bad = {
    files: [{ ...TARGETS.files[0], final_key: `staging/../files/${A1}.pdf` }],
  }
  const { handler } = setup((fn, body) =>
    fn === 'authorize_files' ? ok(body.p_asset_ids) : ok(bad),
  )
  const res = await handler(post({ asset_ids: [A1], mode: 'view' }))
  assert.equal(res.status, 500)
})

test('service key ใช้ไม่ได้ → internal_error (ไม่ใช่ not_authenticated)', async () => {
  const { handler } = setup((fn, body) =>
    fn === 'authorize_files'
      ? ok(body.p_asset_ids)
      : new Response(JSON.stringify({ code: '42501', message: 'permission denied' }), {
          status: 401,
        }),
  )
  const res = await handler(post({ asset_ids: [A1], mode: 'view' }))
  assert.equal(res.status, 500)
  assert.equal(await errorOf(res), 'internal_error')
})

test('คำขอผิดรูป → invalid_request โดยไม่เรียก RPC', async () => {
  const many = Array.from(
    { length: 21 },
    (_, i) => `0a1b2c3d-4e5f-4a6b-8c7d-${String(i).padStart(12, '0')}`,
  )
  const bodies: unknown[] = [
    { asset_ids: [A1], mode: 'preview' },
    { asset_ids: [A1] },
    { asset_ids: [], mode: 'view' },
    { asset_ids: ['not-a-uuid'], mode: 'view' },
    { asset_ids: A1, mode: 'view' },
    { asset_ids: many, mode: 'view' },
    { asset_ids: [A1], mode: 'view', key: `files/${A1}.pdf` },
    [A1],
    'not json',
  ]
  for (const body of bodies) {
    const { handler, calls } = setup()
    const res = await handler(post(body))
    assert.equal(res.status, 400, JSON.stringify(body))
    assert.equal(await errorOf(res), 'invalid_request')
    assert.equal(calls.length, 0)
  }
  const twenty = many.slice(0, 20)
  const { handler } = setup((fn, body) =>
    fn === 'authorize_files'
      ? ok(body.p_asset_ids)
      : ok({
          files: twenty.map((id) => ({
            ...TARGETS.files[0],
            id,
            final_key: `files/${id}.pdf`,
          })),
        }),
  )
  assert.equal((await handler(post({ asset_ids: twenty, mode: 'view' }))).status, 200)
})

test('ไม่ล็อกอิน → 401 / เส้นทางหรือเมธอดอื่น → 404 / OPTIONS ตอบ CORS', async () => {
  const { handler, calls } = setup()
  let res = await handler(post({ asset_ids: [A1], mode: 'view' }, { Authorization: '' }))
  assert.equal(res.status, 401)
  res = await handler(post({ asset_ids: [A1], mode: 'view' }, {}, '/functions/v1/files/other'))
  assert.equal(res.status, 404)
  res = await handler(new Request('https://dev.example.supabase.co/functions/v1/files/sign'))
  assert.equal(res.status, 404)
  res = await handler(
    new Request('https://dev.example.supabase.co/functions/v1/files/sign', {
      method: 'OPTIONS',
      headers: { Origin: 'https://phase-3.kemi-classroom.pages.dev' },
    }),
  )
  assert.equal(res.status, 204)
  assert.equal(
    res.headers.get('access-control-allow-origin'),
    'https://phase-3.kemi-classroom.pages.dev',
  )
  res = await handler(post({ asset_ids: [A1], mode: 'view' }, { Origin: 'https://evil.example' }))
  assert.equal(res.headers.get('access-control-allow-origin'), null)
  assert.equal(calls.length, 2) // เฉพาะคำขอสุดท้าย (origin อื่น) ที่ผ่านไปถึง RPC (authorize + begin) — เบราว์เซอร์จะไม่ให้อ่านผล
})

test('ค่าตั้งไม่ครบ (service role / B2) → internal_error ก่อนเรียก RPC', async () => {
  for (const missing of ['SUPABASE_SERVICE_ROLE_KEY', 'B2_APP_KEY', 'SUPABASE_URL']) {
    const env = { ...ENV }
    delete env[missing]
    const { handler, calls } = setup(allow, env)
    const res = await handler(post({ asset_ids: [A1], mode: 'view' }))
    assert.equal(res.status, 500, missing)
    assert.equal(calls.length, 0)
  }
})
