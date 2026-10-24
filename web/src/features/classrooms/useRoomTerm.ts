import { useQuery } from '@tanstack/react-query'
import { termNamesQuery, termQuery } from './api'

// ภาคเรียนของห้อง (UX ข้อใหม่ใต้ “[ยืนยัน I5]”, P5-09): ชื่อภาคเรียนของห้องนั้นเอง + เป็นห้องของภาคเรียนก่อนหรือไม่
export function useRoomTerm(termId: string | undefined): { name: string; past: boolean } {
  const current = useQuery(termQuery)
  const names = useQuery({ ...termNamesQuery, enabled: !!termId })
  const past = !!termId && !!current.data && termId !== current.data.id
  const name = (termId && names.data?.get(termId)) || (past ? '' : (current.data?.name ?? ''))
  return { name, past }
}
