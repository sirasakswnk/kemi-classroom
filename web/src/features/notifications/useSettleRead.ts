import { useQueryClient } from '@tanstack/react-query'
import { notificationsQuery, unreadCountQuery } from './api'

/** หลังทำเครื่องหมายอ่าน: ตั้งตัวเลขกระดิ่งตามผลเซิร์ฟเวอร์ แล้วโหลดรายการใหม่ */
export function useSettleRead() {
  const queryClient = useQueryClient()
  return (count: number) => {
    queryClient.setQueryData(unreadCountQuery.queryKey, count)
    void queryClient.invalidateQueries({ queryKey: notificationsQuery.queryKey })
  }
}
