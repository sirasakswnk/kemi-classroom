import { useQuery } from '@tanstack/react-query'
import { FilePlus, Megaphone, PenLine, Plus, TriangleAlert } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button } from '../../ui'
import { postsQuery } from './api'
import { TeacherWorkList } from '../review/TeacherWorkList'
import { StudentWorkList } from '../work/StudentWorkList'
import { AnnouncementList } from './PostLists'
import styles from './posts.module.css'

// แท็บ “โพสต์งานของคุณครู” (homework) และ “โพสต์ทั่วไป” (announcement) ของห้อง — ใช้ทั้ง T08 และ S02
// ครูเห็นปุ่มสร้างโพสต์ (ถ้าห้องยังโพสต์ได้); การบ้านของครูแสดงยอดส่ง/รอตรวจและเข้า T03 (P3-09)
export function RoomPosts({
  classroomId,
  kind,
  audience,
  teacherName,
  canCreate = false,
}: {
  classroomId: string
  kind: 'homework' | 'announcement'
  audience: 'teacher' | 'student'
  teacherName: string
  /** ครู: แสดงปุ่มสร้างโพสต์ชนิดนี้ (ภาคเรียนปัจจุบัน และการบ้านต้องยังไม่จบภาคเรียน — K5) */
  canCreate?: boolean
}) {
  const posts = useQuery(postsQuery(classroomId))
  const roomCopy = th.classrooms.room
  const listCopy = th.posts.list
  const homework = kind === 'homework'
  const teacher = audience === 'teacher'
  const newTo = `/t/c/${classroomId}/new${homework ? '' : '?kind=announcement'}`
  const newLabel = homework ? listCopy.newHomework : listCopy.newAnnouncement
  const newIcon = homework ? <Plus aria-hidden="true" /> : <PenLine aria-hidden="true" />

  const header = teacher && (
    <div className={styles.panelHead}>
      <h2>{homework ? roomCopy.workHead : roomCopy.generalHead}</h2>
      {canCreate && (
        <Link to={newTo} className={styles.newLink}>
          {newIcon}
          {newLabel}
        </Link>
      )}
    </div>
  )

  if (posts.isPending) {
    return (
      <>
        {header}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </>
    )
  }
  if (posts.isError) {
    const error = appErrorOf(posts.error)
    return (
      <>
        {header}
        <div className={styles.empty} role="alert">
          <TriangleAlert aria-hidden="true" />
          <b>{listCopy.loadFailed}</b>
          <span>
            {error.message}
            {error.ref && ` (${th.errors.reference(error.ref)})`}
          </span>
          <Button size="sm" variant="soft" onClick={() => void posts.refetch()}>
            {th.teacher.retry}
          </Button>
        </div>
      </>
    )
  }

  const items = posts.data.filter((p) => p.kind === kind)
  if (!items.length) {
    return (
      <>
        {header}
        <div className={styles.empty}>
          {homework ? <FilePlus aria-hidden="true" /> : <Megaphone aria-hidden="true" />}
          {teacher ? (
            <>
              <b>{homework ? roomCopy.workEmptyTitle : roomCopy.generalEmptyTitle}</b>
              <span>{homework ? roomCopy.workEmptyBody : roomCopy.generalEmptyBody}</span>
            </>
          ) : (
            <span>{homework ? th.student.room.workEmpty : th.student.room.generalEmpty}</span>
          )}
        </div>
      </>
    )
  }

  const heading = teacher ? 'h3' : 'h2'
  return (
    <>
      {header}
      {homework ? (
        teacher ? (
          <TeacherWorkList posts={items} classroomId={classroomId} heading={heading} />
        ) : (
          <StudentWorkList classroomId={classroomId} />
        )
      ) : (
        <AnnouncementList
          posts={items}
          teacherName={teacherName}
          heading={heading}
          editable={teacher}
        />
      )}
    </>
  )
}
