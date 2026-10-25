// Edge Function `files` (TECHNICAL_DESIGN 9.2, 9.3, 10; TECHNICAL_BUILD_PLAN 5)
//   POST /files/sign     ลิงก์เปิดดู/ดาวน์โหลดไฟล์ (sign.ts, P3-05)
//   POST /files/exports  ลิงก์ดาวน์โหลดไฟล์ภาคเรียนเก่าทีละหน้า (exports.ts, P6-05a3)
// แยกจาก index.ts เพื่อให้ทดสอบด้วย Node ได้ (ไม่มี Deno ในไฟล์นี้)
import { b2ConfigFrom, type B2Config } from '../_shared/b2.ts'
import type { Ctx, Deps } from '../_shared/context.ts'
import { corsHeaders, errorResponse, webOrigins } from '../_shared/http.ts'
import { exportFiles } from './exports.ts'
import { signFiles } from './sign.ts'

export type { Deps } from '../_shared/context.ts'

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const cors = corsHeaders(req, webOrigins(deps.env('WEB_ORIGINS')))
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    const route = /\/files\/(sign|exports)\/?$/.exec(new URL(req.url).pathname)?.[1]
    if (req.method !== 'POST' || !route) return errorResponse('not_found', cors)

    const authorization = req.headers.get('authorization') ?? ''
    if (!/^Bearer \S+$/.test(authorization)) return errorResponse('not_authenticated', cors)

    // ค่าตั้งต้องครบก่อนเรียก RPC — ไม่นับเพดาน/งบถ้าออกลิงก์ไม่ได้ (log แค่ชื่อตัวแปร ไม่ log ค่า)
    let config: B2Config
    const supabaseUrl = deps.env('SUPABASE_URL')
    const serviceKey = deps.env('SUPABASE_SERVICE_ROLE_KEY')?.trim() || null
    try {
      if (!supabaseUrl) throw new Error('config_missing:SUPABASE_URL')
      if (!serviceKey) throw new Error('config_missing:SUPABASE_SERVICE_ROLE_KEY')
      config = b2ConfigFrom(deps.env)
    } catch (e) {
      console.error(`files misconfigured: ${(e as Error).message}`)
      return errorResponse('internal_error', cors)
    }
    const ctx: Ctx = {
      deps,
      cors,
      config,
      supabaseUrl,
      apikey: req.headers.get('apikey') ?? deps.env('SUPABASE_ANON_KEY') ?? '',
      authorization,
      serviceKey,
    }
    return route === 'exports' ? exportFiles(ctx, req) : signFiles(ctx, req)
  }
}
