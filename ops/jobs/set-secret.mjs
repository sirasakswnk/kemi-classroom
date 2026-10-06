// ตั้งรหัสลับระหว่าง pg_cron (pg_net) กับ Edge Function `process-jobs` (P3-10, BUILD_PLAN 3 “รหัสลับที่ pg_cron ใช้”)
// - สุ่มรหัสใหม่ 32 ไบต์ → secret ของฟังก์ชัน JOBS_SECRET (supabase secrets set --env-file) และ Supabase Vault
//   (process_jobs_secret + process_jobs_url) ผ่าน supabase db query — ค่าอยู่ในไฟล์ชั่วคราวที่ลบทิ้งทันที ไม่พิมพ์ออกจอ
// - ตอนนี้ยอมเฉพาะโปรเจกต์ที่ผูกเป็น kemi-dev (ops/check-dev-db.mjs) — prod ทำในระยะ 7 พร้อมขออนุญาต
// - รันซ้ำได้ (หมุนรหัสใหม่) ระหว่างหมุน รอบ cron ที่ค้างอาจได้ 401 หนึ่งครั้งแล้วรอบถัดไปใช้รหัสใหม่
// ใช้: node ops/jobs/set-secret.mjs
import { spawnSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkLinkedProject, DEV_PROJECT } from '../check-dev-db.mjs'

const root = fileURLToPath(new URL('../..', import.meta.url))
const error = checkLinkedProject(join(root, 'supabase', '.temp'))
if (error) {
  console.error(`หยุด: ${error}`)
  process.exit(1)
}

const secret = randomBytes(32).toString('base64url')
const url = `https://${DEV_PROJECT.ref}.supabase.co/functions/v1/process-jobs`
const sqlString = (v) => `'${v.replaceAll("'", "''")}'`

// รันคำสั่ง supabase โดยไม่แสดงผลลัพธ์ (อาจมีค่าที่ตั้ง) — บอกแค่สำเร็จ/ล้มเหลว
function supabase(args) {
  const res = spawnSync(`npx supabase ${args.join(' ')}`, { cwd: root, shell: true, encoding: 'utf8' })
  return res.status === 0
}

const dir = mkdtempSync(join(tmpdir(), 'kemi-jobs-'))
try {
  const envFile = join(dir, 'jobs.env')
  writeFileSync(envFile, `JOBS_SECRET=${secret}\n`, { mode: 0o600 })
  if (!supabase(['secrets', 'set', '--env-file', `"${envFile}"`, '--project-ref', DEV_PROJECT.ref])) {
    throw new Error('ตั้ง secret ของฟังก์ชันไม่สำเร็จ (supabase secrets set)')
  }
  console.log('ตั้ง JOBS_SECRET ของ Edge Function แล้ว')

  const sqlFile = join(dir, 'vault.sql')
  writeFileSync(
    sqlFile,
    `do $$
declare
  v_id uuid;
begin
  select id into v_id from vault.secrets where name = 'process_jobs_secret';
  if v_id is null then
    perform vault.create_secret(${sqlString(secret)}, 'process_jobs_secret', 'process-jobs (P3-10)');
  else
    perform vault.update_secret(v_id, ${sqlString(secret)});
  end if;
  select id into v_id from vault.secrets where name = 'process_jobs_url';
  if v_id is null then
    perform vault.create_secret(${sqlString(url)}, 'process_jobs_url', 'process-jobs URL (P3-10)');
  else
    perform vault.update_secret(v_id, ${sqlString(url)});
  end if;
end
$$;
`,
    { mode: 0o600 },
  )
  if (!supabase(['db', 'query', '--linked', '-f', `"${sqlFile}"`, '--output-format', 'json'])) {
    throw new Error('ใส่ Vault ไม่สำเร็จ (supabase db query) — รันสคริปต์นี้ซ้ำได้')
  }
  console.log('ตั้ง process_jobs_secret และ process_jobs_url ใน Vault แล้ว (ไม่แสดงค่า)')
} catch (e) {
  console.error(`หยุด: ${e.message}`)
  process.exitCode = 1
} finally {
  rmSync(dir, { recursive: true, force: true })
}
