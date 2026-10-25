// ตั้ง bucket kemi-files + สร้างกุญแจ B2 สิทธิ์แคบของ prod (P7-06-1; ops/prod-setup.md ข้อ 3.4) — ผู้ใช้รันเองในเครื่อง
//   node ops/b2/prod-keys.mjs                  → kemi-files: CORS เฉพาะ production + lifecycle + กุญแจ kemi-edge, kemi-backup-ro
//   node ops/b2/prod-keys.mjs --test-on-dev    → kemi-dev-files: ไม่แตะ CORS/lifecycle สร้างกุญแจทดสอบสิทธิ์ชุดเดียวกัน
//                                                 อายุ 1 วัน (ชื่อลงท้าย -test) ไว้ลองกับ proof.mjs / proof-complete.mjs ก่อนใช้จริง
// ความลับ:
//   - กุญแจหลัก (Master Application Key) ถามแบบซ่อนตัวอักษรเท่านั้น — ไม่รับทาง argument, env หรือไฟล์ ไม่เก็บ ไม่พิมพ์
//   - applicationKey ของกุญแจใหม่แสดงบนจอครั้งเดียวเมื่อผู้ใช้กด Enter แล้วล้างจอ — คัดลอกไปใส่ secret เอง
//     (kemi-edge → Supabase secrets ของ kemi-prod · kemi-backup-ro → rclone remote b2ro) ไม่บันทึกลงไฟล์
//   - ผลที่ส่งให้ Claude ได้: ชื่อกุญแจ keyID สิทธิ์ prefix CORS lifecycle (ไม่ใช่ความลับ)
// สิทธิ์ (TECHNICAL_BUILD_PLAN 7 ข้อ 5 — ไม่มี writeBuckets/สิทธิ์จัดการ bucket):
//   kemi-edge      readFiles + writeFiles + deleteFiles + listFiles เฉพาะ bucket
//                  (PUT ลิงก์อัปโหลด, GET/HEAD, CopyObject, ลบระบุเวอร์ชัน, ListObjectVersions ของงานเทียบยอด)
//   kemi-backup-ro readFiles เฉพาะ bucket prefix files/ (งานสำรองใช้แค่ get-object ตามเวอร์ชัน)
import { readFileSync } from 'node:fs'
import { askSecret, authorize, call, DEV_BUCKET, printCounts } from './b2-native.mjs'
import { sameRules } from './rules.mjs'

const PROD_BUCKET = 'kemi-files'
const testOnDev = process.argv.includes('--test-on-dev')
const bucketName = testOnDev ? DEV_BUCKET : PROD_BUCKET
const suffix = testOnDev ? '-test' : ''
const KEYS = [
  {
    keyName: `kemi-edge${suffix}`,
    capabilities: ['listFiles', 'readFiles', 'writeFiles', 'deleteFiles'],
    use: 'Supabase secrets ของ kemi-prod: B2_KEY_ID / B2_APP_KEY (ops/prod-setup.md ข้อ 4)',
  },
  {
    keyName: `kemi-backup-ro${suffix}`,
    capabilities: ['readFiles'],
    namePrefix: 'files/',
    use: 'rclone remote b2ro ของชุด prod (ops/prod-setup.md ข้อ 7.4)',
  },
]
const here = (name) => new URL(name, import.meta.url)
const corsRules = JSON.parse(readFileSync(here('cors-prod.json'), 'utf8'))
const lifecycleRules = JSON.parse(readFileSync(here('lifecycle.json'), 'utf8'))

/** รอผู้ใช้กด Enter (ไม่รับค่า) */
function waitEnter(label) {
  process.stdout.write(`${label} `)
  return new Promise((resolve) => {
    process.stdin.resume()
    process.stdin.once('data', () => {
      process.stdin.pause()
      resolve()
    })
  })
}

/** ล้างจอและ scrollback ของ terminal (กัน applicationKey ค้างบนจอ) */
const clearScreen = () => process.stdout.write('\x1b[2J\x1b[3J\x1b[H')

async function main() {
  console.log(
    testOnDev
      ? `โหมดทดสอบ: สร้างกุญแจสิทธิ์แคบอายุ 1 วันบน ${DEV_BUCKET} (ไม่แตะ CORS/lifecycle)`
      : `ตั้ง ${PROD_BUCKET} (CORS เฉพาะ https://kemi-classroom.pages.dev + lifecycle) และสร้างกุญแจของ prod`,
  )
  console.log('กุญแจหลักใช้แค่ในการรันครั้งนี้ ไม่ถูกเก็บหรือพิมพ์ออก')
  const masterId = await askSecret('Master keyID')
  const masterKey = await askSecret('Master applicationKey')
  const master = await authorize(masterId, masterKey)
  if (!master.s3ApiUrl.includes('s3.eu-central-003.')) {
    throw new Error('endpoint ของบัญชีไม่ใช่ eu-central-003 — หยุดแล้วแจ้ง Claude')
  }

  const { buckets } = await call(master, 'b2_list_buckets', {
    accountId: master.accountId,
    bucketName,
  })
  const bucket = buckets?.[0]
  if (!bucket) throw new Error(`ไม่พบ bucket ${bucketName} — สร้างก่อน (ops/prod-setup.md ข้อ 3.2)`)
  if (bucket.bucketType !== 'allPrivate') {
    throw new Error(`bucket ${bucketName} ต้องเป็น Private — แก้ในหน้า Buckets ก่อน แล้วรันใหม่`)
  }
  console.log(`bucket ${bucket.bucketName}: Private`)

  // ชื่อกุญแจซ้ำ = หยุด (กันมีกุญแจสองชุดที่ไม่รู้ว่าตัวไหนใช้อยู่ — ลบตัวเก่าในหน้า Application Keys ก่อน)
  const existing = await call(master, 'b2_list_keys', {
    accountId: master.accountId,
    maxKeyCount: 1000,
  })
  const taken = KEYS.filter((k) => existing.keys?.some((e) => e.keyName === k.keyName))
  if (taken.length) {
    throw new Error(
      `มีกุญแจชื่อ ${taken.map((k) => k.keyName).join(', ')} อยู่แล้ว — ลบในหน้า Application Keys ก่อนถ้าจะสร้างใหม่`,
    )
  }

  if (!testOnDev) {
    const updated = await call(master, 'b2_update_bucket', {
      accountId: master.accountId,
      bucketId: bucket.bucketId,
      corsRules,
      lifecycleRules,
      ifRevisionIs: bucket.revision,
    })
    const okCors = sameRules(corsRules, updated.corsRules, 'corsRuleName')
    const okLifecycle = sameRules(lifecycleRules, updated.lifecycleRules, 'fileNamePrefix')
    console.log(
      `CORS (อ่านกลับ): origin ${JSON.stringify(updated.corsRules?.[0]?.allowedOrigins ?? [])} · ตรง cors-prod.json: ${okCors ? 'ใช่' : 'ไม่ตรง'}`,
    )
    console.log(
      `lifecycle (อ่านกลับ): ${(updated.lifecycleRules ?? []).map((r) => r.fileNamePrefix).join(' , ')} · ตรง lifecycle.json: ${okLifecycle ? 'ใช่' : 'ไม่ตรง'}`,
    )
    if (!okCors || !okLifecycle)
      throw new Error('ค่า bucket ไม่ตรงที่ตั้ง — หยุดก่อนสร้างกุญแจ แจ้ง Claude')
  }

  const created = []
  for (const k of KEYS) {
    const key = await call(master, 'b2_create_key', {
      accountId: master.accountId,
      keyName: k.keyName,
      capabilities: k.capabilities,
      bucketIds: [bucket.bucketId],
      ...(k.namePrefix ? { namePrefix: k.namePrefix } : {}),
      ...(testOnDev ? { validDurationInSeconds: 86400 } : {}),
    })
    created.push({ ...k, id: key.applicationKeyId, secret: key.applicationKey, got: key })
    console.log(
      `สร้าง ${key.keyName}: keyID ${key.applicationKeyId} · สิทธิ์ ${key.capabilities.join(', ')}` +
        `${key.namePrefix ? ` · prefix ${key.namePrefix}` : ''} · bucket ${bucketName}`,
    )
  }

  console.log(
    '\nขั้นต่อไป: แสดง applicationKey ทีละกุญแจ — คัดลอกไปใส่ตามที่บอก แล้วกด Enter เพื่อล้างจอ',
  )
  for (const k of created) {
    await waitEnter(`\nกด Enter เพื่อแสดง applicationKey ของ ${k.keyName}`)
    console.log(
      `\n${k.keyName}\n  keyID          ${k.id}\n  applicationKey ${k.secret}\n  ใส่ที่          ${k.use}`,
    )
    await waitEnter('\nคัดลอกแล้วกด Enter เพื่อล้างจอ')
    clearScreen()
    k.secret = ''
  }
  console.log('สรุป (ส่งให้ Claude ได้ — ไม่มีความลับ):')
  for (const k of created) {
    console.log(
      `  ${k.keyName}: keyID ${k.id} · ${k.capabilities.join(', ')}${k.namePrefix ? ` · prefix ${k.namePrefix}` : ''}`,
    )
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
