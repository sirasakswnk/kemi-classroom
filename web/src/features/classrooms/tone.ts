/** สีแถบชั้นเรียนวนตามลำดับที่สร้าง (แบบ v2 มี 5 ชุด: ม.5/1–5/3 และ NEW_G สองชุด) — ใช้กับ data-tone ใน CSS */
export const CLASS_TONES = 5

export function classTone(index: number): number {
  return ((index % CLASS_TONES) + CLASS_TONES) % CLASS_TONES
}
