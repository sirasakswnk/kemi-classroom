import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Calendar, CalendarX, Lock, Pencil, Sparkles, TriangleAlert } from 'lucide-react'
import { useEffect } from 'react'
import { Link, useParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { thaiDate } from '../../lib/thaiTime'
import { Button, Steps } from '../../ui'
import { CommentThread } from '../comments/CommentThread'
import { gradeQuery } from '../grading/api'
import { postQuery } from '../posts/api'
import { myClassroomsQuery } from '../student/api'
import { AttachmentList } from '../uploads/AttachmentList'
import { submissionStatusQuery } from './api'
import { MyGrade } from './MyGrade'
import { MyWork } from './MyWork'
import { SolutionSection } from './SolutionSection'
import { gradeView, stepStates, when } from './workState'
import page from '../student/student.module.css'
import styles from './work.module.css'

// S03 หน้างานของนักเรียน (UX 6, 13; แบบ v2 sWork): ชื่องาน/เวลา → แถบขั้นตอน → โจทย์และไฟล์ | งานของฉัน
// ตั้งแต่ 960 px แบ่ง 2 คอลัมน์ ซ้ายโจทย์ ขวางานของฉัน (ลำดับใน DOM เดียวกับที่เห็น)
// ลำดับฝั่งขวา: งานของฉัน → คะแนนและความครบถ้วน → ความคิดเห็นส่วนตัว → เฉลย (UX 6)
export default function WorkPage() {
  const { postId = '' } = useParams()
  const post = useQuery(postQuery(postId))
  const status = useQuery(submissionStatusQuery(postId))
  const classes = useQuery(myClassroomsQuery)
  const submissionId = status.data?.submission?.submission_id
  // ผลตรวจ: อ่านผ่าน RLS (เจ้าของงานส่ง) โหลดใหม่ทุกครั้งที่เปิดหน้า เพราะครูตรวจได้ตลอด
  const grade = useQuery({
    ...gradeQuery(submissionId ?? ''),
    enabled: !!submissionId,
    staleTime: 0,
  })
  const queryClient = useQueryClient()
  const copy = th.work
  const statusError = status.isError ? appErrorOf(status.error) : null
  const notMember = statusError?.code === 'not_member'

  useEffect(() => {
    if (notMember) void queryClient.invalidateQueries({ queryKey: ['my-classrooms'] })
  }, [notMember, queryClient])

  const classroomId = post.data?.classroom_id ?? status.data?.classroom_id
  const room = classes.data?.find((c) => c.id === classroomId)
  const back = (
    <Link to={classroomId ? `/c/${classroomId}?tab=work` : '/'} className={page.back}>
      <ArrowLeft aria-hidden="true" />
      {room?.name ?? th.student.room.backHome}
    </Link>
  )

  if (post.isPending || status.isPending) {
    return (
      <main className={page.page}>
        {back}
        <p role="status" className={page.muted}>
          {th.common.loading}
        </p>
      </main>
    )
  }

  const error = statusError ?? (post.isError ? appErrorOf(post.error) : null)
  const missing = !error && (!post.data || !post.data.assignment || !status.data)
  if (error || missing) {
    const notFound = missing || error?.code === 'forbidden'
    return (
      <main className={page.page} data-width="narrow">
        {back}
        <div className={page.empty} role="alert">
          {notMember || notFound ? (
            <Lock aria-hidden="true" />
          ) : (
            <TriangleAlert aria-hidden="true" />
          )}
          <b>{notFound ? copy.notFound : error?.message}</b>
          {!notFound && error?.ref && <span>{th.errors.reference(error.ref)}</span>}
          {notMember || notFound ? (
            <Link to="/" className={page.softLink}>
              {th.student.room.goHome}
            </Link>
          ) : (
            <Button
              size="sm"
              variant="soft"
              onClick={() => {
                void post.refetch()
                void status.refetch()
              }}
            >
              {th.teacher.retry}
            </Button>
          )}
        </div>
      </main>
    )
  }

  const p = post.data!
  const a = p.assignment!
  const s = status.data!
  const closeText =
    s.intake === 'closed' ? copy.closed : a.close_at ? when(a.close_at) : copy.noClose
  const sub = s.submission
  const view = sub ? gradeView(grade.data ?? null, sub.content_revision) : null
  const states = stepStates(s, view)

  return (
    <main className={page.page}>
      {back}
      <header className={styles.head}>
        <span className={styles.eyebrow}>
          {copy.eyebrow(a.full_score, thaiDate(p.published_at))}
        </span>
        <h1>{p.title}</h1>
        <div className={styles.metaGrid}>
          <dl className={styles.metaBox}>
            <dt>
              <Calendar aria-hidden="true" />
              {copy.due}
            </dt>
            <dd>
              {when(s.due_at)}
              <small>{copy.dueRule}</small>
            </dd>
          </dl>
          <dl className={styles.metaBox}>
            <dt>
              <CalendarX aria-hidden="true" />
              {copy.closeAt}
            </dt>
            <dd>{closeText}</dd>
          </dl>
          {a.reward_tokens > 0 && (
            <p className={styles.reward}>
              <Sparkles aria-hidden="true" />
              <span>{copy.reward(a.reward_tokens)}</span>
            </p>
          )}
        </div>
      </header>
      <Steps
        label={copy.stepsLabel}
        steps={copy.steps.map((label, i) => ({ label, state: states[i] }))}
      />
      <div className={styles.layout}>
        <div className={styles.main}>
          <section className={styles.section} aria-labelledby="workProblem">
            <div className={styles.sectionHead}>
              <h2 id="workProblem">{copy.problem}</h2>
            </div>
            {p.body ? (
              <p className={styles.prose}>{p.body}</p>
            ) : (
              p.files.length > 0 && <p className={styles.muted}>{copy.noBody}</p>
            )}
            {p.files.length > 0 && <AttachmentList files={p.files} />}
            {p.content_updated_at && (
              <p className={styles.edited}>
                <Pencil aria-hidden="true" />
                {copy.edited(when(p.content_updated_at))}
              </p>
            )}
          </section>
        </div>
        <div className={styles.side}>
          <MyWork post={p} status={s} />
          {sub && !grade.isPending && !grade.isError && (
            <MyGrade view={view} fullScore={a.full_score} revision={sub.content_revision} />
          )}
          <CommentThread mode="student" assignmentId={p.id} />
          {s.solution_published && <SolutionSection postId={p.id} />}
        </div>
      </div>
    </main>
  )
}
