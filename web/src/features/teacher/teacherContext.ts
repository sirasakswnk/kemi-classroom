import { createContext, useContext } from 'react'
import type { Account } from '../../app/auth/account'
import type { Classroom, Term } from '../classrooms/api'

export interface TeacherContextValue {
  account: Account
  /** ผู้ดูแลในโหมดผู้ดูแล — RPC ฝั่งครูต้องส่ง p_admin_mode = true */
  adminMode: boolean
  /** ชื่อที่แสดงบนแถบบน (ชื่อครู หรือ “ผู้ดูแลระบบ”) */
  displayName: string
  term: Term | null
  classrooms: Classroom[]
}

export const TeacherContext = createContext<TeacherContextValue | null>(null)

export function useTeacher(): TeacherContextValue {
  const value = useContext(TeacherContext)
  if (!value) throw new Error('useTeacher ต้องอยู่ใต้ TeacherLayout')
  return value
}
