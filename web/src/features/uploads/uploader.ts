// ลำดับการอัปโหลดหนึ่งชุด: ขอ batch → PUT ทีละ 2 ไฟล์ → complete รายไฟล์ได้ asset_id
// ไม่พึ่ง React/เครือข่ายโดยตรง (ส่ง deps เข้ามา) จึงทดสอบลำดับและการลองใหม่ด้วยของจำลองได้
//   - ลิงก์ PUT หมดอายุ (403) → ขอ batch ซ้ำด้วย request key เดิม (ได้ batch เดิม ลิงก์ใหม่) แล้วลองใหม่ 1 ครั้ง
//   - เน็ตหลุดระหว่าง PUT → ลองใหม่ 1 ครั้ง
//   - complete ได้ upload_in_progress → รอแล้วลองใหม่ (ขั้นนี้เรียกซ้ำได้ผลเดิม)
//   - รหัสอื่นของ complete (upload_failed/expired/size/type, download_budget_reached) → ไฟล์นั้นล้มเหลว
//     ผู้ใช้กดลองใหม่ = ชุดใหม่ (request key ใหม่) เฉพาะไฟล์ที่ล้ม
import { RequestError } from '../../lib/request'
import { toAppError, type AppError } from '../../lib/supabase'
import { PutError, type Batch, type BatchRequest, type Completed } from './api'
import type { UploadType } from './rules'

export const PUT_CONCURRENCY = 2
export const IN_PROGRESS_WAIT_MS = 20_000
export const IN_PROGRESS_TRIES = 3
export const NETWORK_RETRY_WAIT_MS = 2_000

export interface UploadDeps {
  requestBatch: (req: BatchRequest) => Promise<Batch>
  put: (
    url: string,
    blob: Blob,
    type: UploadType,
    onProgress: (loaded: number, total: number) => void,
    signal?: AbortSignal,
  ) => Promise<void>
  complete: (batchId: string, item: number) => Promise<Completed>
  sleep: (ms: number, signal?: AbortSignal) => Promise<void>
}

export interface UploadEntry {
  id: string
  blob: Blob
  name: string
  type: UploadType
  /** ยกเลิกเฉพาะไฟล์นี้ (นำออกระหว่างอัปโหลด) */
  signal?: AbortSignal
}

export type UploadEvent =
  | { id: string; phase: 'uploading'; loaded: number; total: number }
  | { id: string; phase: 'completing' }
  | { id: string; phase: 'done'; assetId: string }
  | { id: string; phase: 'failed'; error: AppError }
  | { id: string; phase: 'cancelled' }

const appError = (code: string): AppError => toAppError({ code: 'P0001', message: code })

const errorOf = (e: unknown): AppError => (e instanceof RequestError ? e.appError : toAppError(e))

const anySignal = (signals: (AbortSignal | undefined)[]): AbortSignal | undefined => {
  const list = signals.filter((s): s is AbortSignal => !!s)
  return list.length === 0 ? undefined : list.length === 1 ? list[0] : AbortSignal.any(list)
}

/** ข้อผิดพลาดของ PUT → ข้อความที่แถวไฟล์ (UX 7.1) */
function putErrorToApp(e: PutError): AppError {
  if (e.kind === 'cap') return appError('download_budget_reached')
  if (e.kind === 'network') return toAppError(new TypeError('network'))
  return appError('upload_failed')
}

/**
 * อัปโหลดหนึ่งชุด — แจ้งความคืบหน้าผ่าน onEvent ทุกไฟล์ (จบทุกไฟล์ด้วย done/failed/cancelled)
 * signal ยกเลิกทั้งชุด; entry.signal ยกเลิกไฟล์เดียว
 */
export async function uploadSet(
  entries: UploadEntry[],
  target: Omit<BatchRequest, 'files' | 'requestKey'>,
  requestKey: string,
  deps: UploadDeps,
  onEvent: (event: UploadEvent) => void,
  signal?: AbortSignal,
): Promise<void> {
  const request: BatchRequest = {
    ...target,
    files: entries.map((e) => ({ name: e.name, type: e.type, size: e.blob.size })),
    requestKey,
  }
  let batch: Batch
  try {
    batch = await deps.requestBatch(request)
  } catch (e) {
    const error = errorOf(e)
    for (const entry of entries) onEvent({ id: entry.id, phase: 'failed', error })
    return
  }
  if (batch.files.length !== entries.length) {
    for (const entry of entries)
      onEvent({ id: entry.id, phase: 'failed', error: toAppError({ name: 'InvalidResponse' }) })
    return
  }

  // ขอลิงก์ใหม่ครั้งเดียวต่อรอบหมดอายุ — ไฟล์ที่หมดอายุพร้อมกันใช้ผลเดียวกัน
  let refreshing: Promise<Batch> | null = null
  const refresh = (stale: Batch) => {
    if (batch !== stale) return Promise.resolve(batch)
    refreshing ??= deps.requestBatch(request).then((fresh) => {
      batch = fresh
      refreshing = null
      return fresh
    })
    return refreshing
  }

  const uploadOne = async (entry: UploadEntry, index: number) => {
    const item = index + 1
    const stop = anySignal([signal, entry.signal])
    const report = (loaded: number, total: number) =>
      onEvent({ id: entry.id, phase: 'uploading', loaded, total })
    report(0, entry.blob.size)

    // PUT (ลองใหม่: ลิงก์หมดอายุ 1 ครั้ง, เน็ตหลุด 1 ครั้ง)
    let refreshed = false
    let networkRetried = false
    for (;;) {
      const used = batch
      try {
        await deps.put(used.files[index].upload_url, entry.blob, entry.type, report, stop)
        break
      } catch (e) {
        if (e instanceof PutError && e.kind === 'aborted') {
          onEvent({ id: entry.id, phase: 'cancelled' })
          return
        }
        if (e instanceof PutError && e.kind === 'expired' && !refreshed) {
          refreshed = true
          try {
            await refresh(used)
          } catch (re) {
            onEvent({ id: entry.id, phase: 'failed', error: errorOf(re) })
            return
          }
          continue
        }
        if (e instanceof PutError && e.kind === 'network' && !networkRetried) {
          networkRetried = true
          try {
            await deps.sleep(NETWORK_RETRY_WAIT_MS, stop)
          } catch {
            onEvent({ id: entry.id, phase: 'cancelled' })
            return
          }
          continue
        }
        onEvent({
          id: entry.id,
          phase: 'failed',
          error: e instanceof PutError ? putErrorToApp(e) : errorOf(e),
        })
        return
      }
    }

    // complete (เรียกซ้ำได้ผลเดิม) — ไม่ยกเลิกกลางคัน: ไฟล์ขึ้นไปแล้ว ให้ระบบบันทึกให้จบ
    onEvent({ id: entry.id, phase: 'completing' })
    for (let attempt = 1; ; attempt++) {
      try {
        const done = await deps.complete(batch.batch_id, item)
        onEvent({ id: entry.id, phase: 'done', assetId: done.asset_id })
        return
      } catch (e) {
        const error = errorOf(e)
        if (error.code === 'upload_in_progress' && attempt < IN_PROGRESS_TRIES) {
          await deps.sleep(IN_PROGRESS_WAIT_MS).catch(() => undefined)
          continue
        }
        onEvent({ id: entry.id, phase: 'failed', error })
        return
      }
    }
  }

  // คิวทีละ PUT_CONCURRENCY ไฟล์ ตามลำดับที่เลือก
  let next = 0
  const worker = async () => {
    while (next < entries.length) {
      const index = next++
      await uploadOne(entries[index], index)
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(PUT_CONCURRENCY, entries.length) }, () => worker()),
  )
}

/** sleep ที่ยกเลิกได้ */
export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new PutError('aborted'))
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort)
      resolve()
    }, ms)
    const onAbort = () => {
      clearTimeout(timer)
      reject(new PutError('aborted'))
    }
    signal?.addEventListener('abort', onAbort, { once: true })
  })
}
