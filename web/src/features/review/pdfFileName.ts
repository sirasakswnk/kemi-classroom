// ชื่อไฟล์ PDF รวมของงานส่ง: `{เลขที่}_{ชื่อ}_{นามสกุล}.pdf` เช่น 12_ธนภัทร_ใจดี.pdf (UX 9 [ยืนยัน 29 ก.ย. 2026])
// ตัดอักขระที่ใช้เป็นชื่อไฟล์ไม่ได้ (/ \ : * ? " < > |) และอักขระควบคุม; ช่องว่างในชื่อกลายเป็น _; ไม่มีเลขที่ = ไม่ใส่ส่วนหน้า

// อักขระต้องห้ามของ Windows + อักขระควบคุม (สร้างจากรหัสเพื่อไม่ต้องเขียนอักขระควบคุมตรง ๆ ในนิพจน์)
const FORBIDDEN = new RegExp(
  `[\\\\/:*?"<>|${String.fromCharCode(0)}-${String.fromCharCode(31)}]`,
  'g',
)

function cleanPart(s: string): string {
  return s.replace(FORBIDDEN, '').trim()
}

export function pdfFileName(roll: number | null, displayName: string): string {
  // NFC: ชื่อจาก Excel/แป้นพิมพ์ต่างระบบอาจเรียงอักขระผสมต่างกัน; อักขระไทยทั้งหมดรวมสระบน/ล่างและวรรณยุกต์คงอยู่
  // (ตัดเฉพาะอักขระต้องห้ามของชื่อไฟล์ใน FORBIDDEN และยุบช่องว่าง)
  const words = displayName
    .normalize('NFC')
    .split(/\s+/)
    .map(cleanPart)
    .filter((w) => w.length > 0)
  const parts = [...(roll !== null ? [String(roll)] : []), ...words]
  // Windows ไม่ให้ชื่อไฟล์ลงท้ายด้วยจุด/ช่องว่าง
  const base = parts.join('_').replace(/[. ]+$/, '')
  return `${base || 'งานส่ง'}.pdf`
}
