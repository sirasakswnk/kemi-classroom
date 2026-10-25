import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlarmClock,
  ArrowLeft,
  BookOpenCheck,
  CalendarClock,
  FilePlus,
  Lock,
  Megaphone,
  MessageCircle,
  PencilLine,
  TriangleAlert,
} from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { appErrorOf } from '../../lib/request'
import { Button } from '../../ui'
import { markNotificationsRead, notificationsQuery, unreadCountQuery } from './api'
import { studentBellRow, type BellIcon } from './bellState'
import styles from './notifications.module.css'
import page from '../student/student.module.css'

const ICONS: Record<BellIcon, ReactNode> = {
  newWork: <FilePlus />,
  announcement: <Megaphone />,
  reminder: <AlarmClock />,
  comment: <MessageCircle />,
  revision: <PencilLine />,
  dueChanged: <CalendarClock />,
  closed: <Lock />,
  solution: <BookOpenCheck />,
}

// C01 กระดิ่งนักเรียน (UX 12, แบบ v2 sNotif): รายการจากเหตุการณ์ล่าสุด · กดแล้วนับอ่านและไปงาน/ประกาศนั้น
// แสดงตามสถานะปัจจุบัน — ส่งแล้ว/ปิดรับแล้ว/ความคิดเห็นที่ยกเลิก แสดงจาง ไม่ดึงความสนใจ · งานที่ถูกลบหายจากรายการเอง
// ไม่มีเนื้อข้อความความคิดเห็น (TECHNICAL_DESIGN 11)
export default function StudentBell() {
  const copy = th.bell
  const queryClient = useQueryClient()
  const list = useInfiniteQuery(notificationsQuery)
  const unread = useQuery(unreadCountQuery)
  const now = new Date()

  const settle = (count: number) => {
    queryClient.setQueryData(unreadCountQuery.queryKey, count)
    void queryClient.invalidateQueries({ queryKey: notificationsQuery.queryKey })
  }
  const readAll = useMutation({ mutationFn: () => markNotificationsRead(null), onSuccess: settle })
  // กดรายการ: นับอ่านเบื้องหลังแล้วไปหน้าเป้าหมายทันที (ล้มก็ไม่ขวางการเปิดงาน — กลับมาจะยังเห็นว่ายังไม่อ่าน)
  const readOne = (id: string) => {
    markNotificationsRead([id]).then(settle, () => undefined)
  }

  const items = list.data?.pages.flatMap((p) => p.items) ?? []
  const rows = items.flatMap((item) => {
    const row = studentBellRow(item, now)
    return row ? [{ row, read: item.read }] : []
  })
  const count = unread.data ?? list.data?.pages[0]?.unread_count ?? 0

  return (
    <main className={page.page} data-width="narrow">
      <Link to="/" className={page.back}>
        <ArrowLeft aria-hidden="true" />
        {copy.backHome}
      </Link>
      <div className={styles.head}>
        <h1>{copy.title}</h1>
        {count > 0 && (
          <button
            type="button"
            className={page.link}
            disabled={readAll.isPending}
            onClick={() => readAll.mutate()}
          >
            {copy.readAll}
          </button>
        )}
      </div>

      {list.isPending ? (
        <p role="status" className={page.muted}>
          {th.common.loading}
        </p>
      ) : list.isError ? (
        <div className={page.note} data-tone="red" role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            <b>{copy.loadFailed}</b> {appErrorOf(list.error).message}
          </span>
          <Button size="sm" variant="ghost" onClick={() => void list.refetch()}>
            {copy.retry}
          </Button>
        </div>
      ) : rows.length === 0 ? (
        <p className={styles.empty}>{copy.empty}</p>
      ) : (
        <ul className={styles.list}>
          {rows.map(({ row, read }) => (
            <li key={row.id}>
              <Link
                to={row.href}
                className={cx(styles.row, row.unread && styles.unread, row.faded && styles.faded)}
                onClick={() => {
                  if (!read) readOne(row.id)
                }}
              >
                <span className={styles.ic} aria-hidden="true">
                  {ICONS[row.icon]}
                </span>
                <span className={styles.text}>
                  <b>{row.title}</b>
                  <span className={styles.detail}>{row.detail}</span>
                  {row.faded && <span className={styles.fadedNote}>{row.faded}</span>}
                </span>
                <time dateTime={row.at}>{row.time}</time>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {list.hasNextPage && (
        <Button
          variant="ghost"
          className={styles.more}
          disabled={list.isFetchingNextPage}
          onClick={() => void list.fetchNextPage()}
        >
          {list.isFetchingNextPage ? th.common.loading : copy.more}
        </Button>
      )}
      <p className={styles.footer}>{copy.footer}</p>
    </main>
  )
}
