// POST /files/sign — ลิงก์เปิดดู/ดาวน์โหลดไฟล์ (P3-05; TECHNICAL_DESIGN 9.2, 9.3, 10)
//   1. RPC authorize_files ในนามผู้ใช้: คืนเฉพาะ id ที่เปิดได้ + นับเพดานครั้งต่อบัญชี — ได้ไม่ครบทุก id → forbidden
//      ทั้งชุด (ไม่บอกว่า id ไหนไม่มีสิทธิ์หรือไม่มีอยู่)
//   2. RPC files_sign_begin ด้วย service role: final_key/version_id/ชนิด/ขนาด/ชื่อ + ตรวจและนับงบเปิดดูของวัน
//      ในคำสั่งเดียว (ครบงบ → download_budget_reached ไม่ออกลิงก์) — ส่งเฉพาะ id ที่ข้อ 1 คืนมา
//   3. ลงลายเซ็น GET 600 วินาทีต่อไฟล์ ระบุ versionId + ชนิด + inline/attachment (ชื่อไทยแบบ filename*) + cache-control
//   การลงลายเซ็นคำนวณในฟังก์ชัน ไม่เรียก B2 (ไม่ใช้คำขอ Class B) — เบราว์เซอร์ใช้ลิงก์โหลดไฟล์จาก B2 ตรง
import {
  contentDisposition,
  GET_CACHE_CONTROL,
  GET_EXPIRES_SECONDS,
  presignGet,
} from '../_shared/b2.ts'
import { isUuid, readJson, serviceRpc, userRpc, type Ctx } from '../_shared/context.ts'
import { errorResponse, json } from '../_shared/http.ts'

/** ไฟล์โจทย์ 10 + เฉลย 10 ต่อคำขอ (ตรงกับ private.files_sign_limits() ใน 0018) */
export const MAX_FILES_PER_REQUEST = 20

export type SignMode = 'view' | 'download'

interface SignTarget {
  id: string
  final_key: string
  version_id: string
  content_type: string
  size_bytes: number
  file_name: string
}

/** ตรวจรูปร่างคำขอ: { asset_ids: uuid[1..20], mode } — id ซ้ำตัดออก (เทียบแบบตัวพิมพ์เล็ก) คงลำดับเดิม */
export function parseSignRequest(body: unknown): { ids: string[]; mode: SignMode } | null {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return null
  const b = body as Record<string, unknown>
  if (Object.keys(b).some((k) => k !== 'asset_ids' && k !== 'mode')) return null
  if (b.mode !== 'view' && b.mode !== 'download') return null
  if (!Array.isArray(b.asset_ids) || !b.asset_ids.every(isUuid)) return null
  const ids = [...new Set((b.asset_ids as string[]).map((id) => id.toLowerCase()))]
  if (ids.length < 1 || ids.length > MAX_FILES_PER_REQUEST) return null
  return { ids, mode: b.mode }
}

const sameIds = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((id, i) => id === b[i])

function isTargets(data: unknown, ids: readonly string[]): data is { files: SignTarget[] } {
  const files = (data as { files?: unknown } | null)?.files
  return (
    Array.isArray(files) &&
    files.every(
      (f: SignTarget) =>
        typeof f === 'object' &&
        f !== null &&
        isUuid(f.id) &&
        typeof f.final_key === 'string' &&
        typeof f.version_id === 'string' &&
        f.version_id !== '' &&
        typeof f.content_type === 'string' &&
        Number.isSafeInteger(f.size_bytes) &&
        typeof f.file_name === 'string',
    ) &&
    sameIds(
      files.map((f: SignTarget) => f.id.toLowerCase()),
      ids,
    )
  )
}

export async function signFiles(ctx: Ctx, req: Request): Promise<Response> {
  const { cors } = ctx
  const request = parseSignRequest(await readJson(req))
  if (!request) return errorResponse('invalid_request', cors)
  const { ids, mode } = request

  const allowed = await userRpc(ctx, 'authorize_files', { p_asset_ids: ids })
  if (!allowed.ok) return errorResponse(allowed.code, cors)
  if (!Array.isArray(allowed.data) || !allowed.data.every(isUuid)) {
    console.error('files: unexpected authorize_files result')
    return errorResponse('internal_error', cors)
  }
  // ต้องได้ครบทุก id ที่ขอ — ไม่ออกลิงก์บางส่วน
  const granted = new Set((allowed.data as string[]).map((id) => id.toLowerCase()))
  if (!ids.every((id) => granted.has(id))) return errorResponse('forbidden', cors)

  const begin = await serviceRpc(ctx, 'files_sign_begin', { p_asset_ids: ids })
  if (!begin.ok) return errorResponse(begin.code, cors)
  if (!isTargets(begin.data, ids)) {
    console.error('files: unexpected files_sign_begin result')
    return errorResponse('internal_error', cors)
  }

  const now = ctx.deps.now?.() ?? new Date()
  const disposition = mode === 'view' ? 'inline' : 'attachment'
  let files
  try {
    files = await Promise.all(
      begin.data.files.map(async (f) => ({
        asset_id: f.id,
        url: await presignGet(
          ctx.config,
          {
            key: f.final_key,
            versionId: f.version_id,
            contentType: f.content_type,
            disposition: contentDisposition(disposition, f.file_name),
            cacheControl: GET_CACHE_CONTROL,
          },
          { now },
        ),
        file_name: f.file_name,
        content_type: f.content_type,
        size_bytes: f.size_bytes,
      })),
    )
  } catch (e) {
    // key ผิดรูปแบบ (ไม่ใช่ files/{uuid}.{ext}) — ไม่ควรเกิด; งบที่นับไปแล้วไม่คืน (กันพลาดฝั่งปลอดภัย)
    console.error(`files: sign failed ${(e as Error).message}`)
    return errorResponse('internal_error', cors)
  }
  return json(
    {
      mode,
      expires_at: new Date(now.getTime() + GET_EXPIRES_SECONDS * 1000).toISOString(),
      files,
    },
    200,
    cors,
  )
}
