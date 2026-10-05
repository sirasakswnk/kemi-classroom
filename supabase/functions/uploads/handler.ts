// Edge Function `uploads` (TECHNICAL_DESIGN 9, 10; TECHNICAL_BUILD_PLAN 5)
//   POST /uploads                        ขอชุดอัปโหลด + ลิงก์ PUT ต่อไฟล์ (create.ts, P3-03)
//   POST /uploads/:batch_id/complete     ย้ายไฟล์พักเป็นไฟล์จริง (complete.ts, P3-04)
// แยกจาก index.ts เพื่อให้ทดสอบด้วย Node ได้ (ไม่มี Deno ในไฟล์นี้)
import { b2ConfigFrom, type B2Config } from '../_shared/b2.ts'
import { corsHeaders, errorResponse, webOrigins } from '../_shared/http.ts'
import { completeItem } from './complete.ts'
import type { Ctx, Deps } from '../_shared/context.ts'
import { createBatch } from './create.ts'

export type { Deps } from '../_shared/context.ts'

type Route = { kind: 'create' } | { kind: 'complete'; batchId: string }

function route(req: Request): Route | null {
  if (req.method !== 'POST') return null
  const path = new URL(req.url).pathname
  if (/\/uploads\/?$/.test(path)) return { kind: 'create' }
  const match =
    /\/uploads\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/complete\/?$/i.exec(
      path,
    )
  return match ? { kind: 'complete', batchId: match[1].toLowerCase() } : null
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const cors = corsHeaders(req, webOrigins(deps.env('WEB_ORIGINS')))
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    const target = route(req)
    if (!target) return errorResponse('not_found', cors)

    const authorization = req.headers.get('authorization') ?? ''
    if (!/^Bearer \S+$/.test(authorization)) return errorResponse('not_authenticated', cors)

    // ค่าตั้งต้องครบก่อนเรียก RPC — ไม่จองพื้นที่/ไม่อ่าน B2 ถ้าทำต่อไม่ได้ (log แค่ชื่อตัวแปร ไม่ log ค่า)
    let config: B2Config
    const supabaseUrl = deps.env('SUPABASE_URL')
    const serviceKey = deps.env('SUPABASE_SERVICE_ROLE_KEY')?.trim() || null
    try {
      if (!supabaseUrl) throw new Error('config_missing:SUPABASE_URL')
      if (target.kind === 'complete' && !serviceKey) {
        throw new Error('config_missing:SUPABASE_SERVICE_ROLE_KEY')
      }
      config = b2ConfigFrom(deps.env)
    } catch (e) {
      console.error(`uploads misconfigured: ${(e as Error).message}`)
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
    return target.kind === 'create' ? createBatch(ctx, req) : completeItem(ctx, req, target.batchId)
  }
}
