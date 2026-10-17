// สูตรคะแนนส่งช้า (TECHNICAL_DESIGN ส่วน 6 ข้อ 3, L2) — ต้องตรงกับ private.grade_net_score ใน 0025_grading
// ชุดตัวอย่างร่วมกับฐานข้อมูล: supabase/tests/fixtures/score_cases.json

// คะแนนสุทธิ = ceil(raw × (100 − pct) / 100) ด้วยจำนวนเต็มล้วน (ไม่ใช้ทศนิยมลอยตัว)
// raw ไม่เกิน 1,000,000 ผลคูณจึงไม่เกิน 10^8 อยู่ในช่วงจำนวนเต็มที่ number แทนได้ตรง
export function netScore(raw: number, pct: number): number {
  return Math.floor((raw * (100 - pct) + 99) / 100)
}
