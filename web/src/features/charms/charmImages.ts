import { useQuery } from '@tanstack/react-query'
import { loadSignedFile, signFiles, type SignedFile } from '../../lib/files'

// รูปเครื่องราง (TECHNICAL_DESIGN 9.3 ข้อ 4.1): ขอลิงก์ครั้งเดียวต่อหน้าจอสำหรับทุกรูปที่เห็น แล้วเก็บใน Cache Storage
// โดยใช้ id ไฟล์เป็นกุญแจ — รูปที่เปลี่ยนได้ id ใหม่เสมอ แต่ละเครื่องจึงโหลดแต่ละรูปจาก B2 ครั้งเดียว
// ขอลิงก์ไม่ได้/เกินงบ/โหลดไม่สำเร็จ → ไม่มีรูปของ id นั้น ผู้เรียกแสดงเหรียญวาดแทน (ไม่แสดงข้อผิดพลาด)

/** files/sign รับได้ครั้งละไม่เกิน 20 id (private.files_sign_limits) */
export const SIGN_CHUNK = 20
const CACHE_NAME = 'kemi-charm-images-v1'
const cacheUrl = (id: string) => `/__charm-image/${id}`

export interface CharmImageDeps {
  cacheGet: (id: string) => Promise<Blob | null>
  cachePut: (id: string, blob: Blob) => Promise<void>
  sign: (ids: string[]) => Promise<SignedFile[]>
  fetchBlob: (file: SignedFile) => Promise<Blob>
}

/** โหลดรูปของ id ที่ให้มา (ซ้ำ/ว่างตัดทิ้ง) — ได้เฉพาะ id ที่โหลดสำเร็จ ไม่โยนข้อผิดพลาด */
export async function loadCharmImages(
  ids: readonly string[],
  deps: CharmImageDeps,
): Promise<Map<string, Blob>> {
  const unique = [...new Set(ids.filter(Boolean))]
  const result = new Map<string, Blob>()
  const missing: string[] = []
  for (const id of unique) {
    const cached = await deps.cacheGet(id).catch(() => null)
    if (cached) result.set(id, cached)
    else missing.push(id)
  }
  for (let i = 0; i < missing.length; i += SIGN_CHUNK) {
    let files: SignedFile[]
    try {
      files = await deps.sign(missing.slice(i, i + SIGN_CHUNK))
    } catch {
      continue
    }
    await Promise.all(
      files.map(async (file) => {
        try {
          const blob = await deps.fetchBlob(file)
          result.set(file.assetId, blob)
          await deps.cachePut(file.assetId, blob).catch(() => undefined)
        } catch {
          // โหลดไม่สำเร็จ: แสดงเหรียญวาด ครั้งหน้าลองใหม่
        }
      }),
    )
  }
  return result
}

const openCache = async (): Promise<Cache | null> => {
  try {
    return typeof caches === 'undefined' ? null : await caches.open(CACHE_NAME)
  } catch {
    // โหมดส่วนตัว/บริบทไม่ปลอดภัย: ใช้ไม่ได้ ก็โหลดจาก B2 ตามปกติ
    return null
  }
}

export const browserCharmImageDeps: CharmImageDeps = {
  async cacheGet(id) {
    const res = await (await openCache())?.match(cacheUrl(id))
    return res ? res.blob() : null
  },
  async cachePut(id, blob) {
    await (
      await openCache()
    )?.put(cacheUrl(id), new Response(blob, { headers: { 'content-type': blob.type } }))
  },
  sign: (ids) => signFiles(ids, 'view'),
  fetchBlob: (file) => loadSignedFile(file),
}

// object URL ต่อ id ใช้ร่วมทั้งแอป (จำนวนรูปเท่าจำนวนเครื่องราง ~13 จึงไม่คืนหน่วยความจำ)
const urls = new Map<string, string>()
const urlOf = (id: string, blob: Blob) => {
  let url = urls.get(id)
  if (!url) {
    url = URL.createObjectURL(blob)
    urls.set(id, url)
  }
  return url
}

/**
 * รูปเครื่องรางของทุก id ที่หน้าจอนี้แสดง — คืน id → object URL (ไม่มี = ใช้เหรียญวาด)
 * โหลดครั้งเดียวต่อชุด id (ขอลิงก์รวมครั้งเดียว) และไม่ลองซ้ำเอง
 */
export function useCharmImages(
  ids: readonly (string | null | undefined)[],
  deps: CharmImageDeps = browserCharmImageDeps,
): ReadonlyMap<string, string> {
  const key = [...new Set(ids.filter((id): id is string => !!id))].sort()
  const { data } = useQuery({
    queryKey: ['charm-images', key],
    queryFn: async () => {
      const blobs = await loadCharmImages(key, deps)
      return new Map([...blobs].map(([id, blob]) => [id, urlOf(id, blob)]))
    },
    enabled: key.length > 0,
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
    refetchOnWindowFocus: false,
  })
  return data ?? EMPTY
}

const EMPTY: ReadonlyMap<string, string> = new Map()
