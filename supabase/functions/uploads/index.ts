// Edge Function `uploads` — logic อยู่ใน handler.ts (ทดสอบด้วย Node: npm run functions:test)
// verify_jwt = false ใน config.toml: ฟังก์ชันส่ง JWT ของผู้ใช้ต่อให้ PostgREST ตรวจเอง (RPC ตรวจสิทธิ์ทุกครั้ง)
// ตัวแปร: B2_KEY_ID, B2_APP_KEY, B2_BUCKET, B2_ENDPOINT (supabase secrets), WEB_ORIGINS ไม่บังคับ
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY มีให้อัตโนมัติ (service role ใช้เฉพาะ RPC ขั้น complete)
import { createHandler } from './handler.ts'

Deno.serve(
  createHandler({ env: (name) => Deno.env.get(name), fetch: (input, init) => fetch(input, init) }),
)
