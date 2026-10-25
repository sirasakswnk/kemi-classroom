// POST /files/exports — ลิงก์ดาวน์โหลดไฟล์ของภาคเรียนเก่าทีละหน้า (P6-05a3; TECHNICAL_DESIGN 10, 12; SYSTEM_SPEC J9.2)
//   1. RPC export_files_page ในนามผู้ใช้: ครู (หรือผู้ดูแลในโหมดผู้ดูแล) + ภาคเรียนที่กดจบ/มีภาคเรียนใหม่ทับแล้วเท่านั้น
//      (ภาคเรียนที่ยังเปิด/ไม่มี = invalid_request) + เพดานหน้าต่อบัญชี → ไฟล์หน้านี้ (≤ 20) เรียงตาม asset_id
//      + fingerprint/จำนวน/ไบต์ของทั้งชุด + next_after
//   2. RPC files_sign_begin ด้วย service role: นับงบเปิดดูของวันแบบเดียวกับ /files/sign (ไฟล์ละ 1 คำขอ + ขนาดเต็ม)
//      งบไม่พอ → export_budget_reached ทั้งหน้า ไม่นับงบ ไม่ออกลิงก์ — หน้าเว็บเก็บ after เดิมไว้แล้วขอหน้าเดิมอีกครั้ง
//      หลัง 07:00 น. (รอบวัน UTC ใหม่) จึงดาวน์โหลดต่อจากที่ค้างได้ ไม่ต้องเริ่มใหม่
//      ไฟล์หน้านี้ถูกลบ/ไม่ ready ระหว่างขั้น 1–2 (forbidden) → export_mismatch (ชุดเปลี่ยนระหว่างดาวน์โหลด)
//   3. ลงลายเซ็น GET 600 วินาทีต่อไฟล์แบบ attachment (ไม่เรียก B2) — คำตอบไม่มี key/เวอร์ชันแยก (อยู่ในลิงก์เท่านั้น)
//   log: เฉพาะชื่อขั้นที่ล้ม — ไม่เขียน key ของ B2 ชื่อไฟล์ หรือชื่อ/รหัสนักเรียน
import {
  contentDisposition,
  GET_CACHE_CONTROL,
  GET_EXPIRES_SECONDS,
  presignGet,
} from '../_shared/b2.ts'
import { isUuid, readJson, serviceRpc, userRpc, type Ctx } from '../_shared/context.ts'
import { errorResponse, json } from '../_shared/http.ts'
import { MAX_FILES_PER_REQUEST } from './sign.ts'

export interface ExportRequest {
  termId: string
  after: string | null
  limit: number
  adminMode: boolean
}

/** { term_id, after?: uuid | null, limit?: 1..20, admin_mode?: boolean } — คีย์อื่นไม่รับ */
export function parseExportRequest(body: unknown): ExportRequest | null {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return null
  const b = body as Record<string, unknown>
  const keys = ['term_id', 'after', 'limit', 'admin_mode']
  if (Object.keys(b).some((k) => !keys.includes(k))) return null
  if (!isUuid(b.term_id)) return null
  if (b.after !== undefined && b.after !== null && !isUuid(b.after)) return null
  const limit = b.limit ?? MAX_FILES_PER_REQUEST
  if (
    !Number.isInteger(limit) ||
    (limit as number) < 1 ||
    (limit as number) > MAX_FILES_PER_REQUEST
  ) {
    return null
  }
  if (b.admin_mode !== undefined && typeof b.admin_mode !== 'boolean') return null
  return {
    termId: b.term_id.toLowerCase(),
    after: typeof b.after === 'string' ? b.after.toLowerCase() : null,
    limit: limit as number,
    adminMode: b.admin_mode === true,
  }
}

/** แถวไฟล์จาก export_files_page — ตรวจเฉพาะช่องที่ฟังก์ชันใช้ ที่เหลือ (ห้อง งาน นักเรียน) ส่งต่อตามที่ฐานข้อมูลคืน */
interface PageFile {
  asset_id: string
  file_name: string
  content_type: string
  size_bytes: number
  [meta: string]: unknown
}

interface Page {
  term_id: string
  fingerprint: string
  total_count: number
  total_bytes: number
  next_after: string | null
  files: PageFile[]
}

function isPage(data: unknown, limit: number): data is Page {
  const p = data as Partial<Page> | null
  return (
    typeof p === 'object' &&
    p !== null &&
    isUuid(p.term_id) &&
    typeof p.fingerprint === 'string' &&
    Number.isSafeInteger(p.total_count) &&
    Number.isSafeInteger(p.total_bytes) &&
    (p.next_after === null || isUuid(p.next_after)) &&
    Array.isArray(p.files) &&
    p.files.length <= limit &&
    p.files.every(
      (f: PageFile) =>
        typeof f === 'object' &&
        f !== null &&
        isUuid(f.asset_id) &&
        typeof f.file_name === 'string' &&
        typeof f.content_type === 'string' &&
        Number.isSafeInteger(f.size_bytes),
    ) &&
    new Set(p.files.map((f: PageFile) => f.asset_id.toLowerCase())).size === p.files.length
  )
}

interface SignTarget {
  id: string
  final_key: string
  version_id: string
  content_type: string
  size_bytes: number
}

/** files_sign_begin คืนครบทุก id ตามลำดับ และชนิด/ขนาดตรงกับหน้า (อ่านจากแถว assets เดียวกัน) */
function isTargets(data: unknown, files: readonly PageFile[]): data is { files: SignTarget[] } {
  const targets = (data as { files?: unknown } | null)?.files
  return (
    Array.isArray(targets) &&
    targets.length === files.length &&
    targets.every(
      (t: SignTarget, i) =>
        typeof t === 'object' &&
        t !== null &&
        isUuid(t.id) &&
        t.id.toLowerCase() === files[i].asset_id.toLowerCase() &&
        typeof t.final_key === 'string' &&
        typeof t.version_id === 'string' &&
        t.version_id !== '' &&
        t.content_type === files[i].content_type &&
        t.size_bytes === files[i].size_bytes,
    )
  )
}

export async function exportFiles(ctx: Ctx, req: Request): Promise<Response> {
  const { cors } = ctx
  const request = parseExportRequest(await readJson(req))
  if (!request) return errorResponse('invalid_request', cors)

  const page = await userRpc(ctx, 'export_files_page', {
    p_term_id: request.termId,
    p_after: request.after,
    p_limit: request.limit,
    p_admin_mode: request.adminMode,
  })
  if (!page.ok) return errorResponse(page.code, cors)
  if (!isPage(page.data, request.limit)) {
    console.error('exports: unexpected export_files_page result')
    return errorResponse('internal_error', cors)
  }
  const { files, ...set } = page.data
  const now = ctx.deps.now?.() ?? new Date()
  const expiresAt = new Date(now.getTime() + GET_EXPIRES_SECONDS * 1000).toISOString()
  // หน้าว่าง (ภาคเรียนไม่มีไฟล์ หรือ after เลยไฟล์สุดท้ายแล้ว) — ไม่เรียก files_sign_begin ไม่นับงบ
  if (files.length === 0) return json({ ...set, expires_at: expiresAt, files: [] }, 200, cors)

  const begin = await serviceRpc(ctx, 'files_sign_begin', {
    p_asset_ids: files.map((f) => f.asset_id),
  })
  if (!begin.ok) {
    if (begin.code === 'download_budget_reached')
      return errorResponse('export_budget_reached', cors)
    if (begin.code === 'forbidden') return errorResponse('export_mismatch', cors)
    return errorResponse(begin.code, cors)
  }
  if (!isTargets(begin.data, files)) {
    console.error('exports: unexpected files_sign_begin result')
    return errorResponse('internal_error', cors)
  }

  let signed
  try {
    signed = await Promise.all(
      begin.data.files.map(async (t, i) => ({
        ...files[i],
        url: await presignGet(
          ctx.config,
          {
            key: t.final_key,
            versionId: t.version_id,
            contentType: t.content_type,
            disposition: contentDisposition('attachment', files[i].file_name),
            cacheControl: GET_CACHE_CONTROL,
          },
          { now },
        ),
      })),
    )
  } catch (e) {
    // key ผิดรูปแบบ — ไม่ควรเกิด; ข้อความจาก b2.ts เป็นรหัสคงที่ ไม่มี key; งบที่นับไปแล้วไม่คืน (ฝั่งปลอดภัย)
    console.error(`exports: sign failed ${(e as Error).message}`)
    return errorResponse('internal_error', cors)
  }
  return json({ ...set, expires_at: expiresAt, files: signed }, 200, cors)
}
