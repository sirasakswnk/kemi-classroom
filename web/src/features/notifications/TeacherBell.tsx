import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, Check, HardDrive, Inbox, MessageCircle, TriangleAlert } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { appErrorOf } from '../../lib/request'
import { Button } from '../../ui'
import { TeacherPage } from '../teacher/TeacherLayout'
import { markNotificationsRead, notificationsQuery, unreadCountQuery } from './api'
import { teacherBellRow, type TeacherBellIcon, type TeacherBellRow } from './bellState'
import styles from './notifications.module.css'
import review from '../review/review.module.css'

const ICONS: Record<TeacherBellIcon, ReactNode> = {
  pending: <Inbox />,
  comment: <MessageCircle />,
  storage: <HardDrive />,
}

type Filter = 'all' | 'unread'

// T11 กระดิ่งครู (UX 12, แบบ v2 tNotif): แบ่ง “วันนี้/ก่อนหน้า” · กรอง “ทั้งหมด/ยังไม่อ่าน” · อ่านทั้งหมด
// งานรอตรวจรวมต่องาน → T03 สถานะการส่ง · ความคิดเห็นจากนักเรียนรายคน → หน้าของนักเรียนคนนั้นพร้อมช่องความคิดเห็น
// พื้นที่เก็บไฟล์ → T07 · แสดงตามสถานะปัจจุบัน (ตรวจครบแล้ว/ความคิดเห็นที่ยกเลิก แสดงจาง ไม่นับยังไม่อ่าน)
export default function TeacherBell() {
  const copy = th.bell
  const t = copy.teacher
  const queryClient = useQueryClient()
  const list = useInfiniteQuery(notificationsQuery)
  const unread = useQuery(unreadCountQuery)
  const [filter, setFilter] = useState<Filter>('all')
  const now = new Date()

  const settle = (count: number) => {
    queryClient.setQueryData(unreadCountQuery.queryKey, count)
    void queryClient.invalidateQueries({ queryKey: notificationsQuery.queryKey })
  }
  const readAll = useMutation({ mutationFn: () => markNotificationsRead(null), onSuccess: settle })
  const readOne = (id: string) => {
    markNotificationsRead([id]).then(settle, () => undefined)
  }

  const rows = (list.data?.pages.flatMap((p) => p.items) ?? []).flatMap((item) => {
    const row = teacherBellRow(item, now)
    return row ? [{ row, read: item.read }] : []
  })
  const count = unread.data ?? list.data?.pages[0]?.unread_count ?? 0
  const shown = rows.filter(({ row }) => filter === 'all' || row.unread)
  const groups = [
    { label: t.today, rows: shown.filter(({ row }) => row.today) },
    { label: t.earlier, rows: shown.filter(({ row }) => !row.today) },
  ].filter((g) => g.rows.length > 0)

  const item = ({ row, read }: { row: TeacherBellRow; read: boolean }) => (
    <li key={row.id}>
      <Link
        to={row.href}
        className={cx(styles.row, row.unread && styles.unread, row.faded && styles.faded)}
        onClick={() => {
          if (!read) readOne(row.id)
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

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.title }]}>
      <div className={review.page}>
        <header className={styles.tHead}>
          <div className={review.head}>
            <span className={review.eyebrow}>{t.eyebrow}</span>
            <h1>{copy.title}</h1>
            <p>{t.intro}</p>
          </div>
          {count > 0 && (
            <Button
              variant="ghost"
              icon={<Check />}
              disabled={readAll.isPending}
              onClick={() => readAll.mutate()}
            >
              {copy.readAll}
            </Button>
          )}
        </header>

        {list.isPending ? (
          <p role="status" className={review.muted}>
            {th.common.loading}
          </p>
        ) : list.isError ? (
          <div className={review.note} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              <b>{copy.loadFailed}</b> {appErrorOf(list.error).message}
            </span>
            <Button size="sm" variant="ghost" onClick={() => void list.refetch()}>
              {copy.retry}
            </Button>
          </div>
        ) : (
          <section className={styles.tCard}>
            <div className={styles.tBar}>
              <div className={review.seg} role="group" aria-label={t.filtersAria}>
                {(['all', 'unread'] as const).map((f) => (
                  <button
                    key={f}
                    type="button"
                    aria-pressed={filter === f}
                    onClick={() => setFilter(f)}
                  >
                    {t[f]}
                    <span className={review.n}>{f === 'all' ? rows.length : count}</span>
                  </button>
                ))}
              </div>
            </div>
            {groups.length === 0 ? (
              <div className={styles.tEmpty}>
                <Bell aria-hidden="true" />
                <b>{filter === 'unread' || rows.length > 0 ? t.allRead : t.empty}</b>
                <span>{t.emptyHint}</span>
              </div>
            ) : (
              groups.map((g) => (
                <div key={g.label}>
                  <h2 className={styles.group}>{g.label}</h2>
                  <ul className={styles.tList}>{g.rows.map(item)}</ul>
                </div>
              ))
            )}
          </section>
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
        <p className={styles.footer}>{t.hint}</p>
      </div>
    </TeacherPage>
  )
}
