// POST /uploads/:batch_id/complete  { item } — ย้ายไฟล์พักเป็นไฟล์จริง (P3-04; TECHNICAL_DESIGN 9 ข้อ 2–4, 9.3)
//   1. upload_complete_target (JWT ของผู้ใช้): เป็นเจ้าของ batch ไหม + staging key/ชนิด/ขนาดที่ประกาศจากแถว batch
//      (หน้าเว็บส่งแค่ batch id + ลำดับไฟล์) — ไฟล์นี้ complete แล้วตอบผลเดิมโดยไม่เรียก B2
//   2. GET แบบ Range 0–15 ครั้งเดียว: เวอร์ชันจาก x-amz-version-id, ขนาดเต็มจาก Content-Range, ชนิดจาก magic number
//   3. upload_complete_begin (service_role): นับคำขอ ตรวจขนาด/ชนิดเทียบที่ประกาศ แล้วสร้าง asset สถานะ copying
//   4. CopyObject ระบุ versionId ต้นทาง + REPLACE + ชนิดที่ตรวจแล้ว → files/{asset_id}.{ext}
//   5. upload_complete_finish (service_role): version_id ปลายทาง + ETag → ready
//   6. ลบไฟล์พักแบบระบุเวอร์ชันที่ตรวจ (Class A ไม่นับเพดาน; ลบไม่สำเร็จ lifecycle ของ staging/ ล้างให้)
// เกินเพดาน B2 (GET หรือ CopyObject ได้ 403 cap exceeded) → download_budget_reached
// CopyObject ถูกปฏิเสธแน่นอน (4xx) → ลบแถว copying ให้เรียก complete ใหม่ได้; ผลไม่แน่นอน (5xx, หมดเวลา, 200 ที่มี
// <Error>) → ปล่อยแถว copying ให้ sweeper (P3-10) ตรวจปลายทางหลัง 15 นาที — ระหว่างนั้นเรียกซ้ำได้ upload_in_progress
import {
  copyObjectRequest,
  deleteVersionRequest,
  isCapExceeded,
  isStagingKeyOf,
  parseCopyResult,
  rangeGetRequest,
  readRange,
} from '../_shared/b2.ts'
import { detectType } from '../_shared/filetype.ts'
import { errorResponse, json } from '../_shared/http.ts'
import { isUuid, readJson, serviceRpc, userRpc, type Ctx } from './context.ts'

interface Target {
  account_id: string
  batch_id: string
  item: number
  staging_key: string
  file_name: string
  content_type: string
  size_bytes: number
  asset: { id: string; status: 'copying' | 'ready' | 'deleting' } | null
}

type Begin =
  | { code: string }
  | { asset_id: string; status: 'copying' | 'ready' | 'deleting'; existing: true }
  | { asset_id: string; final_key: string; content_type: string; status: 'copying' }

function parseItem(body: unknown): number | null {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return null
  const b = body as Record<string, unknown>
  if (Object.keys(b).some((k) => k !== 'item')) return null
  return Number.isInteger(b.item) && (b.item as number) >= 1 && (b.item as number) <= 10
    ? (b.item as number)
    : null
}

function isTarget(d: unknown, batchId: string): d is Target {
  const t = d as Target
  return (
    typeof t === 'object' &&
    t !== null &&
    isUuid(t.account_id) &&
    isStagingKeyOf(t.staging_key, batchId) &&
    typeof t.content_type === 'string' &&
    Number.isSafeInteger(t.size_bytes)
  )
}

export async function completeItem(ctx: Ctx, req: Request, batchId: string): Promise<Response> {
  const { cors, config, deps } = ctx
  const item = parseItem(await readJson(req))
  if (item === null) return errorResponse('invalid_request', cors)

  // ผลสำเร็จ (ครั้งแรกหรือเรียกซ้ำ) ใช้รูปเดียวกัน
  const done = (t: Target, assetId: string) =>
    json(
      {
        batch_id: batchId,
        item,
        asset_id: assetId,
        file_name: t.file_name,
        content_type: t.content_type,
        size_bytes: t.size_bytes,
        status: 'ready',
      },
      200,
      cors,
    )
  const fromExisting = (t: Target, asset: { id: string; status: string }) =>
    asset.status === 'ready'
      ? done(t, asset.id)
      : errorResponse(asset.status === 'copying' ? 'upload_in_progress' : 'upload_failed', cors)
  // นับคำขอ GET ที่ไม่ผ่านถึงขั้น begin — นับไม่สำเร็จไม่ทำให้คำตอบเปลี่ยน
  const countFailedGet = async () => {
    const r = await serviceRpc(ctx, 'record_b2_usage', {
      p_source: 'complete',
      p_requests: 1,
      p_bytes: 0,
    })
    if (!r.ok) console.error(`complete: usage not recorded (${r.code})`)
  }
  const deleteStaging = async (key: string, versionId: string) => {
    try {
      const res = await deps.fetch(await deleteVersionRequest(config, key, versionId))
      await res.body?.cancel()
      if (res.status !== 204 && res.status !== 200)
        console.error(`complete: staging delete ${res.status}`)
    } catch {
      console.error('complete: staging delete failed')
    }
  }

  // 1. เจ้าของ batch (JWT ของผู้ใช้)
  const t = await userRpc(ctx, 'upload_complete_target', { p_batch_id: batchId, p_item: item })
  if (!t.ok) return errorResponse(t.code, cors)
  if (!isTarget(t.data, batchId)) {
    console.error('complete: unexpected target')
    return errorResponse('internal_error', cors)
  }
  const target = t.data
  if (target.asset) return fromExisting(target, target.asset)

  // 2. GET แบบ Range ครั้งเดียว
  let got: Response
  try {
    got = await deps.fetch(await rangeGetRequest(config, target.staging_key))
  } catch {
    console.error('complete: range get failed (network)')
    return errorResponse('upload_failed', cors)
  }
  if (got.status === 404) {
    await got.body?.cancel()
    await countFailedGet()
    return errorResponse('upload_not_found', cors)
  }
  if (got.status === 403) {
    const text = await got.text()
    if (isCapExceeded(403, text)) return errorResponse('download_budget_reached', cors)
    console.error('complete: range get 403')
    return errorResponse('upload_failed', cors)
  }
  if (got.status === 416) {
    // ไฟล์ว่าง (ประกาศขนาด ≥ 1 เสมอ)
    await got.body?.cancel()
    await countFailedGet()
    return errorResponse('upload_size_mismatch', cors)
  }
  const status = got.status
  const read = await readRange(got)
  if (!read) {
    console.error(`complete: range get unusable (${status})`)
    if (status < 500) await countFailedGet()
    return errorResponse('upload_failed', cors)
  }

  // 3. ตรวจ + สร้าง asset copying (service_role)
  const b = await serviceRpc(ctx, 'upload_complete_begin', {
    p_account_id: target.account_id,
    p_batch_id: batchId,
    p_item: item,
    p_staging_version_id: read.versionId,
    p_total_bytes: read.totalBytes,
    p_detected_type: detectType(read.bytes),
    p_read_bytes: read.bytes.length,
  })
  if (!b.ok) return errorResponse(b.code, cors)
  const begun = b.data as Begin
  if ('code' in begun) {
    // ไฟล์ที่ตรวจไม่ผ่านลบทิ้งทันที (เฉพาะเวอร์ชันที่ตรวจ) — ผู้ใช้เลือกไฟล์ใหม่ใน batch ใหม่
    if (begun.code === 'upload_size_mismatch' || begun.code === 'upload_type_mismatch') {
      await deleteStaging(target.staging_key, read.versionId)
    }
    return errorResponse(begun.code, cors)
  }
  if ('existing' in begun) return fromExisting(target, { id: begun.asset_id, status: begun.status })

  // 4. CopyObject ระบุเวอร์ชันต้นทาง
  let copied: Response
  try {
    copied = await deps.fetch(
      await copyObjectRequest(config, {
        sourceKey: target.staging_key,
        sourceVersionId: read.versionId,
        destKey: begun.final_key,
        contentType: begun.content_type,
      }),
    )
  } catch {
    console.error('complete: copy failed (network) — left for sweeper')
    return errorResponse('upload_failed', cors)
  }
  const copyBody = await copied.text()
  const result = parseCopyResult(copied.status, copyBody)
  const versionId = copied.headers.get('x-amz-version-id')
  if (!result) {
    if (copied.status >= 400 && copied.status < 500) {
      // ปฏิเสธแน่นอน ปลายทางไม่มีไฟล์ → ลบแถว copying
      const aborted = await serviceRpc(ctx, 'upload_complete_abort', { p_asset_id: begun.asset_id })
      if (!aborted.ok) console.error(`complete: abort failed (${aborted.code})`)
      return errorResponse(
        isCapExceeded(copied.status, copyBody) ? 'download_budget_reached' : 'upload_failed',
        cors,
      )
    }
    console.error(`complete: copy uncertain (${copied.status}) — left for sweeper`)
    return errorResponse('upload_failed', cors)
  }
  // ETag ของ CopyObject เป็นหลัก (ไม่มีให้ใช้ ETag ของต้นทางเวอร์ชันเดียวกันจาก GET)
  const checksum = result.etag ?? read.etag
  if (!versionId || !checksum) {
    console.error('complete: copy result without version/etag — left for sweeper')
    return errorResponse('upload_failed', cors)
  }

  // 5. ready
  const f = await serviceRpc(ctx, 'upload_complete_finish', {
    p_asset_id: begun.asset_id,
    p_version_id: versionId,
    p_checksum: checksum,
  })
  if (!f.ok) return errorResponse(f.code, cors)

  // 6. ลบไฟล์พักเวอร์ชันที่คัดลอกแล้ว
  await deleteStaging(target.staging_key, read.versionId)
  return done(target, begun.asset_id)
}
