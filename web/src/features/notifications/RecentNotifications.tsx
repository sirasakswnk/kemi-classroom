import { useInfiniteQuery } from '@tanstack/react-query'
import { ChevronRight } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { notificationsQuery } from './api'
import { teacherBellRow } from './bellState'
import { TeacherBellItem } from './TeacherBellItem'
import styles from './notifications.module.css'

const RECENT = 5

// แผง “แจ้งเตือนล่าสุด” ในภาพรวมครู (แบบ v2 tOverview .panel) — RPC เดิมของ T11, 5 รายการล่าสุด + “ดูทั้งหมด”
// โหลดไม่สำเร็จก็ไม่ขวางหน้าภาพรวม: บอกสั้น ๆ แล้วให้ไปหน้าแจ้งเตือน
export function RecentNotifications() {
  const t = th.bell.teacher
  const list = useInfiniteQuery(notificationsQuery)
  const now = new Date()
  const rows = (list.data?.pages[0]?.items ?? [])
    .flatMap((item) => {
      const row = teacherBellRow(item, now)
      return row ? [{ row, read: item.read }] : []
    })
    .slice(0, RECENT)

  return (
    <section className={styles.panel} aria-labelledby="recentNotifs">
      <div className={styles.panelHead}>
        <h2 id="recentNotifs">{t.recent}</h2>
        <Link to="/t/notifications" className={styles.seeAll}>
          {t.seeAll}
          <ChevronRight aria-hidden="true" />
        </Link>
      </div>
      {list.isPending ? (
        <p role="status" className={styles.panelNote}>
          {th.common.loading}
        </p>
      ) : list.isError ? (
        <p role="alert" className={styles.panelNote}>
          {th.bell.loadFailed}
        </p>
      ) : rows.length === 0 ? (
        <p className={styles.panelNote}>{t.empty}</p>
      ) : (
        <ul className={styles.tList}>
          {rows.map((r) => (
            <TeacherBellItem key={r.row.id} row={r.row} read={r.read} />
          ))}
        </ul>
      )}
    </section>
  )
}
