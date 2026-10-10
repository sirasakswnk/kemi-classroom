import { useQuery } from '@tanstack/react-query'
import {
  ChevronRight,
  CircleCheck,
  ClockAlert,
  FilePen,
  Hourglass,
  Lock,
  Pencil,
  Sparkles,
  TriangleAlert,
} from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip, type ChipTone } from '../../ui'
import { myWorkQuery, type WorkRow } from './api'
import { filterWork, sortWork, workBadge, type WorkFilter } from './workState'
import styles from './work.module.css'

const FILTERS: WorkFilter[] = ['all', 'todo', 'done']

const ICONS: Record<ChipTone, ReactNode> = {
  amber: <FilePen />,
  purple: <Hourglass />,
  red: <ClockAlert />,
  plain: <Lock />,
  green: <CircleCheck />,
  gold: <Sparkles />,
  outline: <FilePen />,
}

// S02 แท็บ “โพสต์งานของคุณครู” ของนักเรียน (UX 5; แบบ v2 sClass + workCard): ตัวกรอง ทั้งหมด/ยังไม่ส่ง/ส่งแล้ว,
// การ์ดชื่อ กำหนดส่ง สถานะส่วนตัว และรางวัลที่รู้ล่วงหน้า กดเข้า S03; เรียงค้าง/ใกล้ส่งก่อน
// สถานะจาก RPC my_work (ฟังก์ชันตัดสินเดียวกับการส่งงาน) · ตั้งแต่ 960 px การ์ด 2 คอลัมน์ (UX 13)
export function StudentWorkList({ classroomId }: { classroomId: string }) {
  const work = useQuery(myWorkQuery(classroomId))
  const [filter, setFilter] = useState<WorkFilter>('all')
  const copy = th.work

  if (work.isPending) {
    return (
      <p role="status" className={styles.muted}>
        {th.common.loading}
      </p>
    )
  }
  if (work.isError) {
    const error = appErrorOf(work.error)
    return (
      <p className={styles.error} role="alert">
        <TriangleAlert aria-hidden="true" />
        <span>
          {th.posts.list.loadFailed} {error.message}
          {error.ref && ` (${th.errors.reference(error.ref)})`}
        </span>
        <Button size="sm" variant="ghost" onClick={() => void work.refetch()}>
          {th.teacher.retry}
        </Button>
      </p>
    )
  }

  const rows = sortWork(work.data)
  if (!rows.length) {
    return (
      <div className={styles.empty}>
        <FilePen aria-hidden="true" />
        <span>{th.student.room.workEmpty}</span>
      </div>
    )
  }
  const shown = filterWork(rows, filter)
  return (
    <>
      <div className={styles.filters} role="group" aria-label={copy.filtersAria}>
        {FILTERS.map((f) => (
          <button
            key={f}
            type="button"
            className={styles.filter}
            aria-pressed={filter === f}
            onClick={() => setFilter(f)}
          >
            {copy.filters[f]}
            <span className={styles.n}>{filterWork(rows, f).length}</span>
          </button>
        ))}
      </div>
      {shown.length ? (
        <ul className={styles.workList}>
          {shown.map((row) => (
            <li key={row.post_id}>
              <WorkCard row={row} />
            </li>
          ))}
        </ul>
      ) : (
        <div className={styles.empty}>
          <CircleCheck aria-hidden="true" />
          <span>{filter === 'done' ? copy.noneSubmitted : copy.noneInFilter}</span>
        </div>
      )}
    </>
  )
}

function WorkCard({ row }: { row: WorkRow }) {
  const badge = workBadge(row)
  return (
    <Link to={`/w/${row.post_id}`} className={styles.workCard}>
      <span className={styles.wIc} data-tone={badge.tone} aria-hidden="true">
        {row.permission_open ? <Pencil /> : ICONS[badge.tone]}
      </span>
      <span className={styles.text}>
        <h3 className={styles.title}>{row.title}</h3>
        <span className={styles.meta}>
          {th.posts.list.due(thaiDate(row.due_at), thaiTime(row.due_at))}
        </span>
        <span className={styles.chips}>
          <Chip tone={badge.tone}>{badge.label}</Chip>
          {!row.submitted && row.outcome === 'first_on_time' && row.reward_tokens > 0 && (
            <Chip tone="gold" icon={<Sparkles />}>
              {th.posts.list.reward(row.reward_tokens)}
            </Chip>
          )}
        </span>
      </span>
      <ChevronRight aria-hidden="true" className={styles.chev} />
    </Link>
  )
}
