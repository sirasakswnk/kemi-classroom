// unit test ของ process-jobs/handler.ts — fetch ปลอมแทน PostgREST และ B2 (ไม่เรียกของจริง)
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHandler, secretMatches } from './handler.ts'

const A1 = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
const A2 = '1b2c3d4e-5f6a-4b7c-9d8e-0f1a2b3c4d5e'
const SECRET = 'test-jobs-secret-0123456789abcdef'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://dev.example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-test',
  JOBS_SECRET: SECRET,
  B2_KEY_ID: '003testkeyid0000000000001',
  B2_APP_KEY: 'K003testapplicationkey000000000',
  B2_BUCKET: 'kemi-dev-files',
  B2_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
}

type Call = { method: string; url: string; body: Record<string, unknown>; headers: Headers }
type Rpc = (fn: string, body: Record<string, unknown>, n: number) => unknown
type B2 = (method: string, url: URL) => Response

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status })

function setup(opts: { rpc: Rpc; b2?: B2; env?: Record<string, string> }) {
  const calls: Call[] = []
  const counts = new Map<string, number>()
  const handler = createHandler({
    env: (n) => (opts.env ?? ENV)[n],
    fetch: async (input, init) => {
      const req = input instanceof Request ? input : new Request(String(input), init)
      const url = new URL(req.url)
      const fn = /\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(url.pathname)?.[1]
      if (fn) {
        const body = JSON.parse((await req.text()) || '{}') as Record<string, unknown>
        calls.push({ method: req.method, url: req.url, body, headers: req.headers })
        const n = (counts.get(fn) ?? 0) + 1
        counts.set(fn, n)
        const out = opts.rpc(fn, body, n)
        return out instanceof Response ? out : json(out)
      }
      calls.push({ method: req.method, url: req.url, body: {}, headers: req.headers })
      if (!opts.b2) throw new Error(`unexpected fetch ${req.url}`)
      return opts.b2(req.method, url)
    },
  })
  return { handler, calls }
}

const call = (headers: Record<string, string> = { 'x-jobs-secret': SECRET }, method = 'POST') =>
  new Request('https://dev.example.supabase.co/functions/v1/process-jobs', {
    method,
    headers,
    body: method === 'POST' ? '{}' : undefined,
  })

const rpcNames = (calls: Call[]) =>
  calls.filter((c) => c.url.includes('/rest/v1/rpc/')).map((c) => c.url.split('/').at(-1))
const b2Calls = (calls: Call[]) => calls.filter((c) => c.url.startsWith(ENV.B2_ENDPOINT))

// claim: รอบแรกได้งาน รอบถัดไปว่าง
const claimOnce = (jobs: unknown[]) => (n: number) => (n === 1 ? jobs : [])
const deleteJob = (id: number) => ({
  id,
  kind: 'delete_asset',
  payload: { asset_id: A1 },
  attempts: 1,
})

test('รหัสลับ: เทียบเวลาคงที่ ถูก/ผิด/ว่าง', async () => {
  assert.equal(await secretMatches(SECRET, SECRET), true)
  assert.equal(await secretMatches('wrong', SECRET), false)
  assert.equal(await secretMatches('', SECRET), false)
  assert.equal(await secretMatches('', ''), false)
})

test('ไม่มี/ผิดรหัสลับ → 401 ไม่เรียก RPC หรือ B2', async () => {
  const { handler, calls } = setup({ rpc: () => [] })
  assert.equal((await handler(call({}))).status, 401)
  assert.equal((await handler(call({ 'x-jobs-secret': 'nope' }))).status, 401)
  assert.equal(calls.length, 0)
})

test('ไม่ใช่ POST → 404; ไม่ได้ตั้ง JOBS_SECRET → 500', async () => {
  const { handler } = setup({ rpc: () => [] })
  assert.equal((await handler(call({ 'x-jobs-secret': SECRET }, 'GET'))).status, 404)
  const env = { ...ENV, JOBS_SECRET: '' }
  const s2 = setup({ rpc: () => [], env })
  assert.equal((await s2.handler(call())).status, 500)
  assert.equal(s2.calls.length, 0)
})

test('delete_asset: begin → DELETE ระบุ versionId ด้วยลายเซ็น → finish; RPC ทั้งหมดใช้ service role', async () => {
  const claim = claimOnce([deleteJob(7)])
  const { handler, calls } = setup({
    rpc: (fn, _b, n) =>
      fn === 'copying_stale'
        ? []
        : fn === 'jobs_claim'
          ? claim(n)
          : fn === 'delete_asset_begin'
            ? {
                action: 'delete',
                asset_id: A1,
                final_key: `files/${A1}.pdf`,
                version_id: '4_zver_1',
              }
            : true,
    b2: () => new Response(null, { status: 204 }),
  })
  const res = await handler(call())
  assert.equal(res.status, 200)
  const summary = (await res.json()) as { jobs: { deleted: number; claimed: number } }
  assert.equal(summary.jobs.claimed, 1)
  assert.equal(summary.jobs.deleted, 1)
  assert.deepEqual(rpcNames(calls), [
    'copying_stale',
    'jobs_claim',
    'delete_asset_begin',
    'delete_asset_finish',
    'jobs_claim',
  ])
  for (const c of calls.filter((x) => x.url.includes('/rest/v1/rpc/'))) {
    assert.equal(c.headers.get('authorization'), 'Bearer service-role-test')
  }
  const [del] = b2Calls(calls)
  assert.equal(del.method, 'DELETE')
  const u = new URL(del.url)
  assert.equal(u.pathname, `/kemi-dev-files/files/${A1}.pdf`)
  assert.equal(u.searchParams.get('versionId'), '4_zver_1')
  assert.match(del.headers.get('authorization') ?? '', /^AWS4-HMAC-SHA256 /)
})

test('delete_asset: B2 404 (ไม่มีเวอร์ชันแล้ว) = สำเร็จ · 500 = jobs_fail พร้อมรหัส', async () => {
  for (const [status, expectFinish] of [
    [404, true],
    [500, false],
  ] as const) {
    const claim = claimOnce([deleteJob(8)])
    const { handler, calls } = setup({
      rpc: (fn, _b, n) =>
        fn === 'copying_stale'
          ? []
          : fn === 'jobs_claim'
            ? claim(n)
            : fn === 'delete_asset_begin'
              ? { action: 'delete', final_key: `files/${A1}.pdf`, version_id: 'v' }
              : fn === 'jobs_fail'
                ? 'pending'
                : true,
      b2: () => new Response('<Error/>', { status }),
    })
    await handler(call())
    assert.equal(rpcNames(calls).includes('delete_asset_finish'), expectFinish, `status ${status}`)
    const fail = calls.find((c) => c.url.endsWith('/jobs_fail'))
    if (!expectFinish) assert.deepEqual(fail?.body, { p_job_id: 8, p_error: 'b2_500' })
  }
})

test('delete_asset: เน็ตหลุดตอนเรียก B2 → jobs_fail b2_network', async () => {
  const claim = claimOnce([deleteJob(9)])
  const { handler, calls } = setup({
    rpc: (fn, _b, n) =>
      fn === 'copying_stale'
        ? []
        : fn === 'jobs_claim'
          ? claim(n)
          : fn === 'delete_asset_begin'
            ? { action: 'delete', final_key: `files/${A1}.pdf`, version_id: 'v' }
            : 'pending',
    b2: () => {
      throw new TypeError('network')
    },
  })
  await handler(call())
  assert.deepEqual(calls.find((c) => c.url.endsWith('/jobs_fail'))?.body, {
    p_job_id: 9,
    p_error: 'b2_network',
  })
})

test('delete_asset: defer (ธงสำรอง) / done (ยังผูก/ไม่มีแล้ว) → ไม่เรียก B2', async () => {
  for (const plan of [
    { action: 'defer' },
    { action: 'done', note: 'asset_kept' },
    { action: 'skip' },
  ]) {
    const claim = claimOnce([deleteJob(10)])
    const { handler, calls } = setup({
      rpc: (fn, _b, n) => (fn === 'copying_stale' ? [] : fn === 'jobs_claim' ? claim(n) : plan),
    })
    await handler(call())
    assert.equal(b2Calls(calls).length, 0, plan.action)
    assert.equal(rpcNames(calls).includes('delete_asset_finish'), false)
  }
})

test('งานชนิดที่ไม่รู้จัก → jobs_fail unknown_kind', async () => {
  const claim = claimOnce([{ id: 11, kind: 'mystery', payload: {}, attempts: 1 }])
  const { handler, calls } = setup({
    rpc: (fn, _b, n) => (fn === 'copying_stale' ? [] : fn === 'jobs_claim' ? claim(n) : 'pending'),
  })
  await handler(call())
  assert.deepEqual(calls.find((c) => c.url.endsWith('/jobs_fail'))?.body, {
    p_job_id: 11,
    p_error: 'unknown_kind',
  })
})

test('due_reminder: due_reminder_run ปิดงานเอง · skip ไม่นับ · RPC ล้ม → jobs_fail', async () => {
  const claim = claimOnce([
    { id: 21, kind: 'due_reminder', payload: { assignment_id: A1 }, attempts: 1 },
    { id: 22, kind: 'due_reminder', payload: { assignment_id: A2 }, attempts: 1 },
    { id: 23, kind: 'due_reminder', payload: { assignment_id: A2 }, attempts: 1 },
  ])
  const { handler, calls } = setup({
    rpc: (fn, body, n) =>
      fn === 'copying_stale'
        ? []
        : fn === 'jobs_claim'
          ? claim(n)
          : fn === 'due_reminder_run'
            ? body.p_job_id === 21
              ? { action: 'done', sent: 3 }
              : body.p_job_id === 22
                ? { action: 'skip' }
                : json({ code: 'XX000', message: 'boom' }, 500)
            : 'pending',
  })
  const res = await handler(call())
  const summary = (await res.json()) as { jobs: Record<string, number> }
  assert.deepEqual(
    calls.filter((c) => c.url.endsWith('/due_reminder_run')).map((c) => c.body),
    [{ p_job_id: 21 }, { p_job_id: 22 }, { p_job_id: 23 }],
  )
  assert.equal(rpcNames(calls).includes('jobs_complete'), false, 'ฐานข้อมูลปิดงานเอง')
  const fails = calls.filter((c) => c.url.endsWith('/jobs_fail'))
  assert.equal(fails.length, 1)
  assert.equal(fails[0].body.p_job_id, 23)
  assert.match(String(fails[0].body.p_error), /^due_reminder_/)
  assert.deepEqual(
    { done: summary.jobs.done, reminded: summary.jobs.reminded, failed: summary.jobs.failed },
    { done: 1, reminded: 3, failed: 1 },
  )
  assert.equal(b2Calls(calls).length, 0, 'งานเตือนไม่เรียก B2')
})

test('sweeper copying: HEAD มีไฟล์ → finish พร้อมเวอร์ชัน · 404 → finish null · นับ Class B ทุก HEAD', async () => {
  const { handler, calls } = setup({
    rpc: (fn, body) =>
      fn === 'copying_stale'
        ? [
            { asset_id: A1, final_key: `files/${A1}.jpg` },
            { asset_id: A2, final_key: `files/${A2}.pdf` },
          ]
        : fn === 'jobs_claim'
          ? []
          : fn === 'sweep_copying_finish'
            ? body.p_version_id
              ? 'queued'
              : 'removed'
            : null,
    b2: (_method, url) =>
      url.pathname.endsWith('.jpg')
        ? new Response(null, { status: 200, headers: { 'x-amz-version-id': '4_zdest' } })
        : new Response(null, { status: 404 }),
  })
  const res = await handler(call())
  const summary = (await res.json()) as { copying: Record<string, number> }
  assert.deepEqual(summary.copying, { checked: 2, queued: 1, removed: 1, errors: 0 })
  assert.deepEqual(
    b2Calls(calls).map((c) => c.method),
    ['HEAD', 'HEAD'],
  )
  const finishes = calls.filter((c) => c.url.endsWith('/sweep_copying_finish')).map((c) => c.body)
  assert.deepEqual(finishes, [
    { p_asset_id: A1, p_version_id: '4_zdest' },
    { p_asset_id: A2, p_version_id: null },
  ])
  const usage = calls.filter((c) => c.url.endsWith('/record_b2_usage')).map((c) => c.body)
  assert.deepEqual(usage, [
    { p_source: 'complete', p_requests: 1, p_bytes: 0 },
    { p_source: 'complete', p_requests: 1, p_bytes: 0 },
  ])
})

test('sweeper copying: HEAD เกินเพดานรายวัน → หยุด HEAD ที่เหลือ ไม่แตะแถว', async () => {
  const { handler, calls } = setup({
    rpc: (fn) =>
      fn === 'copying_stale'
        ? [
            { asset_id: A1, final_key: `files/${A1}.jpg` },
            { asset_id: A2, final_key: `files/${A2}.jpg` },
          ]
        : fn === 'jobs_claim'
          ? []
          : null,
    b2: () => new Response('<Error><Code>transaction_cap_exceeded</Code></Error>', { status: 403 }),
  })
  await handler(call())
  assert.equal(b2Calls(calls).length, 1)
  assert.equal(rpcNames(calls).includes('sweep_copying_finish'), false)
})

const listXml = (versions: string, truncated: boolean, next = '') =>
  `<ListVersionsResult><IsTruncated>${truncated}</IsTruncated>${next}${versions}</ListVersionsResult>`
const reconcileJob = {
  id: 31,
  kind: 'storage_reconcile',
  payload: {},
  attempts: 1,
}

test('storage_reconcile: หน้าละ 1000 ต่อจาก cursor → step ทุกหน้า → done · ไม่ลบไฟล์', async () => {
  const claim = claimOnce([reconcileJob])
  const { handler, calls } = setup({
    rpc: (fn, body, n) =>
      fn === 'copying_stale'
        ? []
        : fn === 'jobs_claim'
          ? claim(n)
          : fn === 'storage_reconcile_start'
            ? {
                action: 'list',
                allow: 5,
                key_marker: 'files/m.pdf',
                version_id_marker: '4_zM',
              }
            : fn === 'storage_reconcile_step'
              ? (body.p_page as { truncated: boolean }).truncated
                ? {
                    action: 'list',
                    key_marker: 'files/n.pdf',
                    version_id_marker: '4_zN',
                  }
                : { action: 'done', diff_bytes: 0 }
              : 'pending',
    b2: (_method, url) =>
      url.searchParams.get('key-marker') === 'files/m.pdf'
        ? new Response(
            listXml(
              '<Version><Key>files/n.pdf</Key><VersionId>4_zN</VersionId><IsLatest>false</IsLatest><Size>9</Size></Version>',
              true,
              '<NextKeyMarker>files/n.pdf</NextKeyMarker><NextVersionIdMarker>4_zN</NextVersionIdMarker>',
            ),
          )
        : new Response(listXml('<DeleteMarker><Key>x</Key></DeleteMarker>', false)),
  })
  const res = await handler(call())
  const summary = (await res.json()) as {
    jobs: Record<string, number>
    reconcile: { requests: number; result: string }
  }
  const lists = b2Calls(calls)
  assert.deepEqual(
    lists.map((c) => [c.method, new URL(c.url).searchParams.get('key-marker')]),
    [
      ['GET', 'files/m.pdf'],
      ['GET', 'files/n.pdf'],
    ],
    'ทำต่อจาก cursor ที่ฐานข้อมูลเก็บไว้ แล้วตาม cursor หน้าถัดไป',
  )
  assert.equal(new URL(lists[0].url).searchParams.get('max-keys'), '1000')
  const steps = calls.filter((c) => c.url.endsWith('/storage_reconcile_step')).map((c) => c.body)
  assert.deepEqual(steps[0], {
    p_job_id: 31,
    p_page: {
      ok: true,
      versions: [{ k: 'files/n.pdf', v: '4_zN', s: 9, l: false }],
      delete_markers: 0,
      truncated: true,
      next_key_marker: 'files/n.pdf',
      next_version_id_marker: '4_zN',
    },
    p_more: true,
  })
  assert.equal((steps[1].p_page as { delete_markers: number }).delete_markers, 1)
  assert.deepEqual(summary.reconcile, { requests: 2, result: 'done' })
  assert.equal(summary.jobs.done, 1)
  assert.equal(
    lists.some((c) => c.method !== 'GET'),
    false,
    'ผลเทียบไม่ลบ/ไม่แก้ไฟล์ใน B2',
  )
})

test('storage_reconcile: ครบ allow → หน้าสุดท้ายของรอบส่ง p_more false · ไม่ขอเกิน', async () => {
  const claim = claimOnce([reconcileJob])
  const { handler, calls } = setup({
    rpc: (fn, body, n) =>
      fn === 'copying_stale'
        ? []
        : fn === 'jobs_claim'
          ? claim(n)
          : fn === 'storage_reconcile_start'
            ? {
                action: 'list',
                allow: 2,
                key_marker: null,
                version_id_marker: null,
              }
            : fn === 'storage_reconcile_step'
              ? body.p_more
                ? { action: 'list', key_marker: 'k', version_id_marker: 'v' }
                : { action: 'later' }
              : 'pending',
    b2: () => new Response(listXml('', true, '<NextKeyMarker>k</NextKeyMarker>')),
  })
  const summary = (await (await handler(call())).json()) as {
    reconcile: { requests: number; result: string }
  }
  assert.equal(b2Calls(calls).length, 2, 'เพดานต่อรอบ = allow จากฐานข้อมูล')
  assert.equal(
    new URL(b2Calls(calls)[0].url).searchParams.has('key-marker'),
    false,
    'หน้าแรกของการเทียบ',
  )
  assert.deepEqual(
    calls.filter((c) => c.url.endsWith('/storage_reconcile_step')).map((c) => c.body.p_more),
    [true, false],
  )
  assert.deepEqual(summary.reconcile, { requests: 2, result: 'later' })
})

test('storage_reconcile: B2 เกินเพดาน → ส่ง cap · งบวันหมด (paused) → ไม่เรียก B2 · start ล้ม → jobs_fail', async () => {
  const run = async (start: unknown, b2?: () => Response) => {
    const claim = claimOnce([reconcileJob])
    return setup({
      rpc: (fn, _body, n) =>
        fn === 'copying_stale'
          ? []
          : fn === 'jobs_claim'
            ? claim(n)
            : fn === 'storage_reconcile_start'
              ? start
              : fn === 'storage_reconcile_step'
                ? { action: 'paused', reason: 'b2_cap' }
                : 'pending',
      b2,
    })
  }
  const capped = await run(
    { action: 'list', allow: 5 },
    () =>
      new Response(
        '<Error><Code>AccessDenied</Code><Message>Transaction cap exceeded</Message></Error>',
        {
          status: 403,
        },
      ),
  )
  await capped.handler(call())
  const capStep = capped.calls.filter((c) => c.url.endsWith('/storage_reconcile_step'))
  assert.equal(capStep.length, 1, 'หยุดหลังหน้าแรกที่ถูกปฏิเสธ')
  assert.deepEqual(capStep[0].body.p_page, {
    ok: false,
    error: 'b2_403',
    cap: true,
  })

  const paused = await run({ action: 'paused', reason: 'daily_budget' })
  const summary = (await (await paused.handler(call())).json()) as {
    reconcile: { requests: number; result: string }
  }
  assert.equal(b2Calls(paused.calls).length, 0)
  assert.deepEqual(summary.reconcile, { requests: 0, result: 'paused' })

  const broken = await run(json({ code: 'XX000', message: 'boom' }, 500))
  await broken.handler(call())
  const fails = broken.calls.filter((c) => c.url.endsWith('/jobs_fail'))
  assert.equal(fails.length, 1)
  assert.match(String(fails[0].body.p_error), /^reconcile_start_/)
})
