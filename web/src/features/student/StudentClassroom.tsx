import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, FileText, Lock, Megaphone, TriangleAlert } from 'lucide-react'
import { useEffect } from 'react'
import { Link, useParams } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { appErrorOf } from '../../lib/request'
import { useTabParam } from '../../lib/useTabParam'
import { Button, Chip, Tabs } from '../../ui'
import { ClassBanner } from '../classrooms/ClassBanner'
import { classroomViewQuery, myClassroomsQuery } from './api'
import styles from './student.module.css'

const TABS = ['general', 'work', 'members'] as const

// S02 ห้องเรียนของนักเรียน: หัวห้อง + สามแท็บ (งาน/ประกาศมาในระยะ 3, สมาชิกใช้ได้แล้ว)
// ตรวจ membership ทุกครั้งที่โหลด (classroom_view) — ถูกครูเอาออกแล้วเห็นข้อความ not_member (UX 7.1)
export default function StudentClassroom() {
  const { classId = '' } = useParams()
  const view = useQuery(classroomViewQuery(classId))
  const classes = useQuery(myClassroomsQuery)
  const [tab, selectTab] = useTabParam(TABS, 'work')
  const queryClient = useQueryClient()
  const error = view.isError ? appErrorOf(view.error) : null
  const notMember = error?.code === 'not_member'

  // ถูกเอาออก: ให้หน้าแรกโหลดรายการห้องใหม่ (ห้องนี้หายไป)
  useEffect(() => {
    if (notMember) void queryClient.invalidateQueries({ queryKey: ['my-classrooms'] })
  }, [notMember, queryClient])

  const back = (
    <Link to="/" className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {th.student.room.backHome}
    </Link>
  )

  if (view.isPending) {
    return (
      <main className={styles.page}>
        {back}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </main>
    )
  }
  if (error) {
    return (
      <main className={styles.page} data-width="narrow">
        {back}
        <div className={styles.empty} role="alert">
          {notMember ? <Lock aria-hidden="true" /> : <TriangleAlert aria-hidden="true" />}
          <b>{error.message}</b>
          {error.ref && <span>{th.errors.reference(error.ref)}</span>}
          {notMember ? (
            <Link to="/" className={styles.softLink}>
              {th.student.room.goHome}
            </Link>
          ) : (
            <Button size="sm" variant="soft" onClick={() => void view.refetch()}>
              {th.teacher.retry}
            </Button>
          )}
        </div>
      </main>
    )
  }

  const c = view.data
  if (!c) return null
  const tone = Math.max(
    0,
    (classes.data ?? []).findIndex((x) => x.id === c.id),
  )
  const copy = th.student.room
  return (
    <main className={styles.page}>
      {back}
      <section className={styles.hero} aria-label={c.name}>
        <ClassBanner tone={tone} size="hero" level={1} eyebrow={c.term_name} title={c.name}>
          <span className={styles.teacherLine}>
            <span className={styles.bannerAvatar} aria-hidden="true">
              {initialOf(c.teacher_name)}
            </span>
            {[th.student.classMeta(c.teacher_name, c.member_count + 1), c.description]
              .filter(Boolean)
              .join(' · ')}
          </span>
        </ClassBanner>
      </section>
      <Tabs
        label={th.classrooms.room.tabsLabel}
        tabs={TABS.map((key) => ({ key, label: th.classrooms.room.tabs[key] }))}
        selected={tab}
        onSelect={selectTab}
      >
        {tab === 'members' ? (
          <>
            <div className={styles.members}>
              <p className={styles.mGroup}>{copy.teacherGroup}</p>
              <div className={styles.mRow}>
                <span className={styles.mAvatar} aria-hidden="true">
                  {initialOf(c.teacher_name)}
                </span>
                <b className={styles.mName}>{c.teacher_name}</b>
              </div>
              <p className={styles.mGroup}>{copy.studentsGroup(c.members.length)}</p>
              <ul className={styles.memGrid}>
                {c.members.map((m, i) => (
                  <li key={`${i}${m.display_name}`} className={styles.mRow} data-me={m.is_me}>
                    <span className={styles.mNo}>{m.roll_number ?? '–'}</span>
                    <span className={styles.mName}>{m.display_name}</span>
                    {m.is_me && <Chip tone="purple">{copy.me}</Chip>}
                  </li>
                ))}
              </ul>
            </div>
            <p className={styles.muted}>{copy.membersNote}</p>
          </>
        ) : (
          <div className={styles.empty}>
            {tab === 'general' ? <Megaphone aria-hidden="true" /> : <FileText aria-hidden="true" />}
            <span>{tab === 'general' ? copy.generalEmpty : copy.workEmpty}</span>
          </div>
        )}
      </Tabs>
    </main>
  )
}
