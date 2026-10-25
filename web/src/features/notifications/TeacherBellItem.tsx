import { HardDrive, Inbox, MessageCircle } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router'
import { cx } from '../../lib/cx'
import { markNotificationsRead } from './api'
import type { TeacherBellIcon, TeacherBellRow } from './bellState'
import styles from './notifications.module.css'
import { useSettleRead } from './useSettleRead'

const ICONS: Record<TeacherBellIcon, ReactNode> = {
  pending: <Inbox />,
  comment: <MessageCircle />,
  storage: <HardDrive />,
}

// แถวแจ้งเตือนของครู (แบบ v2 tNotifRow) — ใช้ใน T11 และแผง “แจ้งเตือนล่าสุด” ของภาพรวม
// กดแล้วนับอ่านเบื้องหลังและไปหน้าเป้าหมายทันที (ล้มก็ไม่ขวางการเปิด)
export function TeacherBellItem({ row, read }: { row: TeacherBellRow; read: boolean }) {
  const settle = useSettleRead()
  return (
    <li>
      <Link
        to={row.href}
        className={cx(styles.row, row.unread && styles.unread, row.faded && styles.faded)}
        onClick={() => {
          if (!read) markNotificationsRead([row.id]).then(settle, () => undefined)
        }}
      >
        <span className={styles.ic} data-tone={row.icon} aria-hidden="true">
          {ICONS[row.icon]}
        </span>
        <span className={styles.text}>
          <b>{row.title}</b>
          {row.detail && <span className={styles.detail}>{row.detail}</span>}
          {row.faded && <span className={styles.fadedNote}>{row.faded}</span>}
        </span>
        <time dateTime={row.at}>{row.time}</time>
      </Link>
    </li>
  )
}
