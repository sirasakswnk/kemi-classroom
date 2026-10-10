// ป้าย “ใหม่” บนแท็บ “โพสต์ทั่วไป” ของ S02 (UX 5 [ยืนยัน 6 ต.ค. 2026])
// - ขึ้นเมื่อมีประกาศที่ published_at ภายใน 7 วัน และใหม่กว่าประกาศล่าสุดที่นักเรียนคนนี้เคยเห็นในห้องนี้
// - ใช้ published_at อย่างเดียว: ครูแก้ไขประกาศ (content_updated_at) ไม่ทำให้ขึ้นใหม่
// - “เห็นแล้ว” = เข้าแท็บ “โพสต์ทั่วไป” → จด published_at ล่าสุดของประกาศ (เวลาของเซิร์ฟเวอร์ ไม่ใช่นาฬิกาเครื่อง)
// - เก็บใน localStorage แยกตามบัญชี + ห้อง; ใช้ไม่ได้ (โหมดไม่ระบุตัวตน/ถูกปิด) → จำได้แค่ในหน้าที่เปิดอยู่
//   (โหลดหน้าใหม่ = เหมือนยังไม่เคยเห็น ขึ้นป้ายตามเพดาน 7 วัน) โดยไม่มี error

export type StorageLike = Pick<Storage, 'getItem' | 'setItem'>

const WINDOW_MS = 7 * 24 * 60 * 60 * 1000

export const seenKey = (accountId: string, classroomId: string) =>
  `kemi:seenAnnouncements:${accountId}:${classroomId}`

// สำรองในหน่วยความจำของหน้า เมื่อ localStorage ใช้ไม่ได้
const memory = new Map<string, string>()

/** สำหรับทดสอบ */
export function resetSeenMemory() {
  memory.clear()
}

function browserStorage(): StorageLike | null {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

const time = (value: string | null | undefined) => {
  const t = value ? Date.parse(value) : Number.NaN
  return Number.isFinite(t) ? t : null
}

/** published_at ล่าสุดที่เคยเห็นในห้องนี้ (null = ยังไม่เคยเห็น หรืออ่านไม่ได้) */
export function readSeen(
  key: string,
  storage: StorageLike | null = browserStorage(),
): string | null {
  let stored: string | null
  try {
    stored = storage?.getItem(key) ?? null
  } catch {
    stored = null
  }
  const candidates = [stored, memory.get(key) ?? null].filter((v) => time(v) !== null) as string[]
  if (!candidates.length) return null
  return candidates.reduce((a, b) => (time(b)! > time(a)! ? b : a))
}

/** จดว่าเห็นประกาศถึง publishedAt แล้ว (ไม่ถอยหลัง) */
export function markSeen(
  key: string,
  publishedAt: string,
  storage: StorageLike | null = browserStorage(),
) {
  const at = time(publishedAt)
  if (at === null) return
  const current = time(readSeen(key, storage))
  if (current !== null && current >= at) return
  memory.set(key, publishedAt)
  try {
    storage?.setItem(key, publishedAt)
  } catch {
    // ใช้ไม่ได้ — จำในหน่วยความจำของหน้าแทน
  }
}

interface AnnouncementLike {
  kind: string
  published_at: string
}

/** published_at ล่าสุดของประกาศในรายการ */
export function latestAnnouncement(posts: AnnouncementLike[]): string | null {
  let best: string | null = null
  for (const p of posts) {
    if (p.kind !== 'announcement' || time(p.published_at) === null) continue
    if (best === null || time(p.published_at)! > time(best)!) best = p.published_at
  }
  return best
}

/** มีประกาศใหม่ที่ควรขึ้นป้ายหรือไม่ */
export function hasNewAnnouncement(
  posts: AnnouncementLike[],
  seen: string | null,
  now: number,
): boolean {
  const seenAt = time(seen)
  return posts.some((p) => {
    const at = time(p.published_at)
    return (
      p.kind === 'announcement' &&
      at !== null &&
      at >= now - WINDOW_MS &&
      (seenAt === null || at > seenAt)
    )
  })
}
