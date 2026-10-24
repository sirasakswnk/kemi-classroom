import { ChevronRight, Clock, ClockAlert, FilePlus, PartyPopper, Sparkles } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { bangkokParts, thaiDate, thaiTime } from '../../lib/thaiTime'
import { Chip } from '../../ui'
import type { WorkRow } from './api'
import { dueHint } from './workState'
import styles from './work.module.css'

// S01 “ใกล้กำหนดส่ง” (UX 5; แบบ v2 sHome .due-card): งานที่ยังต้องส่งจากทุกห้อง เชื่อมไป S03 โดยตรง
// empty: ตอนไม่มีงานค้าง — ห้องยังไม่มีงานเลย หรือมีงานและส่งครบแล้ว (dueEmpty)
export function DueSoon({
  rows,
  now,
  empty,
}: {
  rows: WorkRow[]
  now: number
  empty: 'noWork' | 'allSent'
}) {
  const copy = th.work
  if (!rows.length) {
    return (
      <div className={styles.calm}>
        <span className={styles.wIc} aria-hidden="true">
          {empty === 'noWork' ? <FilePlus /> : <PartyPopper />}
        </span>
        {empty === 'noWork' ? (
          <span>
            <b>{copy.noWorkTitle}</b>
          </span>
        ) : (
          <span>
            <b>{copy.noPendingTitle}</b>
            <span className={styles.muted}>{copy.noPendingBody}</span>
          </span>
        )}
      </div>
    )
  }
  return (
    <ul className={styles.dueList}>
      {rows.map((row) => {
        const hint = dueHint(row.due_at, now)
        const [day, ...month] = thaiDate(row.due_at, new Date(now)).split(' ')
        return (
          <li key={row.post_id}>
            <Link to={`/w/${row.post_id}`} className={styles.dueCard}>
              <span className={styles.dateTile} aria-hidden="true">
                <b className="num">{day}</b>
                <span>{month[0] ?? bangkokParts(row.due_at).date.slice(5, 7)}</span>
              </span>
              <span className={styles.text}>
                <h3 className={styles.title}>{row.title}</h3>
                <span className={styles.meta}>
                  {thaiDate(row.due_at, new Date(now))} ·{' '}
                  {copy.dueMeta(thaiTime(row.due_at), row.classroom_name)}
                </span>
                <span className={styles.chips}>
                  {hint === 'soon' && (
                    <Chip tone="amber" icon={<Clock />}>
                      {copy.lessThanDay}
                    </Chip>
                  )}
                  {hint === 'overdue' && (
                    <Chip tone="red" icon={<ClockAlert />}>
                      {copy.overdue}
                    </Chip>
                  )}
                  {row.outcome === 'first_on_time' && row.reward_tokens > 0 && (
                    <Chip tone="gold" icon={<Sparkles />}>
                      {th.posts.list.reward(row.reward_tokens)}
                    </Chip>
                  )}
                </span>
              </span>
              <ChevronRight aria-hidden="true" className={styles.chev} />
            </Link>
          </li>
        )
      })}
    </ul>
  )
}
