// ตั้ง CORS + lifecycle ของ bucket kemi-dev-files (P3-03) — ผู้ใช้รันเองใน terminal ของตัวเอง
//   node ops/b2/apply-settings.mjs
// ขั้นตอน (TECHNICAL_BUILD_PLAN 7 Backblaze ข้อ 3–4, TECHNICAL_DESIGN 9.2):
//   1. ถามกุญแจหลัก (Master Application Key) แบบซ่อนตัวอักษร — ใช้แค่สร้างและลบกุญแจชั่วคราว ไม่เก็บ ไม่พิมพ์
//   2. สร้างกุญแจชั่วคราวเฉพาะ bucket นี้ สิทธิ์ listBuckets + writeBuckets อายุ 1 ชั่วโมง
//   3. ใช้กุญแจชั่วคราวตั้ง corsRules (cors.json) + lifecycleRules (lifecycle.json) แล้วอ่านกลับมาแสดง
//   4. ลบกุญแจชั่วคราวทิ้งเสมอ แม้ขั้นก่อนหน้าล้ม
// แตะเฉพาะ kemi-dev-files — bucket ใช้จริง (kemi-files) ตั้งในระยะ 7 ด้วยรายการ origin ของ production อย่างเดียว
import { readFileSync } from 'node:fs'
import { askSecret, authorize, call, DEV_BUCKET, printCounts } from './b2-native.mjs'
import { sameRules } from './rules.mjs'

const here = (name) => new URL(name, import.meta.url)
const corsRules = JSON.parse(readFileSync(here('cors.json'), 'utf8'))
const lifecycleRules = JSON.parse(readFileSync(here('lifecycle.json'), 'utf8'))

async function main() {
  console.log(`ตั้งค่า bucket ${DEV_BUCKET} — ใช้กุญแจหลักเพื่อสร้าง/ลบกุญแจชั่วคราวเท่านั้น`)
  const masterId = await askSecret('Master keyID')
  const masterKey = await askSecret('Master applicationKey')
  const master = await authorize(masterId, masterKey)
  console.log(`S3 endpoint ของบัญชี: ${master.s3ApiUrl}`)
  if (!master.s3ApiUrl.includes('s3.eu-central-003.')) {
    console.log('  ⚠ endpoint ไม่ใช่ eu-central-003 — หยุดแล้วแจ้ง Claude ก่อนทำต่อ')
    return
  }

  const { buckets } = await call(master, 'b2_list_buckets', {
    accountId: master.accountId,
    bucketName: DEV_BUCKET,
  })
  const bucket = buckets?.[0]
  if (!bucket) throw new Error(`ไม่พบ bucket ${DEV_BUCKET} — สร้างก่อน (ops/b2/README.md ขั้น 1)`)
  console.log(`bucket ${bucket.bucketName}: ชนิด ${bucket.bucketType}`)
  if (bucket.bucketType !== 'allPrivate') {
    throw new Error('bucket ต้องเป็น Private — แก้ในหน้า Buckets ก่อน แล้วรันใหม่')
  }

  const temp = await call(master, 'b2_create_key', {
    accountId: master.accountId,
    capabilities: ['listBuckets', 'writeBuckets'],
    keyName: `kemi-dev-settings-tmp-${Date.now()}`,
    validDurationInSeconds: 3600,
    bucketIds: [bucket.bucketId],
  })
  console.log(
    `สร้างกุญแจชั่วคราวแล้ว: ${temp.keyName} (สิทธิ์ ${temp.capabilities.join(', ')}; อายุ 1 ชม.)`,
  )
  try {
    const auth = await authorize(temp.applicationKeyId, temp.applicationKey)
    const updated = await call(auth, 'b2_update_bucket', {
      accountId: auth.accountId,
      bucketId: bucket.bucketId,
      corsRules,
      lifecycleRules,
      ifRevisionIs: bucket.revision,
    })
    console.log('\nCORS ที่ตั้งแล้ว (อ่านกลับจาก B2):')
    console.log(JSON.stringify(updated.corsRules, null, 2))
    console.log('\nLifecycle ที่ตั้งแล้ว (อ่านกลับจาก B2):')
    console.log(JSON.stringify(updated.lifecycleRules, null, 2))
    const sameCors = sameRules(corsRules, updated.corsRules, 'corsRuleName')
    const sameLifecycle = sameRules(lifecycleRules, updated.lifecycleRules, 'fileNamePrefix')
    const prefixes = (updated.lifecycleRules ?? []).map((r) => r.fileNamePrefix).sort()
    console.log(`\nCORS ตรงกับ cors.json: ${sameCors ? 'ใช่' : 'ไม่ตรง (ดูด้านบน)'}`)
    console.log(`lifecycle ตรงกับ lifecycle.json: ${sameLifecycle ? 'ใช่' : 'ไม่ตรง (ดูด้านบน)'}`)
    console.log(`lifecycle แยก prefix: ${prefixes.join(' , ') || '-'}`)
  } finally {
    await call(master, 'b2_delete_key', { applicationKeyId: temp.applicationKeyId })
    console.log('ลบกุญแจชั่วคราวแล้ว')
  }
}

try {
  await main()
} catch (e) {
  console.error(`\n✗ ${e.message}`)
  process.exitCode = 1
} finally {
  printCounts()
}
