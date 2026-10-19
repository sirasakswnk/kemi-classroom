// เพดานความคิดเห็น 2,000 ตัว (0025_grading: length() ของ Postgres หลังตัดช่องว่างหัวท้าย) — UX 7.1 comment_too_long
export const COMMENT_MAX = 2000

/** จำนวนตัวอักษรที่ยังพิมพ์ได้ (ติดลบ = เกิน) นับแบบ code point ให้ตรงกับฐานข้อมูล */
export function remaining(draft: string): number {
  return COMMENT_MAX - [...draft.trim()].length
}
