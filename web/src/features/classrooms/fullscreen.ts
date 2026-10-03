/** ขอเต็มจอต้องเรียกในตัวจัดการคลิก (ต้องมีการกระทำของผู้ใช้) — เบราว์เซอร์ไม่ยอมก็ยังแสดงเต็มหน้าต่าง */
export function requestPageFullscreen(): void {
  try {
    const p = document.documentElement.requestFullscreen?.()
    p?.catch(() => {})
  } catch {
    // เบราว์เซอร์ไม่รองรับ (เช่น iPhone) — แสดงเต็มหน้าต่างแทน
  }
}

export function leaveFullscreen() {
  try {
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => {})
  } catch {
    // ไม่มีอะไรต้องทำ
  }
}
