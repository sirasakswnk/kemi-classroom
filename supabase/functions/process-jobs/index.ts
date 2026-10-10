// Edge Function `process-jobs` — logic อยู่ใน handler.ts (ทดสอบด้วย Node: npm run functions:test)
// verify_jwt = false ใน config.toml: ตรวจรหัสลับ x-jobs-secret เอง (pg_cron + pg_net เรียก ไม่มี JWT ผู้ใช้)
// ตัวแปร: JOBS_SECRET, B2_KEY_ID, B2_APP_KEY, B2_BUCKET, B2_ENDPOINT (supabase secrets)
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY มีให้อัตโนมัติ
import { createHandler } from './handler.ts'

Deno.serve(
  createHandler({ env: (name) => Deno.env.get(name), fetch: (input, init) => fetch(input, init) }),
)
