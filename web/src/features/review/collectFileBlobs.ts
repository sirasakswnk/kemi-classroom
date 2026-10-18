import type { QueryClient } from '@tanstack/react-query'
import {
  fileBlobKey,
  linkFreshMs,
  loadSignedFile,
  signedFileKey,
  signFiles,
  type SignedFile,
} from '../../lib/files'
import { RequestError } from '../../lib/request'
import { toAppError } from '../../lib/supabase'
import type { AttachmentRef } from '../uploads/AttachmentList'

// รวบรวมเนื้อไฟล์ของงานส่งเพื่อรวมเป็น PDF (P4-08) ตามงบดาวน์โหลดของ B2 (TECHNICAL_DESIGN 9.3):
//   1. ไฟล์ที่ตัวดูโหลดไว้แล้ว (Blob ในแคช) ใช้ตรง ๆ — ไม่แตะ B2
//   2. ไฟล์ที่ยังไม่มี Blob แต่มีลิงก์ลงลายเซ็นที่ยังไม่ใกล้หมดอายุ ใช้ลิงก์นั้น — ไม่ขอลิงก์ใหม่
//   3. ที่เหลือขอลิงก์รวดเดียว (หนึ่งคำขอ /files/sign) แล้วโหลดไฟล์ละครั้ง และเก็บ Blob/ลิงก์เข้าแคชเดียวกับตัวดู
// ล้มเหลวข้อใดข้อหนึ่ง (เช่น download_budget_reached) → throw ทั้งชุด ไม่คืนไฟล์ครึ่งเดียว

export interface CollectDeps {
  sign: (assetIds: string[], mode: 'view') => Promise<SignedFile[]>
  load: (file: SignedFile) => Promise<Blob>
}

const defaultDeps: CollectDeps = { sign: signFiles, load: (f) => loadSignedFile(f) }

export async function collectFileBlobs(
  queryClient: QueryClient,
  files: AttachmentRef[],
  onProgress?: (done: number, total: number) => void,
  deps: CollectDeps = defaultDeps,
  now: number = Date.now(),
): Promise<Blob[]> {
  const blobs = new Map<string, Blob>()
  const links = new Map<string, SignedFile>()
  for (const f of files) {
    const cached = queryClient.getQueryData<Blob>(fileBlobKey(f.asset_id))
    if (cached) {
      blobs.set(f.asset_id, cached)
      continue
    }
    const link = queryClient.getQueryData<SignedFile>(signedFileKey(f.asset_id, 'view'))
    if (link && linkFreshMs(link, now) > 0) links.set(f.asset_id, link)
  }

  const needLink = files.filter((f) => !blobs.has(f.asset_id) && !links.has(f.asset_id))
  if (needLink.length > 0) {
    const signed = await deps.sign(
      needLink.map((f) => f.asset_id),
      'view',
    )
    for (const s of signed) {
      queryClient.setQueryData(signedFileKey(s.assetId, 'view'), s)
      links.set(s.assetId, s)
    }
  }

  let done = blobs.size
  onProgress?.(done, files.length)
  for (const f of files) {
    if (blobs.has(f.asset_id)) continue
    const link = links.get(f.asset_id)
    try {
      if (!link) throw new RequestError(toAppError({ code: 'P0001', message: 'forbidden' }))
      const blob = await deps.load(link)
      queryClient.setQueryData(fileBlobKey(f.asset_id), blob)
      blobs.set(f.asset_id, blob)
    } catch (error) {
      // ลิงก์ที่ใช้ไม่ได้ (หมดอายุ/ถูกปฏิเสธ) ไม่ค้างในแคชให้ลองซ้ำแล้วชนอีก
      queryClient.removeQueries({ queryKey: signedFileKey(f.asset_id, 'view') })
      throw error
    }
    done += 1
    onProgress?.(done, files.length)
  }
  return files.map((f) => blobs.get(f.asset_id)!)
}
