import { createContext, type ReactNode } from 'react'

// Toast ใช้แจ้งผลสำเร็จ/ข้อมูลสั้น ๆ เท่านั้น — ไม่มีแบบข้อผิดพลาดโดยตั้งใจ:
// ข้อผิดพลาดต้องแสดงใกล้จุดที่เกิด (Field error หรือข้อความในหน้า) ตาม UX 13 และ 7.1
export type ToastTone = 'success' | 'info'

export interface ShowToast {
  (message: ReactNode, options?: { tone?: ToastTone }): void
}

export const ToastContext = createContext<ShowToast | null>(null)
