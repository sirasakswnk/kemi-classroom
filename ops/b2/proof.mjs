// พิสูจน์พฤติกรรมของ B2 กับ bucket kemi-dev-files (P3-03 ข้อ จ.) — รันด้วยมือ ไม่อยู่ใน CI
//   node ops/b2/proof.mjs
// ใช้กุญแจชั่วคราว (เช่น kemi-proof-tmp — ห้ามลบ/สร้าง kemi-edge-dev แทน) ถามแบบซ่อนตัวอักษร หรืออ่าน B2_KEY_ID / B2_APP_KEY จาก env ของ session
// ใช้คำขอน้อยที่สุด: PUT 3 + DELETE 1 (Class A ไม่นับเพดาน) · GET แบบ Range 1 ครั้ง 16 ไบต์ (Class B) · OPTIONS 4
// ไม่พิมพ์กุญแจหรือลิงก์ที่ลงลายเซ็น — พิมพ์เฉพาะสถานะและ header ที่ต้องดู ส่งผลส่วนนี้ให้ Claude ได้
// ไม่ทดสอบการเกินเพดาน (ทำให้ทั้งบัญชีใช้ไม่ได้จนถึง 07:00 น.) — รูปแบบ 403 ยืนยันจากเอกสาร B2 แทน
import { createHash, randomUUID } from 'node:crypto'
import { AwsClient } from 'aws4fetch'
import {
  b2ConfigFrom,
  contentDisposition,
  GET_CACHE_CONTROL,
  presignGet,
  presignPut,
} from '../../supabase/functions/_shared/b2.ts'
import { counts, DEV_BUCKET, DEV_ENDPOINT, printCounts, secretFromEnvOrAsk } from './b2-native.mjs'

const ORIGINS = {
  production: 'https://kemi-classroom.pages.dev',
  preview: 'https://phase-3.kemi-classroom.pages.dev',
  localhost: 'http://localhost:5173',
  other: 'https://example.com',
}
const results = []
const uploaded = [] // { key, versionId } ที่ต้องลบท้ายสคริปต์เสมอ
let aws = null
const record = (name, pass, detail) => {
  results.push({ name, pass, detail })
  console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ` — ${detail}` : ''}`)
}
const s3Code = async (res) => /<Code>([^<]+)<\/Code>/.exec(await res.text())?.[1] ?? '-'

async function main() {
  const keyId = await secretFromEnvOrAsk('B2_KEY_ID', 'keyID ของกุญแจชั่วคราว (เช่น kemi-proof-tmp)')
  const appKey = await secretFromEnvOrAsk('B2_APP_KEY', 'applicationKey ของกุญแจชั่วคราว')
  const env = {
    B2_KEY_ID: keyId,
    B2_APP_KEY: appKey,
    B2_BUCKET: DEV_BUCKET,
    B2_ENDPOINT: DEV_ENDPOINT,
  }
  const config = b2ConfigFrom((n) => env[n])
  aws = new AwsClient({
    accessKeyId: keyId,
    secretAccessKey: appKey,
    service: 's3',
    region: config.region,
  })
  const batch = randomUUID()
  const keyOf = () => `staging/${batch}/${randomUUID()}`

  const body = Buffer.from(`%PDF-1.4\n% kemi proof ทดสอบ ${new Date().toISOString()}\n`, 'utf8')
  const md5 = createHash('md5').update(body).digest('hex')
  console.log(`bucket ${DEV_BUCKET} · ไฟล์ทดสอบ ${body.length} ไบต์ ใต้ staging/${batch}/\n`)

  // 1. PUT ตามลายเซ็น (ชนิด + ขนาดตรง) → ต้องผ่าน
  const key = keyOf()
  counts.classA++
  const put = await fetch(
    await presignPut(config, { key, contentType: 'application/pdf', sizeBytes: body.length }),
    {
      method: 'PUT',
      headers: { 'content-type': 'application/pdf' },
      body,
    },
  )
  const versionId = put.headers.get('x-amz-version-id')
  const etag = put.headers.get('etag')
  if (put.ok && versionId) uploaded.push({ key, versionId })
  record(
    'PUT ตามลายเซ็น',
    put.status === 200 && !!versionId,
    `HTTP ${put.status}${put.ok ? '' : ` ${await s3Code(put)}`}, version id ${versionId ? 'มี' : 'ไม่มี'}`,
  )
  if (!put.ok || !versionId) return

  // 2. PUT ที่ขนาด/ชนิดไม่ตรงลายเซ็น → B2 ต้องปฏิเสธ (เบราว์เซอร์ตั้ง Content-Length ตามไฟล์จริงเสมอ)
  for (const [name, signed, sent] of [
    [
      'PUT ขนาดจริงไม่ตรงลายเซ็น (+1 ไบต์)',
      { contentType: 'application/pdf', sizeBytes: body.length },
      { type: 'application/pdf', data: Buffer.concat([body, Buffer.from('x')]) },
    ],
    [
      'PUT ชนิดไม่ตรงลายเซ็น (png แทน pdf)',
      { contentType: 'application/pdf', sizeBytes: body.length },
      { type: 'image/png', data: body },
    ],
  ]) {
    const k = keyOf()
    counts.classA++
    const res = await fetch(await presignPut(config, { key: k, ...signed }), {
      method: 'PUT',
      headers: { 'content-type': sent.type },
      body: sent.data,
    })
    const v = res.headers.get('x-amz-version-id')
    if (res.ok && v) uploaded.push({ key: k, versionId: v })
    record(
      name,
      res.status === 403,
      `HTTP ${res.status} ${res.ok ? '(รับไว้ — ไม่ควรเป็นแบบนี้)' : await s3Code(res)}`,
    )
  }

  // 3. GET แบบ Range 16 ไบต์ อ้าง versionId + response-* (ข้อ 18, 9, 10) พร้อม Origin เพื่อดู CORS ของคำตอบจริง
  const disposition = contentDisposition('attachment', 'ใบงาน ที่ 1 (เฉลย).pdf')
  counts.classB++
  const get = await fetch(
    await presignGet(config, {
      key,
      versionId,
      contentType: 'application/pdf',
      disposition,
      cacheControl: GET_CACHE_CONTROL,
    }),
    { headers: { Range: 'bytes=0-15', Origin: ORIGINS.production } },
  )
  const bytes = Buffer.from(await get.arrayBuffer())
  const h = (n) => get.headers.get(n)
  record(
    'ข้อ 18: GET แบบ Range ได้ 206 และ 16 ไบต์แรก',
    get.status === 206 && bytes.equals(body.subarray(0, 16)),
    `HTTP ${get.status}, ${bytes.length} ไบต์`,
  )
  record(
    'ข้อ 18: คำตอบมี x-amz-version-id ตรงกับตอน PUT',
    h('x-amz-version-id') === versionId,
    h('x-amz-version-id') ? 'มี' : 'ไม่มี',
  )
  record(
    'ข้อ 18: Content-Range บอกขนาดเต็ม',
    h('content-range') === `bytes 0-15/${body.length}`,
    h('content-range') ?? '-',
  )
  record(
    'ข้อ 18: response-cache-control',
    h('cache-control') === GET_CACHE_CONTROL,
    h('cache-control') ?? '-',
  )
  record(
    'ข้อ 10: response-content-type',
    h('content-type') === 'application/pdf',
    h('content-type') ?? '-',
  )
  record(
    'ข้อ 10: response-content-disposition (ชื่อไทย)',
    h('content-disposition') === disposition,
    h('content-disposition') ?? '-',
  )
  const etagIsMd5 = etag === `"${md5}"`
  record(
    'ข้อ 9: ETag ของ PUT ชิ้นเดียว = MD5 ของเนื้อไฟล์',
    etagIsMd5,
    `ETag ${etag ?? '-'} · MD5 ${md5}`,
  )
  record('ข้อ 9: ETag ตอน GET ตรงกับตอน PUT', h('etag') === etag, h('etag') ?? '-')
  record(
    'CORS: GET จริงมี Access-Control-Allow-Origin',
    h('access-control-allow-origin') === ORIGINS.production,
    h('access-control-allow-origin') ?? '-',
  )
  const expose = (h('access-control-expose-headers') ?? '').toLowerCase()
  record(
    'CORS: เปิดให้อ่าน ETag และ x-amz-version-id',
    expose.includes('etag') && expose.includes('x-amz-version-id'),
    h('access-control-expose-headers') ?? '-',
  )

  // 4. CORS preflight ของการอัปโหลด: เว็บของเราผ่าน origin อื่นไม่ผ่าน
  for (const [label, origin] of Object.entries(ORIGINS)) {
    counts.preflight++
    const res = await fetch(`${DEV_ENDPOINT}/${DEV_BUCKET}/${key}`, {
      method: 'OPTIONS',
      headers: {
        Origin: origin,
        'Access-Control-Request-Method': 'PUT',
        'Access-Control-Request-Headers': 'content-type',
      },
    })
    const allowed = res.headers.get('access-control-allow-origin') === origin
    const expected = label !== 'other'
    record(
      `CORS preflight PUT จาก ${label}`,
      allowed === expected,
      `HTTP ${res.status}, ${allowed ? 'อนุญาต' : 'ไม่อนุญาต'}`,
    )
  }
}

// 5. ลบโดยระบุ versionId (ลบจริง ไม่ใช่ซ่อน) — รันใน finally เสมอ ไฟล์ที่ลบไม่ได้ lifecycle ของ staging/ ล้างใน 2 วัน
async function cleanup() {
  for (const item of uploaded.splice(0)) {
    counts.classA++
    const url = new URL(`${DEV_ENDPOINT}/${DEV_BUCKET}/${item.key}`)
    url.searchParams.set('versionId', item.versionId)
    const res = await aws.fetch(url, { method: 'DELETE' })
    record(
      'DELETE ระบุ versionId',
      res.status === 204 && res.headers.get('x-amz-delete-marker') !== 'true',
      `HTTP ${res.status}, delete marker ${res.headers.get('x-amz-delete-marker') ?? 'ไม่มี'}`,
    )
  }
}

try {
  await main()
} catch (e) {
  console.error(`\n✗ ${e.message}`)
  process.exitCode = 1
} finally {
  try {
    await cleanup()
  } catch (e) {
    console.error(`✗ ลบไฟล์ทดสอบไม่สำเร็จ: ${e.message} (lifecycle ของ staging/ จะล้างให้)`)
  }
  const failed = results.filter((r) => !r.pass).length
  console.log(`\nสรุป: ผ่าน ${results.length - failed}/${results.length}`)
  printCounts()
  if (failed) process.exitCode = 1
}
