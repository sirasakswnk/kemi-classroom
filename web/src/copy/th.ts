// ข้อความภาษาไทยบนหน้าจอทั้งหมด — ยึดถ้อยคำจาก UX_DESIGN และแบบ v2
export const th = {
  appName: 'ห้องเคมี',
  field: {
    // ต่อท้ายชื่อช่องที่ไม่บังคับ (แบบ v2: “รายละเอียด · ไม่บังคับ”)
    optional: 'ไม่บังคับ',
  },
  dialog: {
    close: 'ปิด',
  },
  stepper: {
    // แบบ v2: “ลดโทเคน” / “เพิ่มโทเคน”
    decrease: (label: string) => `ลด${label}`,
    increase: (label: string) => `เพิ่ม${label}`,
  },
  steps: {
    // อ่านให้เครื่องอ่านหน้าจอเท่านั้น (ไอคอนบอกสถานะด้วยภาพ)
    done: 'เสร็จแล้ว',
    skipped: 'ข้ามขั้นนี้',
  },
} as const
