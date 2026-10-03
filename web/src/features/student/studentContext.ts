import { createContext, useContext } from 'react'
import type { MyStudent } from '../identity/identity'

export interface StudentContextValue {
  student: MyStudent
  /** ข้อความแจ้งบนหน้าแรก เช่น “บัญชีนี้เลือกชื่อเรียบร้อยแล้ว” (already_bound) */
  notice: string | null
  /** โหลดข้อมูลการผูกชื่อใหม่ (เช่นเซิร์ฟเวอร์ตอบ identity_required) */
  reloadStudent: () => void
}

export const StudentContext = createContext<StudentContextValue | null>(null)

export function useStudent(): StudentContextValue {
  const value = useContext(StudentContext)
  if (!value) throw new Error('useStudent ต้องอยู่ใต้ StudentLayout')
  return value
}
