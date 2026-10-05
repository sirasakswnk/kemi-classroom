import { FunctionsHttpError } from '@supabase/supabase-js'
import { queryOptions, useQuery, type UseQueryResult } from '@tanstack/react-query'
import { RequestError } from './request'
import { supabase, toAppError, type AppError } from './supabase'
import { z } from './zod'

// ---------------------------------------------------------------------------
// ลิงก์เปิดดู/ดาวน์โหลดไฟล์จาก B2 — POST /files/sign (Edge Function `files`, P3-05)
// TECHNICAL_DESIGN 9.3 ข้อ 3: ทุกครั้งที่ออกลิงก์นับงบเปิดดูรายวัน จึง
//   - เก็บลิงก์ไว้ตลอดอายุ (TanStack Query ตามคู่ asset + mode) — เปิดซ้ำ/ซูม/หมุนใช้ลิงก์เดิม และเบราว์เซอร์ใช้ไฟล์
//     จากแคช (ลิงก์ขอ response-cache-control: private,max-age=600)
//   - ขอเฉพาะไฟล์ที่กำลังดู (enabled) ไม่โหลดล่วงหน้าทั้งชุด และไม่ขอใหม่เองตอนกลับมาที่แท็บ
// ---------------------------------------------------------------------------
export type FileMode = 'view' | 'download'

/** อายุลิงก์จากเซิร์ฟเวอร์ 600 วินาที — เลิกใช้ก่อนหมดจริง 60 วินาที เผื่อไฟล์ใหญ่ที่ยังโหลดไม่เสร็จ */
export const LINK_SAFETY_MS = 60_000

const signResponseSchema = z.object({
  mode: z.enum(['view', 'download']),
  expires_at: z.string(),
  files: z.array(
    z.object({
      asset_id: z.string(),
      url: z.string().url(),
      file_name: z.string(),
      content_type: z.string(),
      size_bytes: z.number().int(),
    }),
  ),
})

export interface SignedFile {
  assetId: string
  url: string
  fileName: string
  contentType: string
  sizeBytes: number
  /** เวลาหมดอายุของลิงก์ (ms ตั้งแต่ epoch) */
  expiresAt: number
}

/** ผลจากเซิร์ฟเวอร์ → SignedFile[] (รูปแบบไม่ตรง = null) */
export function parseSignResponse(data: unknown): SignedFile[] | null {
  const parsed = signResponseSchema.safeParse(data)
  if (!parsed.success) return null
  const expiresAt = Date.parse(parsed.data.expires_at)
  if (Number.isNaN(expiresAt)) return null
  return parsed.data.files.map((f) => ({
    assetId: f.asset_id,
    url: f.url,
    fileName: f.file_name,
    contentType: f.content_type,
    sizeBytes: f.size_bytes,
    expiresAt,
  }))
}

/** ข้อผิดพลาดของ Edge Function → AppError (เนื้อคำตอบเป็น { code: 'P0001', message: <รหัส> } แบบเดียวกับ RPC) */
export async function functionError(error: unknown): Promise<AppError> {
  if (error instanceof FunctionsHttpError && error.context instanceof Response) {
    try {
      return toAppError(await error.context.json())
    } catch {
      return toAppError({ name: `http_${error.context.status}` })
    }
  }
  return toAppError(error)
}

/** ขอลิงก์ — ใช้ผ่าน useSignedFile เท่านั้น (เรียกตรงจะไม่ได้แคชและนับงบทุกครั้ง) */
export async function signFiles(assetIds: string[], mode: FileMode): Promise<SignedFile[]> {
  let result: { data: unknown; error: unknown }
  try {
    result = await supabase.functions.invoke('files/sign', {
      body: { asset_ids: assetIds, mode },
    })
  } catch (error) {
    throw new RequestError(toAppError(error))
  }
  if (result.error) throw new RequestError(await functionError(result.error))
  const files = parseSignResponse(result.data)
  if (!files) throw new RequestError(toAppError({ name: 'InvalidResponse' }))
  return files
}

/** เวลาที่ลิงก์ยังใช้ได้ (ms) — หมดแล้ว query ขอลิงก์ใหม่ตอนผู้ใช้เปิดไฟล์นั้นครั้งถัดไป */
export function linkFreshMs(file: SignedFile | undefined, now: number): number {
  return file ? Math.max(0, file.expiresAt - LINK_SAFETY_MS - now) : 0
}

export const signedFileKey = (assetId: string, mode: FileMode) =>
  ['signed-file', assetId, mode] as const

// ไม่ลองซ้ำเมื่อเซิร์ฟเวอร์ตอบรหัสที่รู้จัก (ไม่มีสิทธิ์ ครบงบ ถี่เกิน) — ลองซ้ำ 1 ครั้งเฉพาะเน็ตหลุด/ไม่ทราบสาเหตุ
const retryUnknownOnce = (count: number, error: unknown) =>
  count < 1 && error instanceof RequestError && error.appError.code === 'unknown'

/**
 * ตัวเลือก query ของลิงก์ไฟล์หนึ่งไฟล์ในโหมดหนึ่ง — ใช้ทั้ง useSignedFile และ queryClient.fetchQuery (ขอเมื่อกดปุ่ม)
 * จึงใช้แคชเดียวกัน: กดเปิดซ้ำภายในอายุลิงก์ไม่ขอใหม่และไม่นับงบเพิ่ม
 */
export const signedFileOptions = (assetId: string, mode: FileMode) =>
  queryOptions<SignedFile, RequestError, SignedFile, ReturnType<typeof signedFileKey>>({
    queryKey: signedFileKey(assetId, mode),
    queryFn: async () => (await signFiles([assetId], mode))[0],
    staleTime: (query) => linkFreshMs(query.state.data, Date.now()),
    // ลบจากแคชเมื่อพ้นอายุลิงก์ (ลิงก์ใช้ไม่ได้แล้ว)
    gcTime: 600_000,
    retry: retryUnknownOnce,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  })

/**
 * ลิงก์ของไฟล์หนึ่งไฟล์ในโหมดหนึ่ง — ส่ง enabled = false จนกว่าจะเปิดไฟล์นั้นจริง (ไม่โหลดล่วงหน้า)
 * ข้อผิดพลาดเป็น RequestError (เช่น download_budget_reached, forbidden)
 */
export function useSignedFile(
  assetId: string,
  mode: FileMode,
  enabled = true,
): UseQueryResult<SignedFile, RequestError> {
  return useQuery({ ...signedFileOptions(assetId, mode), enabled })
}

// ---------------------------------------------------------------------------
// โหลดไฟล์จากลิงก์ (ตัวดูไฟล์ P3-08/P3-09 ใช้) — B2 ปฏิเสธเพราะเกินเพดานรายวัน → download_budget_reached (UX 7.1)
// ---------------------------------------------------------------------------
/** คำตอบ 403 ของ B2 เมื่อเกินเพดาน (cap_exceeded / download_cap_exceeded / ข้อความ "cap exceeded") — แบบเดียวกับ _shared/b2.ts */
export function isCapExceeded(status: number, body: string): boolean {
  return status === 403 && /cap[ _]exceeded/i.test(body)
}

const budgetReached = () =>
  new RequestError(toAppError({ code: 'P0001', message: 'download_budget_reached' }))

/**
 * โหลดเนื้อไฟล์ด้วยลิงก์ที่ลงลายเซ็นแล้ว (ใช้แคชของเบราว์เซอร์ตามอายุลิงก์) — คืน Blob ให้ตัวดูสร้าง object URL
 * 403 อื่น (เช่นลิงก์หมดอายุ) ได้ข้อความสำรองพร้อมรหัสอ้างอิง b2_<สถานะ>; ผู้เรียกขอลิงก์ใหม่ได้ด้วย invalidate
 */
export async function loadSignedFile(
  file: SignedFile,
  fetchImpl: typeof fetch = fetch,
): Promise<Blob> {
  let res: Response
  try {
    res = await fetchImpl(file.url)
  } catch (error) {
    throw new RequestError(toAppError(error))
  }
  if (res.ok) return res.blob()
  const body = await res.text().catch(() => '')
  if (isCapExceeded(res.status, body)) throw budgetReached()
  throw new RequestError(toAppError({ name: `b2_${res.status}` }))
}
