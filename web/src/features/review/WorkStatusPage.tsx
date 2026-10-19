import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft,
  BookOpenCheck,
  ChevronLeft,
  ChevronRight,
  ClipboardCheck,
  Inbox,
  CalendarPlus,
  Lock,
  LockOpen,
  Trash2,
  TriangleAlert,
} from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip } from '../../ui'
import { classroomQuery } from '../classrooms/api'
import { postQuery } from '../posts/api'
import { DeletePostDialog } from '../posts/DeletePostDialog'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { submissionListQuery } from './api'
import { solutionQuery } from './assignmentApi'
import { CloseDialog } from './CloseDialog'
import { DueDialog } from './DueDialog'
import { SolutionDialog } from './SolutionDialog'
import { ProblemCard } from './ProblemCard'
import {
  countRows,
  filterRows,
  paginate,
  parseFilter,
  phaseBadge,
  rowBadges,
  STATUS_FILTERS,
  type StatusFilter,
} from './reviewState'
import styles from './review.module.css'

// T03 สถานะการส่งงาน (UX 9 [ยืนยันเพิ่มใน HTML ครู]; แบบ v2 tStatus): หัวหน้า (ชื่องาน กำหนดส่ง สถานะรับงาน) → การ์ดโจทย์และไฟล์
// → สรุปยอด → ตัวกรอง ทั้งหมด/ส่งแล้ว/ยังไม่ส่ง → ตาราง 15 คนต่อหน้า (เลขที่ ชื่อ สถานะ เวลาส่ง ป้ายส่งช้า/ออกจากห้องแล้ว)
// ตัวกรองและหน้าอยู่ใน URL (?filter=&page=) — กลับจากตัวดูไฟล์ได้หน้าเดิม
// ปุ่มหัวหน้า (แบบ v2 tStatus .actions): เปิดรับอยู่ = เปลี่ยนกำหนดส่ง · ปิดรับงาน · เตรียมเฉลย; ปิดแล้ว = เปลี่ยนกำหนดส่ง ·
// เปิดรับอีกครั้ง (ก่อนเผยแพร่เฉลย) · เผยแพร่เฉลย/ดูเฉลย; ช่วงรับหลังเฉลย = ปิดรับงานหลังเฉลย · ดูเฉลย — หน้าต่าง M1–M3 (P4-05)
export default function WorkStatusPage() {
  const { postId = '' } = useParams()
  const [params, setParams] = useSearchParams()
  const post = useQuery(postQuery(postId))
  const list = useQuery(submissionListQuery(postId))
  const classroomId = post.data?.classroom_id ?? list.data?.classroom_id ?? ''
  const classroom = useQuery({ ...classroomQuery(classroomId), enabled: !!classroomId })
  const [now] = useState(() => Date.now())
  const solution = useQuery(solutionQuery(postId))
  const { adminMode } = useTeacher()
  const [dialog, setDialog] = useState<'due' | 'close' | 'solution' | 'delete' | null>(null)
  const navigate = useNavigate()
  const copy = th.review

  const roomTo = classroomId ? `/t/c/${classroomId}?tab=work` : '/t'
  const crumbs = (title: string) => [
    { label: th.teacher.overview, to: '/t' },
    ...(classroom.data ? [{ label: classroom.data.name, to: roomTo }] : []),
    { label: title },
  ]
  const back = (
    <Link to={roomTo} className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {copy.backToRoom}
    </Link>
  )

  if (post.isPending || list.isPending) {
    return (
      <TeacherPage crumbs={crumbs('…')}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  const error = list.isError ? appErrorOf(list.error) : post.isError ? appErrorOf(post.error) : null
  const p = post.data
  if (error || !p || !p.assignment || !list.data) {
    const notFound = !error || error.code === 'forbidden'
    return (
      <TeacherPage crumbs={crumbs(copy.loadFailed)}>
        {back}
        <div className={styles.error} role="alert">
          {notFound ? <Lock aria-hidden="true" /> : <TriangleAlert aria-hidden="true" />}
          <span>
            {notFound ? copy.notFound : `${copy.loadFailed} ${error?.message ?? ''}`}
            {!notFound && error?.ref && ` (${th.errors.reference(error.ref)})`}
          </span>
          {!notFound && (
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                void post.refetch()
                void list.refetch()
              }}
            >
              {th.teacher.retry}
            </Button>
          )}
        </div>
      </TeacherPage>
    )
  }

  const a = p.assignment
  const data = list.data
  const counts = countRows(data.rows)
  const phase = phaseBadge(data.intake, a.due_at, now)
  const filter = parseFilter(params.get('filter'))
  const filtered = filterRows(data.rows, filter)
  const view = paginate(filtered, Number(params.get('page') ?? '1'))
  const setView = (next: { filter?: StatusFilter; page?: number }) =>
    setParams(
      (prev) => {
        const q = new URLSearchParams(prev)
        if (next.filter) q.set('filter', next.filter)
        q.set('page', String(next.page ?? 1))
        return q
      },
      { replace: true },
    )
  const act = th.workActions
  const hasDraft = !!solution.data && !solution.data.publishedAt
  const backSearch = `?filter=${filter}&page=${view.page}`
  const filterCount: Record<StatusFilter, number> = {
    all: counts.total,
    sub: counts.submitted,
    not: counts.not,
  }

  return (
    <TeacherPage crumbs={crumbs(p.title)}>
      <div className={styles.page}>
        {back}
        <header className={styles.head}>
          <span className={styles.eyebrow}>{copy.eyebrow(a.full_score, a.reward_tokens)}</span>
          <h1>{p.title}</h1>
          <p>{copy.due(`${thaiDate(a.due_at)} · ${thaiTime(a.due_at)} น.`)}</p>
          <span className={styles.chips}>
            <Chip tone={phase.tone}>{phase.label}</Chip>
            {a.close_at && data.intake !== 'closed' && (
              <Chip tone="plain" icon={<Lock />}>
                {copy.phase.closeAt(`${thaiDate(a.close_at)} ${thaiTime(a.close_at)} น.`)}
              </Chip>
            )}
            {data.solution_published && (
              <Chip tone="green" icon={<BookOpenCheck />}>
                {copy.solutionPublished}
              </Chip>
            )}
          </span>
          <div className={styles.actions}>
            <Button variant="ghost" icon={<CalendarPlus />} onClick={() => setDialog('due')}>
              {act.changeDue}
            </Button>
            {data.intake === 'open' && (
              <Button variant="ghost" icon={<Lock />} onClick={() => setDialog('close')}>
                {act.close}
              </Button>
            )}
            {data.intake === 'closed' && !data.solution_published && (
              <Button variant="ghost" icon={<LockOpen />} onClick={() => setDialog('close')}>
                {act.reopen}
              </Button>
            )}
            {data.intake === 'after_solution' && (
              <Button variant="ghost" icon={<Lock />} onClick={() => setDialog('close')}>
                {act.closeAfter}
              </Button>
            )}
            <Button
              variant={data.intake === 'closed' && !data.solution_published ? 'primary' : 'ghost'}
              icon={<BookOpenCheck />}
              onClick={() => setDialog('solution')}
            >
              {data.solution_published
                ? act.viewSolution
                : data.intake === 'closed'
                  ? hasDraft
                    ? act.publishPrepared
                    : act.publish
                  : hasDraft
                    ? act.prepared
                    : act.prepare}
            </Button>
            <Button
              variant="ghost"
              icon={<Trash2 />}
              className={styles.dangerAction}
              onClick={() => setDialog('delete')}
            >
              {th.deletePost.open}
            </Button>
          </div>
        </header>
        {dialog === 'due' && (
          <DueDialog
            open
            onClose={() => setDialog(null)}
            postId={postId}
            dueAt={a.due_at}
            adminMode={adminMode}
          />
        )}
        {dialog === 'close' && (
          <CloseDialog
            open
            onClose={() => setDialog(null)}
            postId={postId}
            intake={data.intake}
            dueAt={a.due_at}
            closeAt={a.close_at}
            solutionPublished={data.solution_published}
            acceptAfterSolution={a.accept_after_solution}
            notSubmitted={counts.not}
            waiting={counts.waiting}
            adminMode={adminMode}
          />
        )}
        {dialog === 'delete' && (
          <DeletePostDialog
            open
            onClose={() => setDialog(null)}
            postId={postId}
            adminMode={adminMode}
            onDeleted={() => void navigate(roomTo, { replace: true })}
          />
        )}
        <SolutionDialog
          open={dialog === 'solution'}
          onClose={() => setDialog(null)}
          postId={postId}
          classroomId={p.classroom_id}
          intake={data.intake}
          acceptAfterSolution={a.accept_after_solution}
          adminMode={adminMode}
          onGoClose={() => setDialog('close')}
        />

        <ProblemCard post={p} />

        <div className={styles.summary}>
          <div className={`${styles.stat} ${styles.sumMain}`}>
            <span>{copy.summarySubmitted(counts.submitted, counts.total)}</span>
            <b>
              {counts.submitted}/{counts.total}
            </b>
            <small>{copy.summaryWaiting(counts.waiting)}</small>
          </div>
          <div className={styles.stat}>
            <span>{copy.statWaiting}</span>
            <b>{counts.waiting}</b>
            <small>{copy.people}</small>
          </div>
          <div className={styles.stat}>
            <span>{copy.statNot}</span>
            <b>{counts.not}</b>
            <small>{copy.people}</small>
          </div>
          <div className={styles.stat}>
            <span>{copy.statLate}</span>
            <b>{counts.late}</b>
            <small>{copy.latePct(a.late_penalty_pct)}</small>
          </div>
        </div>

        <section className={styles.card} aria-label={copy.tableAria}>
          <div className={styles.tblBar}>
            <div className={styles.seg} role="group" aria-label={copy.filtersAria}>
              {STATUS_FILTERS.map((f) => (
                <button
                  key={f}
                  type="button"
                  aria-pressed={filter === f}
                  onClick={() => setView({ filter: f, page: 1 })}
                >
                  {copy.filters[f]}
                  <span className={styles.n}>{filterCount[f]}</span>
                </button>
              ))}
            </div>
            <span className={styles.range}>
              {copy.range(
                filtered.length ? view.from + 1 : 0,
                view.from + view.rows.length,
                filtered.length,
              )}
            </span>
          </div>
          {data.rows.length === 0 ? (
            <div className={styles.empty}>
              <Inbox aria-hidden="true" />
              <span>{copy.empty}</span>
            </div>
          ) : view.rows.length === 0 ? (
            <div className={styles.empty}>
              <Inbox aria-hidden="true" />
              <span>{copy.noneInFilter}</span>
            </div>
          ) : (
            <ul className={styles.rows}>
              <li className={`${styles.srow} ${styles.headRow}`} aria-hidden="true">
                <span className={styles.no}>{copy.cols.no}</span>
                <span className={styles.nm}>{copy.cols.name}</span>
                <span className={styles.st}>{copy.cols.status}</span>
                <span className={styles.tm}>{copy.cols.time}</span>
                <span className={styles.ac}>{copy.cols.act}</span>
              </li>
              {view.rows.map((r) => (
                <li key={r.student_id} className={styles.srow}>
                  <span className={styles.no}>{r.roll_number ?? '–'}</span>
                  <span className={styles.nm}>{r.display_name}</span>
                  <span className={styles.st}>
                    {rowBadges(r).map((b) => (
                      <Chip key={b.label} tone={b.tone}>
                        {b.label}
                      </Chip>
                    ))}
                  </span>
                  <span className={styles.tm}>
                    {r.last_submitted_at
                      ? `${thaiDate(r.last_submitted_at)} ${thaiTime(r.last_submitted_at)} น.`
                      : '—'}
                  </span>
                  <span className={styles.ac}>
                    {r.submission_id ? (
                      <Link
                        to={`/t/w/${p.id}/s/${r.submission_id}`}
                        state={{ back: backSearch }}
                        className={styles.link}
                        aria-label={copy.reviewAria(r.display_name)}
                      >
                        <ClipboardCheck aria-hidden="true" />
                        {copy.review}
                      </Link>
                    ) : (
                      <span className={styles.noFile}>{copy.noFile}</span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {view.pages > 1 && (
            <nav className={styles.pager} aria-label={copy.pagerAria}>
              <span>{copy.pager(view.page, view.pages)}</span>
              <div className={styles.pg}>
                <button
                  type="button"
                  disabled={view.page <= 1}
                  aria-label={copy.prev}
                  onClick={() => setView({ page: view.page - 1 })}
                >
                  <ChevronLeft aria-hidden="true" />
                </button>
                {Array.from({ length: view.pages }, (_, k) => (
                  <button
                    key={k}
                    type="button"
                    aria-current={view.page === k + 1}
                    aria-label={copy.pageAria(k + 1)}
                    onClick={() => setView({ page: k + 1 })}
                  >
                    {k + 1}
                  </button>
                ))}
                <button
                  type="button"
                  disabled={view.page >= view.pages}
                  aria-label={copy.next}
                  onClick={() => setView({ page: view.page + 1 })}
                >
                  <ChevronRight aria-hidden="true" />
                </button>
              </div>
            </nav>
          )}
        </section>
      </div>
    </TeacherPage>
  )
}
