// พิสูจน์ขั้น complete กับ bucket kemi-dev-files (P3-04 ข้อ ฉ.) — รันด้วยมือ ไม่อยู่ใน CI
//   node ops/b2/proof-complete.mjs
// ใช้กุญแจ kemi-edge-dev (ถามแบบซ่อนตัวอักษร หรืออ่าน B2_KEY_ID / B2_APP_KEY จาก env ของ session)
// ใช้ฟังก์ชันชุดเดียวกับ Edge Function (supabase/functions/_shared/b2.ts, filetype.ts)
// ขั้นตอน — ลิงก์ PUT เดียวกันใช้ซ้ำสามครั้ง (เหมือนนักเรียนอัปทับด้วยลิงก์เดิม):
//   1. PUT V1 = PDF ถูกต้อง  2. PUT V2 = ขนาดเท่ากันแต่ไม่ใช่ PDF (อัปทับก่อน complete)
//   3. GET แบบ Range ของไฟล์พัก (ล่าสุด = V2) → magic number ผิด ขั้น complete จะปฏิเสธ (upload_type_mismatch)
//   4. CopyObject ระบุ versionId = V1 + REPLACE ชนิด application/pdf → files/{uuid}.pdf (ต้องได้ V1 ไม่ใช่ V2)
//   5. PUT V3 (อัปทับหลัง complete)  6. GET แบบ Range ของไฟล์จริง → ยังเป็น V1, ชนิดเป็น PDF, ETag/เวอร์ชันตรง
//   7. ลบทุกเวอร์ชันที่สร้างแบบระบุ versionId
// คำขอ: Class A 8 (PUT 3 + CopyObject 1 + DELETE 4, ไม่นับเพดาน) · Class B 2 (GET 16 ไบต์ × 2)
// ไม่พิมพ์กุญแจหรือลิงก์ที่ลงลายเซ็น · ไม่ทดสอบการเกินเพดาน
import { createHash, randomUUID } from 'node:crypto'
import {
  b2ConfigFrom,
  copyObjectRequest,
  deleteVersionRequest,
  parseCopyResult,
  presignGet,
  presignPut,
  rangeGetRequest,
  readRange,
  stripEtag,
} from '../../supabase/functions/_shared/b2.ts'
import { detectType } from '../../supabase/functions/_shared/filetype.ts'
import { counts, DEV_BUCKET, DEV_ENDPOINT, printCounts, secretFromEnvOrAsk } from './b2-native.mjs'

const results = []
const created = [] // { key, versionId } ลบท้ายสคริปต์เสมอ
let config = null
const record = (name, pass, detail) => {
  results.push({ name, pass, detail })
  console.log(`${pass ? '✓' : '✗'} ${name}${detail ? ` — ${detail}` : ''}`)
}
const s3Code = (text) => /<Code>([^<]+)<\/Code>/.exec(text)?.[1] ?? '-'
const sized = (text, n) => Buffer.from(text.padEnd(n, '.').slice(0, n), 'utf8')

async function main() {
  const keyId = await secretFromEnvOrAsk('B2_KEY_ID', 'keyID ของ kemi-edge-dev')
  const appKey = await secretFromEnvOrAsk('B2_APP_KEY', 'applicationKey ของ kemi-edge-dev')
  const env = {
    B2_KEY_ID: keyId,
    B2_APP_KEY: appKey,
    B2_BUCKET: DEV_BUCKET,
    B2_ENDPOINT: DEV_ENDPOINT,
  }
  config = b2ConfigFrom((n) => env[n])

  const N = 64
  const v1 = sized(`%PDF-1.4\n% kemi complete proof V1 ${new Date().toISOString()}\n`, N)
  const v2 = sized('<html>not a pdf — overwritten before complete</html>', N)
  const v3 = sized('%PDF-1.4\n% V3 overwritten after complete\n', N)
  const md5 = (b) => createHash('md5').update(b).digest('hex')
  const staging = `staging/${randomUUID()}/${randomUUID()}`
  const finalKey = `files/${randomUUID()}.pdf`
  // ลิงก์เดียวใช้ซ้ำ — ชนิดในลายเซ็นเป็น octet-stream เพื่อให้เห็นว่า REPLACE ตั้งชนิดใหม่ให้ไฟล์จริงได้
  const link = await presignPut(config, {
    key: staging,
    contentType: 'application/octet-stream',
    sizeBytes: N,
  })
  const put = async (label, body) => {
    counts.classA++
    const res = await fetch(link, {
      method: 'PUT',
      headers: { 'content-type': 'application/octet-stream' },
      body,
    })
    const versionId = res.headers.get('x-amz-version-id')
    if (res.ok && versionId) created.push({ key: staging, versionId })
    record(
      `PUT ${label} ด้วยลิงก์เดิม`,
      res.status === 200 && !!versionId,
      `HTTP ${res.status}${res.ok ? '' : ` ${s3Code(await res.text())}`}`,
    )
    return res.ok ? versionId : null
  }

  const ver1 = await put('V1 (PDF)', v1)
  const ver2 = await put('V2 (ไม่ใช่ PDF, อัปทับก่อน complete)', v2)
  if (!ver1 || !ver2) return

  // 3. GET แบบ Range ของไฟล์พัก — เหมือนขั้น complete
  counts.classB++
  const got = await readRange(await fetch(await rangeGetRequest(config, staging)))
  record(
    'GET แบบ Range ของไฟล์พักได้เวอร์ชันล่าสุด (V2)',
    got?.versionId === ver2,
    got ? `ขนาดเต็ม ${got.totalBytes}` : 'อ่านไม่ได้',
  )
  record(
    'magic number ของ V2 ไม่ใช่ JPEG/PNG/PDF → complete ปฏิเสธ (upload_type_mismatch)',
    got !== null && detectType(got.bytes) === null,
    got ? `ตรวจได้ ${detectType(got.bytes) ?? 'null'}` : '-',
  )

  // 4. CopyObject ระบุเวอร์ชัน V1 (ไม่ใช่เวอร์ชันล่าสุด)
  counts.classA++
  const copied = await fetch(
    await copyObjectRequest(config, {
      sourceKey: staging,
      sourceVersionId: ver1,
      destKey: finalKey,
      contentType: 'application/pdf',
    }),
  )
  const copyText = await copied.text()
  const parsed = parseCopyResult(copied.status, copyText)
  const finalVersion = copied.headers.get('x-amz-version-id')
  if (parsed && finalVersion) created.push({ key: finalKey, versionId: finalVersion })
  record(
    'CopyObject ระบุ versionId ต้นทางสำเร็จ',
    !!parsed && !!finalVersion,
    `HTTP ${copied.status}${parsed ? '' : ` ${s3Code(copyText)}`}, version ปลายทาง ${finalVersion ? 'มี' : 'ไม่มี'}`,
  )
  if (!parsed || !finalVersion) return
  const rawEtag = /<ETag>([^<]*)<\/ETag>/.exec(copyText)?.[1] ?? '-'
  record(
    'ข้อ 9: ETag ของ CopyObject = MD5 ของเนื้อไฟล์ V1',
    parsed.etag === md5(v1),
    `ใน XML: ${rawEtag} · MD5(V1) ${md5(v1)}`,
  )

  // 5. อัปทับไฟล์พักหลัง complete
  await put('V3 (อัปทับหลัง complete)', v3)

  // 6. ไฟล์จริงยังเป็น V1
  counts.classB++
  const res = await fetch(await presignGet(config, { key: finalKey, versionId: finalVersion }), {
    headers: { Range: 'bytes=0-15' },
  })
  const bytes = Buffer.from(await res.arrayBuffer())
  const h = (n) => res.headers.get(n)
  record(
    'ข้อ 7: ไฟล์จริงเป็นเนื้อของ V1 (คัดลอกตามเวอร์ชันที่ระบุ) และไม่เปลี่ยนหลังอัปทับไฟล์พัก',
    res.status === 206 && bytes.equals(v1.subarray(0, 16)),
    `HTTP ${res.status}`,
  )
  record(
    'REPLACE ตั้งชนิดไฟล์จริงเป็น application/pdf (ไฟล์พักเป็น octet-stream)',
    h('content-type') === 'application/pdf',
    h('content-type') ?? '-',
  )
  record(
    'ไฟล์จริง: x-amz-version-id ตรงกับที่ CopyObject คืน',
    h('x-amz-version-id') === finalVersion,
    h('x-amz-version-id') ? 'มี' : 'ไม่มี',
  )
  record(
    'ไฟล์จริง: ETag ตรงกับที่ CopyObject คืน',
    stripEtag(h('etag')) === parsed.etag,
    h('etag') ?? '-',
  )
  record(
    'ไฟล์จริง: Content-Range บอกขนาดเท่าไฟล์พัก',
    h('content-range') === `bytes 0-15/${N}`,
    h('content-range') ?? '-',
  )
}

// 7. ลบทุกเวอร์ชันที่สร้าง (ลบจริงแบบระบุ versionId) — ไฟล์ที่ลบไม่ได้ lifecycle ล้างให้ (staging/ 2 วัน; files/ ต้องลบเอง)
async function cleanup() {
  for (const item of created.splice(0)) {
    counts.classA++
    const res = await fetch(await deleteVersionRequest(config, item.key, item.versionId))
    await res.body?.cancel()
    record(
      `DELETE ระบุ versionId (${item.key.split('/')[0]}/)`,
      res.status === 204,
      `HTTP ${res.status}`,
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
    if (config) await cleanup()
  } catch (e) {
    console.error(`✗ ลบไฟล์ทดสอบไม่สำเร็จ: ${e.message}`)
  }
  const failed = results.filter((r) => !r.pass).length
  console.log(`\nสรุป: ผ่าน ${results.length - failed}/${results.length}`)
  printCounts()
  if (failed) process.exitCode = 1
}
