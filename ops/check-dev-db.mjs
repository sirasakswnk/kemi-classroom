// ตัวกันก่อนรัน pgTAP กับฐานข้อมูลนอกเครื่อง (TECHNICAL_BUILD_PLAN 8): ห้ามรันกับ prod เด็ดขาด
// บางเทสต์แก้แถวจริงชั่วคราวใน transaction ที่ย้อนกลับ (เช่นเทสต์ครูคนสุดท้าย) จึงยอมเฉพาะ kemi-dev
// อ่านโปรเจกต์ที่ `supabase link` ผูกไว้ (supabase/.temp) — ต้องเป็น ref และชื่อของ kemi-dev ทั้งคู่
// ใช้: node ops/check-dev-db.mjs [โฟลเดอร์ .temp]   (ไม่ใส่ = supabase/.temp ของ repo)
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const DEV_PROJECT = { ref: 'igchlnmxbghsigyziomk', name: 'kemi-dev' }

/** คืนข้อความผิดพลาด (ภาษาไทย) หรือ null เมื่อผูกกับโปรเจกต์ที่ต้องการ (ค่าเริ่มต้น kemi-dev) */
export function checkLinkedProject(tempDir, expected = DEV_PROJECT) {
  let ref = ''
  let name = ''
  try {
    ref = readFileSync(join(tempDir, 'project-ref'), 'utf8').trim()
  } catch {
    return `ยังไม่ได้ผูกโปรเจกต์ (ไม่มี supabase/.temp/project-ref) — รัน npx supabase link --project-ref ของ ${expected.name} ก่อน`
  }
  try {
    name = JSON.parse(readFileSync(join(tempDir, 'linked-project.json'), 'utf8')).name ?? ''
  } catch {
    name = ''
  }
  if (ref !== expected.ref || (name && name !== expected.name)) {
    return `โปรเจกต์ที่ผูกอยู่ไม่ใช่ ${expected.name} (ref ${ref || '-'}${name ? `, ชื่อ ${name}` : ''}) — ห้ามรัน pgTAP กับฐานข้อมูลนี้`
  }
  return null
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const tempDir =
    process.argv[2] ?? join(fileURLToPath(new URL('..', import.meta.url)), 'supabase', '.temp')
  const error = checkLinkedProject(tempDir)
  if (error) {
    console.error(`หยุด: ${error}`)
    process.exit(1)
  }
  console.log(`ตรวจแล้ว: ผูกกับ ${DEV_PROJECT.name} (${DEV_PROJECT.ref})`)
}
