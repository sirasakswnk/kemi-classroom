import { useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { useAuth } from './useAuth'

// เปลี่ยนผู้ใช้หรือออกจากระบบ → ล้างข้อมูลที่ cache ไว้ของผู้ใช้ก่อน (กันข้อมูลข้ามบัญชีในแท็บเดียวกัน)
export function QueryReset() {
  const { state } = useAuth()
  const queryClient = useQueryClient()
  const userId = state.status === 'ready' || state.status === 'error' ? state.session.user.id : null
  useEffect(() => {
    queryClient.clear()
  }, [userId, queryClient])
  return null
}
