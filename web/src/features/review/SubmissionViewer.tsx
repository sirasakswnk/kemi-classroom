import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  FileText,
  Image as ImageIcon,
  Info,
  TriangleAlert,
} from 'lucide-react'
import { useState } from 'react'
import { Link, useLocation, useParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip } from '../../ui'
import { classroomQuery } from '../classrooms/api'
import { GradePanel } from '../grading/GradePanel'
import { postQuery } from '../posts/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { AttachmentList } from '../uploads/AttachmentList'
import { submissionFilesQuery, submissionListQuery } from './api'
import { ImagePane, PdfPane } from './FilePanes'
import { isImage, rowBadges } from './reviewState'
import styles from './review.module.css'

// หน้าตรวจ T03: ไฟล์งานส่งของนักเรียนหนึ่งคนทีละไฟล์ (P3-09) — ตัวดูรูป/PDF ซูม หมุน เปลี่ยนหน้าอยู่ใน FilePanes (P4-04b/c)
// โหลดเฉพาะไฟล์ที่เปิดอยู่ รายการไฟล์แสดงชื่อไฟล์ไม่มีรูปย่อ (TECHNICAL_DESIGN 9.3); รวม PDF ดาวน์โหลดมากับ P4-08
// แผงผลตรวจ (P4-04a) อยู่ข้างตัวดู — จอคอมแบ่งภาพราวสองในสาม กับแผงหนึ่งในสาม (UX 9)
// กลับไปรายชื่อได้ตัวกรองและหน้าเดิม (state.back จาก T03)
export default function SubmissionViewer() {
  const { postId = '', submissionId = '' } = useParams()
  const location = useLocation()
  const backSearch = (location.state as { back?: string } | null)?.back ?? ''
  const post = useQuery(postQuery(postId))
  const list = useQuery(submissionListQuery(postId))
  const files = useQuery(submissionFilesQuery(submissionId))
  const classroomId = post.data?.classroom_id ?? list.data?.classroom_id ?? ''
  const classroom = useQuery({ ...classroomQuery(classroomId), enabled: !!classroomId })
  const [index, setIndex] = useState(0)
  const { adminMode } = useTeacher()
  const copy = th.review.viewer

  const statusTo = `/t/w/${postId}${backSearch}`
  const row = list.data?.rows.find((r) => r.submission_id === submissionId)
  const crumbs = [
    { label: th.teacher.overview, to: '/t' },
    ...(classroom.data ? [{ label: classroom.data.name, to: `/t/c/${classroomId}?tab=work` }] : []),
    ...(post.data ? [{ label: post.data.title, to: statusTo }] : []),
    { label: copy.crumb },
  ]
  const back = (
    <Link to={statusTo} className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {copy.back}
    </Link>
  )

  if (list.isPending || files.isPending) {
    return (
      <TeacherPage crumbs={crumbs}>
        {back}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  const error = list.isError
    ? appErrorOf(list.error)
    : files.isError
      ? appErrorOf(files.error)
      : null
  if (error || !row) {
    return (
      <TeacherPage crumbs={crumbs}>
        <div className={styles.page}>
          {back}
          <div className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {error && error.code !== 'forbidden' ? error.message : copy.notFound}
              {error?.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
          </div>
        </div>
      </TeacherPage>
    )
  }

  const all = files.data ?? []
  const current = all[Math.min(index, Math.max(0, all.length - 1))]
  const at = Math.min(index, Math.max(0, all.length - 1))

  return (
    <TeacherPage crumbs={crumbs}>
      <div className={styles.page}>
        {back}
        <header className={styles.head}>
          <span className={styles.eyebrow}>{post.data?.title}</span>
          <h1>
            {row.roll_number != null ? `${row.roll_number} · ` : ''}
            {row.display_name}
          </h1>
          <span className={styles.chips}>
            {rowBadges(row).map((b) => (
              <Chip key={b.label} tone={b.tone}>
                {b.label}
              </Chip>
            ))}
          </span>
          {row.last_submitted_at && (
            <p className={styles.muted}>
              {copy.submittedAt(
                `${thaiDate(row.last_submitted_at)} ${thaiTime(row.last_submitted_at)} น.`,
              )}{' '}
              · {copy.revision(row.content_revision ?? 1)}
            </p>
          )}
        </header>

        {!current ? (
          <div className={styles.viewer}>
            <div className={styles.empty}>
              <Info aria-hidden="true" />
              <span>{copy.noFiles}</span>
            </div>
            <aside className={styles.side}>
              <GradePanel
                postId={postId}
                row={{ ...row, submission_id: submissionId }}
                adminMode={adminMode}
              />
            </aside>
          </div>
        ) : (
          <div className={styles.viewer}>
            <div className={styles.page}>
              <div className={styles.nav}>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<ChevronLeft />}
                  disabled={at <= 0}
                  onClick={() => setIndex(at - 1)}
                >
                  {copy.prevFile}
                </Button>
                <span aria-live="polite">{copy.fileOf(at + 1, all.length)}</span>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<ChevronRight />}
                  disabled={at >= all.length - 1}
                  onClick={() => setIndex(at + 1)}
                >
                  {copy.nextFile}
                </Button>
              </div>
              <div className={styles.stage}>
                {isImage(current.content_type) ? (
                  <ImagePane key={current.asset_id} file={current} owner={row.display_name} />
                ) : (
                  <PdfPane key={current.asset_id} file={current} owner={row.display_name} />
                )}
              </div>
            </div>
            <aside className={styles.side}>
              <ul className={styles.files} aria-label={copy.filesAria}>
                {all.map((f, i) => (
                  <li key={f.asset_id}>
                    <button
                      type="button"
                      className={styles.fileBtn}
                      aria-current={i === at}
                      onClick={() => setIndex(i)}
                    >
                      {isImage(f.content_type) ? (
                        <ImageIcon aria-hidden="true" />
                      ) : (
                        <FileText aria-hidden="true" />
                      )}
                      <span>
                        {i + 1}. {f.file_name}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
              <AttachmentList files={[current]} />
              <GradePanel
                postId={postId}
                row={{ ...row, submission_id: submissionId }}
                adminMode={adminMode}
              />
            </aside>
          </div>
        )}
      </div>
    </TeacherPage>
  )
}
