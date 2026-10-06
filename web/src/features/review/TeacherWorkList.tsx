import { useQuery } from '@tanstack/react-query'
import { BookOpenCheck, CircleCheck, FilePen, Hourglass, Lock, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Chip } from '../../ui'
import type { Post } from '../posts/api'
import { workSummaryQuery, type WorkSummary } from './api'
import { phaseBadge } from './reviewState'
import styles from './review.module.css'

// T08 แท็บ “โพสต์งานของคุณครู” (UX 9 [ข้อเสนอ]; แบบ v2 twRow): งานทุกชิ้นเรียงจากโพสต์ล่าสุด พร้อมกำหนดส่ง สถานะรับงาน
// เฉลย รางวัล แถบส่งแล้ว/ตรวจแล้ว และยอดรอตรวจ ส่งช้า ยังไม่ส่ง → “ดูสถานะการส่ง” ไป T03
// ปุ่ม “ตรวจงาน · n” ไปคนแรกที่รอตรวจมากับหน้าตรวจงาน (P4-04) — ยังไม่แสดงปุ่มที่ยังไม่มีปลายทาง
export function TeacherWorkList({
  posts,
  classroomId,
  heading = 'h3',
}: {
  posts: Post[]
  classroomId: string
  heading?: 'h2' | 'h3'
}) {
  const summary = useQuery(workSummaryQuery(classroomId))
  const [now] = useState(() => Date.now())
  const byId = new Map((summary.data ?? []).map((s) => [s.post_id, s]))
  const Title = heading
  const copy = th.review
  return (
    <ul className={styles.list} aria-label={th.posts.list.homeworkListAria}>
      {posts.map((post) => {
        const a = post.assignment
        const s = byId.get(post.id)
        const phase = s && a ? phaseBadge(s.intake, a.due_at, now) : null
        return (
          <li key={post.id}>
            <article className={styles.twork}>
              <div className={styles.twMain}>
                <span className={styles.wIc} data-tone={phase?.tone} aria-hidden="true">
                  {s?.intake === 'closed' ? <CircleCheck /> : <FilePen />}
                </span>
                <div className={styles.twText}>
                  <Title className={styles.twHeading}>
                    <Link to={`/t/w/${post.id}`} className={styles.twTitle}>
                      {post.title}
                    </Link>
                  </Title>
                  {a && (
                    <span className={styles.meta}>
                      {copy.meta(
                        `${thaiDate(a.due_at)} · ${thaiTime(a.due_at)} น.`,
                        a.full_score,
                        thaiDate(post.published_at),
                      )}
                    </span>
                  )}
                  <span className={styles.chips}>
                    {phase && (
                      <Chip
                        tone={phase.tone}
                        icon={s?.intake === 'closed' ? <Lock /> : <Hourglass />}
                      >
                        {phase.label}
                      </Chip>
                    )}
                    {a?.close_at && s?.intake !== 'closed' && (
                      <Chip tone="plain" icon={<Lock />}>
                        {copy.phase.closeAt(`${thaiDate(a.close_at)} ${thaiTime(a.close_at)} น.`)}
                      </Chip>
                    )}
                    {s?.solution_published && (
                      <Chip tone="green" icon={<BookOpenCheck />}>
                        {copy.solutionPublished}
                      </Chip>
                    )}
                    {a && a.reward_tokens > 0 && (
                      <Chip tone="gold" icon={<Sparkles />}>
                        {copy.tokens(a.reward_tokens)}
                      </Chip>
                    )}
                  </span>
                </div>
              </div>
              {s && <Progress s={s} />}
              <div className={styles.act}>
                <Link
                  to={`/t/w/${post.id}`}
                  className={styles.link}
                  aria-label={copy.openStatusAria(post.title)}
                >
                  {copy.openStatus}
                </Link>
              </div>
            </article>
          </li>
        )
      })}
    </ul>
  )
}

function Progress({ s }: { s: WorkSummary }) {
  const copy = th.review
  const graded = s.submitted - s.waiting
  const pct = (n: number) => (s.total ? (n / s.total) * 100 : 0)
  return (
    <div className={styles.prog}>
      <div className={styles.progTop}>
        <span>{copy.submittedLabel}</span>
        <b>
          {s.submitted}/{s.total}
        </b>
      </div>
      <div
        className={styles.bar}
        role="img"
        aria-label={copy.progressAria(s.submitted, s.waiting, s.not_submitted)}
      >
        <i className={styles.graded} style={{ width: `${pct(graded)}%` }} />
        <i className={styles.waiting} style={{ width: `${pct(s.waiting)}%` }} />
      </div>
      <span className={styles.chips}>
        {s.waiting > 0 ? (
          <Chip tone="amber">{copy.tally.waiting(s.waiting)}</Chip>
        ) : s.submitted > 0 ? (
          <Chip tone="green">{copy.tally.allGraded}</Chip>
        ) : (
          <Chip tone="plain">{copy.tally.noneYet}</Chip>
        )}
        {s.late > 0 && <Chip tone="red">{copy.tally.late(s.late)}</Chip>}
        {s.not_submitted > 0 && s.submitted > 0 && (
          <Chip tone="plain">{copy.tally.not(s.not_submitted)}</Chip>
        )}
      </span>
    </div>
  )
}
