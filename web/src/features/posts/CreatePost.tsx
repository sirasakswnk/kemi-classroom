import { useQuery } from '@tanstack/react-query'
import { TriangleAlert } from 'lucide-react'
import { Link, useParams, useSearchParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { classroomQuery, teachersQuery } from '../classrooms/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { PostEditor } from './PostEditor'
import type { PostKind } from './postForm'
import styles from './posts.module.css'

// T02 สร้างงาน/ประกาศ (UX_DESIGN ส่วน 9): เลือกชนิด → กรอก → โพสต์ แล้วกลับ T08 แท็บของชนิดนั้น
// K5: ภาคเรียนจบแล้ว (ended) สร้างได้เฉพาะประกาศ; ห้องของภาคเรียนก่อนโพสต์ไม่ได้
// ไฟล์โจทย์/ไฟล์แนบมากับโมดูลอัปโหลด (P3-06) เป็นคีย์ใหม่ในก้อน p_post
export default function CreatePost() {
  const { classId = '' } = useParams()
  const [search] = useSearchParams()
  const { term, adminMode } = useTeacher()
  const classroom = useQuery(classroomQuery(classId))
  const teachers = useQuery(teachersQuery)
  const copy = th.posts.create
  const roomCopy = th.classrooms.room

  const crumbs = (name: string) => [
    { label: th.teacher.overview, to: '/t' },
    { label: name, to: `/t/c/${classId}` },
    { label: copy.crumb },
  ]

  if (classroom.isPending) {
    return (
      <TeacherPage crumbs={crumbs('…')}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  if (classroom.isError || !classroom.data) {
    const error = classroom.isError ? appErrorOf(classroom.error) : null
    return (
      <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.crumb }]}>
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error
              ? `${error.message}${error.ref ? ` (${th.errors.reference(error.ref)})` : ''}`
              : roomCopy.notFoundBody}
          </span>
        </p>
        <Link to="/t" className={styles.ghostLink}>
          {roomCopy.backToOverview}
        </Link>
      </TeacherPage>
    )
  }

  const c = classroom.data
  const oldTerm = !!term && c.term_id !== term.id
  const homeworkAllowed = term?.status === 'active'
  const teacherName = teachers.data?.find((t) => t.id === c.teacher_id)?.display_name ?? ''
  const requested: PostKind = search.get('kind') === 'announcement' ? 'announcement' : 'homework'
  return (
    <TeacherPage crumbs={crumbs(c.name)}>
      <div className={styles.head}>
        <span className={styles.eyebrow}>{copy.eyebrow(c.name)}</span>
        <h1>{copy.title}</h1>
        <p>{copy.intro}</p>
      </div>
      {oldTerm || !term ? (
        <>
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{copy.oldTerm}</span>
          </p>
          <Link to={`/t/c/${c.id}`} className={styles.ghostLink}>
            {copy.backToRoom}
          </Link>
        </>
      ) : (
        <PostEditor
          key={c.id}
          classroom={c}
          teacherName={teacherName}
          adminMode={adminMode}
          mode={{
            kind: 'create',
            initialKind: homeworkAllowed ? requested : 'announcement',
            homeworkAllowed,
          }}
        />
      )}
    </TeacherPage>
  )
}
