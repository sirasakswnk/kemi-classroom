// เรียก Edge Function `uploads` และ PUT ตรงเข้า B2 — TECHNICAL_DESIGN 9, 10; BUILD_PLAN 5 (uploads)
//   POST /uploads                     ขอชุดอัปโหลด (จองพื้นที่ + ลิงก์ PUT อายุ 5 นาทีต่อไฟล์) — request key เดิมได้ batch เดิม/ลิงก์ใหม่
//   PUT <upload_url>                  เบราว์เซอร์ส่งไฟล์ตรงเข้า B2 (ลายเซ็นผูก content-type และขนาด)
//   POST /uploads/:batch_id/complete  ตรวจไฟล์ที่ขึ้นไปจริงแล้วย้ายเป็นไฟล์จริง → asset_id
import { functionError, isCapExceeded } from '../../lib/files'
import { RequestError } from '../../lib/request'
import { supabase, toAppError } from '../../lib/supabase'
import { z } from '../../lib/zod'
import type { UploadType } from './rules'

export type UploadPurpose = 'post' | 'solution' | 'submission'

export interface BatchRequest {
  purpose: UploadPurpose
  classroomId: string
  postId: string | null
  files: { name: string; type: UploadType; size: number }[]
  requestKey: string
  adminMode: boolean
}

const batchSchema = z.object({
  batch_id: z.string(),
  expires_at: z.string(),
  files: z.array(
    z.object({
      file_name: z.string(),
      content_type: z.string(),
      size_bytes: z.number().int(),
      upload_url: z.string().url(),
    }),
  ),
})
export type Batch = z.infer<typeof batchSchema>

const completeSchema = z.object({
  asset_id: z.string(),
  file_name: z.string(),
  content_type: z.string(),
  size_bytes: z.number().int(),
})
export type Completed = z.infer<typeof completeSchema>

async function invoke<T>(
  name: string,
  body: Record<string, unknown>,
  schema: z.ZodType<T>,
): Promise<T> {
  let result: { data: unknown; error: unknown }
  try {
    result = await supabase.functions.invoke(name, { body })
  } catch (error) {
    throw new RequestError(toAppError(error))
  }
  if (result.error) throw new RequestError(await functionError(result.error))
  const parsed = schema.safeParse(result.data)
  if (!parsed.success) throw new RequestError(toAppError({ name: 'InvalidResponse' }))
  return parsed.data
}

export function requestBatch(req: BatchRequest): Promise<Batch> {
  return invoke(
    'uploads',
    {
      purpose: req.purpose,
      classroom_id: req.classroomId,
      post_id: req.postId,
      files: req.files.map((f) => ({
        file_name: f.name,
        content_type: f.type,
        size_bytes: f.size,
      })),
      request_key: req.requestKey,
      admin_mode: req.adminMode,
    },
    batchSchema,
  )
}

export function completeUpload(batchId: string, item: number): Promise<Completed> {
  return invoke(`uploads/${batchId}/complete`, { item }, completeSchema)
}

/** PUT ไม่สำเร็จ — kind บอกว่าผู้เรียกควรทำอะไรต่อ */
export class PutError extends Error {
  /**
   * expired: 403 อื่นที่ไม่ใช่เพดาน (ลิงก์หมดอายุ 5 นาที) → ขอ batch ซ้ำด้วย request key เดิมแล้วลองใหม่
   * cap: B2 ปฏิเสธเพราะเกินเพดาน · network: เน็ตหลุด · aborted: ผู้ใช้ยกเลิก · failed: อื่น ๆ
   */
  readonly kind: 'expired' | 'cap' | 'network' | 'aborted' | 'failed'
  readonly status: number
  constructor(kind: PutError['kind'], status = 0) {
    super(`put_${kind}`)
    this.kind = kind
    this.status = status
  }
}

/**
 * ส่งไฟล์ด้วย XHR เพื่อรายงานความคืบหน้า (fetch ยังรายงานการส่งไม่ได้) — content-type ต้องตรงลายเซ็น
 * ขนาด (content-length) เบราว์เซอร์ใส่จาก Blob เอง จึงต้องเป็นไฟล์ชิ้นเดียวกับที่แจ้งขนาดตอนขอ batch
 */
export function putFile(
  url: string,
  blob: Blob,
  contentType: UploadType,
  onProgress: (loaded: number, total: number) => void,
  signal?: AbortSignal,
): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new PutError('aborted'))
    const xhr = new XMLHttpRequest()
    const onAbort = () => xhr.abort()
    signal?.addEventListener('abort', onAbort, { once: true })
    const finish = (fn: () => void) => {
      signal?.removeEventListener('abort', onAbort)
      fn()
    }
    xhr.open('PUT', url)
    xhr.setRequestHeader('Content-Type', contentType)
    xhr.upload.onprogress = (e) => onProgress(e.loaded, e.lengthComputable ? e.total : blob.size)
    xhr.onload = () =>
      finish(() => {
        if (xhr.status >= 200 && xhr.status < 300) {
          onProgress(blob.size, blob.size)
          return resolve()
        }
        const body = typeof xhr.responseText === 'string' ? xhr.responseText : ''
        if (isCapExceeded(xhr.status, body)) return reject(new PutError('cap', xhr.status))
        reject(new PutError(xhr.status === 403 ? 'expired' : 'failed', xhr.status))
      })
    xhr.onerror = () =>
      finish(() => {
        // คำตอบ error ของ B2 (เช่น 403 จากกุญแจที่ถูกลบ) ไม่มี header CORS เบราว์เซอร์จึงเห็นเป็นเน็ตหลุด
        // จดไว้ให้ผู้พัฒนาเห็นสาเหตุที่เป็นไปได้ (ops/b2/README.md ขั้น 4) — build จริงไม่จด
        if (import.meta.env.DEV)
          console.warn(
            `PUT ไป B2 ล้มแบบ network: B2 อาจปฏิเสธ (คำตอบ error ของ B2 ไม่มี header CORS) — ตรวจ B2_KEY_ID/B2_APP_KEY ใน secrets`,
          )
        reject(new PutError('network'))
      })
    xhr.onabort = () => finish(() => reject(new PutError('aborted')))
    xhr.send(blob)
  })
}
