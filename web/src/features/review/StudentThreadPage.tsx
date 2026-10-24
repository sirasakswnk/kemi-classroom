import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Info, TriangleAlert } from 'lucide-react'
import { Link, Navigate, useParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Chip } from '../../ui'
import { classroomQuery } from '../classrooms/api'
import { PastTermChip } from '../classrooms/RoomTerm'
import { CommentThread } from '../comments/CommentThread'
import { postQuery } from '../posts/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { submissionListQuery } from './api'
import { rowBadges } from './reviewState'
import styles from './review.module.css'

// หน้าของนักเรียนหนึ่งคนในงาน (T03, UX 9/12): ทางจากแจ้งเตือนความคิดเห็น (T11) และชื่อในรายการสถานะ
// ส่งแล้ว → ไปหน้าตรวจของงานส่งนั้น · ยังไม่ส่ง → แสดงเฉพาะช่องความคิดเห็น และบอกว่ายังไม่ส่งงาน
export default function StudentThreadPage() {
  const { postId = '', studentId = '' } = useParams()
  const post = useQuery(postQuery(postId))
  const list = useQuery(submissionListQuery(postId))
  const classroomId = post.data?.classroom_id ?? list.data?.classroom_id ?? ''
  const classroom = useQuery({ ...classroomQuery(classroomId), enabled: !!classroomId })
  const { adminMode } = useTeacher()
  const copy = th.review.viewer

  const statusTo = `/t/w/${postId}`
  const row = list.data?.rows.find((r) => r.student_id === studentId)
  const crumbs = [
    { label: th.teacher.overview, to: '/t' },
    ...(classroom.data ? [{ label: classroom.data.name, to: `/t/c/${classroomId}?tab=work` }] : []),
    ...(post.data ? [{ label: post.data.title, to: statusTo }] : []),
    { label: row?.display_name ?? copy.crumb },
  ]
  const back = (
    <Link to={statusTo} className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {copy.back}
    </Link>
  )

  if (row?.submission_id) {
    return <Navigate to={`/t/w/${postId}/s/${row.submission_id}`} replace />
  }
  if (list.isPending) {
    return (
      <TeacherPage crumbs={crumbs}>
        {back}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  const error = list.isError ? appErrorOf(list.error) : null
  if (error || !row) {
    return (
      <TeacherPage crumbs={crumbs}>
        <div className={styles.page}>
          {back}
          <div className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {error && error.code !== 'forbidden' ? error.message : copy.studentNotFound}
              {error?.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
          </div>
        </div>
      </TeacherPage>
    )
  }

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
            <PastTermChip termId={classroom.data?.term_id} />
            {rowBadges(row).map((b) => (
              <Chip key={b.label} tone={b.tone}>
                {b.label}
              </Chip>
            ))}
          </span>
        </header>
        <div className={styles.thread}>
          <p className={styles.note}>
            <Info aria-hidden="true" />
            <span>{copy.notSubmitted}</span>
          </p>
          <CommentThread
            mode="teacher"
            assignmentId={postId}
            studentId={row.student_id}
            studentName={row.display_name}
            adminMode={adminMode}
          />
        </div>
      </div>
    </TeacherPage>
  )
}
