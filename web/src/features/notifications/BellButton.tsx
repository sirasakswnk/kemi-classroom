import { useQuery } from '@tanstack/react-query'
import { Bell } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { unreadCountQuery } from './api'
import styles from './notifications.module.css'

// กระดิ่งบนหัวเว็บ (แบบ v2 .icon-btn + .dot) → หน้าแจ้งเตือน · ตัวเลข = ยังไม่อ่านที่ยังเกี่ยวข้อง (0048)
export function BellButton({ to }: { to: string }) {
  const { data } = useQuery(unreadCountQuery)
  const n = data ?? 0
  return (
    <Link to={to} className={styles.bellBtn} aria-label={th.bell.buttonAria(n)}>
      <Bell aria-hidden="true" />
      {n > 0 && (
        <span className={styles.badge} aria-hidden="true">
          {n > 99 ? '99+' : n}
        </span>
      )}
    </Link>
  )
}
