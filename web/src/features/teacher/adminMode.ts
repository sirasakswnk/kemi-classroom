import { useSyncExternalStore } from 'react'

// โหมดผู้ดูแล (L6) เป็นสถานะของหน้าเว็บ: ผู้ดูแลกด “เข้าหน้าครูในโหมดผู้ดูแล” แล้วใช้หน้าครูพร้อมแถบเตือน
// สิทธิ์จริงมาจาก role admin ในฐานข้อมูล; RPC ฝั่งครูต้องได้ p_admin_mode = true (TECHNICAL_DESIGN 3)
// เก็บใน sessionStorage: อยู่ได้ตลอดแท็บนั้น ปิดแท็บแล้วหมดโหมด
const KEY = 'kemi:admin-mode'
const listeners = new Set<() => void>()
// สำรองเมื่อ sessionStorage ใช้ไม่ได้ (เช่นโหมดส่วนตัวบางเบราว์เซอร์): อยู่ได้จนโหลดหน้าใหม่
let memory = false

function read(): boolean {
  try {
    return sessionStorage.getItem(KEY) === '1'
  } catch {
    return memory
  }
}

function write(on: boolean) {
  memory = on
  try {
    if (on) sessionStorage.setItem(KEY, '1')
    else sessionStorage.removeItem(KEY)
  } catch {
    // ใช้ค่าใน memory แทน
  }
  listeners.forEach((l) => l())
}

export const enterAdminMode = () => write(true)
export const exitAdminMode = () => write(false)

export function useAdminModeFlag(): boolean {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l)
      return () => listeners.delete(l)
    },
    read,
    () => false,
  )
}
