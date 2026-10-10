import { useQuery } from '@tanstack/react-query'
import { TriangleAlert } from 'lucide-react'
import { Link, useParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { classroomQuery, teachersQuery } from '../classrooms/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { editablePostQuery } from './api'
import { PostEditor } from './PostEditor'
import styles from './posts.module.css'

// T02 โหมดแก้ไข (N2) ที่ /t/w/:postId/edit — UX_DESIGN ส่วน 9 [ยืนยัน N2]
// ทางเข้าตอนนี้: ปุ่มบนการ์ดใน T08 (ประกาศ = ถาวร, การบ้าน = ชั่วคราวจนมีการ์ดโจทย์ของ T03 ใน P3-09)
// ไม่จำกัดตามสถานะภาคเรียน (N2: หลังจบภาคเรียนครูยังแก้ได้)
export default function EditPost() {
  const { postId = '' } = useParams()
  const { adminMode } = useTeacher()
  const post = useQuery(editablePostQuery(postId))
  const classroomId = post.data?.classroom_id ?? ''
  const classroom = useQuery({ ...classroomQuery(classroomId), enabled: !!classroomId })
  const teachers = useQuery(teachersQuery)
  const copy = th.posts.edit

  const crumbs = (name: string) => [
    { label: th.teacher.overview, to: '/t' },
    ...(classroomId ? [{ label: name, to: `/t/c/${classroomId}` }] : []),
    { label: copy.crumb },
  ]

  if (post.isPending || (post.data && classroom.isPending)) {
    return (
      <TeacherPage crumbs={crumbs('…')}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  const loadError = post.isError
    ? appErrorOf(post.error)
    : classroom.isError
      ? appErrorOf(classroom.error)
      : null
  if (loadError || !post.data || !classroom.data) {
    return (
      <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.crumb }]}>
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {loadError
              ? `${loadError.message}${loadError.ref ? ` (${th.errors.reference(loadError.ref)})` : ''}`
              : copy.notFound}
          </span>
        </p>
        <Link to="/t" className={styles.ghostLink}>
          {th.classrooms.room.backToOverview}
        </Link>
      </TeacherPage>
    )
  }

  const p = post.data
  const c = classroom.data
  const teacherName = teachers.data?.find((t) => t.id === c.teacher_id)?.display_name ?? ''
  return (
    <TeacherPage crumbs={crumbs(c.name)}>
      <div className={styles.head}>
        <span className={styles.eyebrow}>{copy.eyebrow[p.kind](c.name)}</span>
        <h1>{p.title}</h1>
        <p>{copy.intro[p.kind]}</p>
      </div>
      <PostEditor
        key={p.id}
        classroom={c}
        teacherName={teacherName}
        adminMode={adminMode}
        mode={{ kind: 'edit', post: p, reload: async () => (await post.refetch()).data }}
      />
    </TeacherPage>
  )
}
