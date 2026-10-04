// POST /uploads — ขอชุดอัปโหลด (TECHNICAL_DESIGN 9, 10; TECHNICAL_BUILD_PLAN 5)
//   1. RPC create_upload_batch ในนามผู้ใช้: ตรวจสิทธิ์ วัตถุประสงค์ ภาคเรียน J4–J6 เพดานครั้ง request key
//      แล้วจองพื้นที่ + สร้าง batch ใน transaction เดียว (0016_upload_batch)
//   2. ลงลายเซ็น PUT ต่อไฟล์ใต้ staging/{batch_id}/{uuid} อายุ 5 นาที พร้อม content-type และ content-length
//   กดซ้ำด้วย request key เดิมได้ batch เดิมและลิงก์ใหม่ (ใช้ตอนลิงก์หมดอายุก่อนอัปโหลดเสร็จ)
//   /uploads/:id/complete มากับ P3-04
// แยกจาก index.ts เพื่อให้ทดสอบด้วย Node ได้ (ไม่มี Deno ในไฟล์นี้)
import {
  b2ConfigFrom,
  isStagingKeyOf,
  presignPut,
  PUT_EXPIRES_SECONDS,
  type B2Config,
} from '../_shared/b2.ts'
import { corsHeaders, errorResponse, json, webOrigins } from '../_shared/http.ts'
import { callRpc } from '../_shared/rpc.ts'

export interface Deps {
  env: (name: string) => string | undefined
  fetch: typeof fetch
  now?: () => Date
}

interface BatchFile {
  staging_key: string
  file_name: string
  content_type: string
  size_bytes: number
}

interface Batch {
  batch_id: string
  purpose: string
  expires_at: string
  reserved_bytes: number
  files: BatchFile[]
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_BODY_BYTES = 16384

const isUuid = (v: unknown): v is string => typeof v === 'string' && UUID.test(v)

/** ตรวจรูปร่างคำขอเท่านั้น กติกาจริงอยู่ใน RPC */
function parseRequest(body: unknown): Record<string, unknown> | null {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return null
  const b = body as Record<string, unknown>
  const known = ['purpose', 'classroom_id', 'post_id', 'files', 'request_key', 'admin_mode']
  if (Object.keys(b).some((k) => !known.includes(k))) return null
  if (typeof b.purpose !== 'string' || !isUuid(b.classroom_id) || !isUuid(b.request_key))
    return null
  if (b.post_id !== undefined && b.post_id !== null && !isUuid(b.post_id)) return null
  if (!Array.isArray(b.files)) return null
  if (b.admin_mode !== undefined && typeof b.admin_mode !== 'boolean') return null
  return {
    p_purpose: b.purpose,
    p_classroom_id: b.classroom_id,
    p_post_id: b.post_id ?? null,
    p_files: b.files,
    p_request_key: b.request_key,
    p_admin_mode: b.admin_mode ?? false,
  }
}

function isBatch(data: unknown): data is Batch {
  const d = data as Batch
  return (
    typeof d === 'object' &&
    d !== null &&
    isUuid(d.batch_id) &&
    Array.isArray(d.files) &&
    d.files.every(
      (f) =>
        typeof f?.staging_key === 'string' &&
        typeof f.content_type === 'string' &&
        Number.isSafeInteger(f.size_bytes),
    )
  )
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    const cors = corsHeaders(req, webOrigins(deps.env('WEB_ORIGINS')))
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    const path = new URL(req.url).pathname
    if (!/\/uploads\/?$/.test(path)) return errorResponse('not_found', cors)
    if (req.method !== 'POST') return errorResponse('not_found', cors)

    const authorization = req.headers.get('authorization') ?? ''
    if (!/^Bearer \S+$/.test(authorization)) return errorResponse('not_authenticated', cors)

    // ค่าตั้งต้องครบก่อนเรียก RPC — ไม่จองพื้นที่ถ้าลงลายเซ็นไม่ได้ (log แค่ชื่อตัวแปร ไม่ log ค่า)
    let config: B2Config
    const supabaseUrl = deps.env('SUPABASE_URL')
    try {
      if (!supabaseUrl) throw new Error('config_missing:SUPABASE_URL')
      config = b2ConfigFrom(deps.env)
    } catch (e) {
      console.error(`uploads misconfigured: ${(e as Error).message}`)
      return errorResponse('internal_error', cors)
    }
    const apikey = req.headers.get('apikey') ?? deps.env('SUPABASE_ANON_KEY') ?? ''

    const text = await req.text()
    if (text.length > MAX_BODY_BYTES) return errorResponse('invalid_request', cors)
    let args: Record<string, unknown> | null = null
    try {
      args = parseRequest(JSON.parse(text))
    } catch {
      args = null
    }
    if (!args) return errorResponse('invalid_request', cors)

    const result = await callRpc({
      fetch: deps.fetch,
      supabaseUrl,
      apikey,
      authorization,
      fn: 'create_upload_batch',
      args,
    })
    if (!result.ok) return errorResponse(result.code, cors)
    if (!isBatch(result.data)) {
      console.error('uploads: unexpected rpc result')
      return errorResponse('internal_error', cors)
    }
    const batch = result.data
    // กันพลาด: ลงลายเซ็นเฉพาะ key ใต้ staging/ ของ batch นี้
    if (!batch.files.every((f) => isStagingKeyOf(f.staging_key, batch.batch_id))) {
      console.error('uploads: staging key outside batch')
      return errorResponse('internal_error', cors)
    }
    const now = deps.now?.()
    const files = await Promise.all(
      batch.files.map(async (f) => ({
        staging_key: f.staging_key,
        file_name: f.file_name,
        content_type: f.content_type,
        size_bytes: f.size_bytes,
        upload_url: await presignPut(
          config,
          { key: f.staging_key, contentType: f.content_type, sizeBytes: f.size_bytes },
          now,
        ),
      })),
    )
    return json(
      {
        batch_id: batch.batch_id,
        purpose: batch.purpose,
        expires_at: batch.expires_at,
        reserved_bytes: batch.reserved_bytes,
        url_expires_in: PUT_EXPIRES_SECONDS,
        files,
      },
      200,
      cors,
    )
  }
}
