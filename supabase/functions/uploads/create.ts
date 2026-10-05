// POST /uploads — ขอชุดอัปโหลด (P3-03)
//   1. RPC create_upload_batch ในนามผู้ใช้: ตรวจสิทธิ์ วัตถุประสงค์ ภาคเรียน J4–J6 เพดานครั้ง request key
//      แล้วจองพื้นที่ + สร้าง batch ใน transaction เดียว (0016_upload_batch)
//   2. ลงลายเซ็น PUT ต่อไฟล์ใต้ staging/{batch_id}/{uuid} อายุ 5 นาที พร้อม content-type และ content-length
//   กดซ้ำด้วย request key เดิมได้ batch เดิมและลิงก์ใหม่ (ใช้ตอนลิงก์หมดอายุก่อนอัปโหลดเสร็จ)
import { isStagingKeyOf, presignPut, PUT_EXPIRES_SECONDS } from '../_shared/b2.ts'
import { errorResponse, json } from '../_shared/http.ts'
import { isUuid, readJson, userRpc, type Ctx } from '../_shared/context.ts'

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

export async function createBatch(ctx: Ctx, req: Request): Promise<Response> {
  const { cors } = ctx
  const args = parseRequest(await readJson(req))
  if (!args) return errorResponse('invalid_request', cors)

  const result = await userRpc(ctx, 'create_upload_batch', args)
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
  const now = ctx.deps.now?.()
  const files = await Promise.all(
    batch.files.map(async (f) => ({
      staging_key: f.staging_key,
      file_name: f.file_name,
      content_type: f.content_type,
      size_bytes: f.size_bytes,
      upload_url: await presignPut(
        ctx.config,
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
