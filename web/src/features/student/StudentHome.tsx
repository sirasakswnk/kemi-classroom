import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowRight, CircleCheck, KeyRound, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { appErrorOf } from '../../lib/request'
import { Button, Chip, useToast } from '../../ui'
import { ClassBanner } from '../classrooms/ClassBanner'
import { termQuery } from '../classrooms/api'
import { myWorkQuery } from '../work/api'
import { DueSoon } from '../work/DueSoon'
import { dueSoon, isPending } from '../work/workState'
import work from '../work/work.module.css'
import { myClassroomsQuery } from './api'
import { firstName } from './names'
import { JoinClass } from './JoinClass'
import { useStudent } from './studentContext'
import styles from './student.module.css'

const shortDate = () =>
  new Intl.DateTimeFormat('th-TH', {
    weekday: 'long',
    day: 'numeric',
    month: 'short',
    timeZone: 'Asia/Bangkok',
  }).format(new Date())

// S01 ชั้นเรียนของฉัน (แบบ v2 sHome): “ใกล้กำหนดส่ง” (งานที่ยังต้องส่งจากทุกห้อง → S03) + การ์ดห้อง + ปุ่มเข้าชั้นเรียน
// ตั้งแต่ 960 px แบ่ง 2 คอลัมน์ “ใกล้กำหนดส่ง | ชั้นเรียนของฉัน” (UX 13); ห้องที่ถูกเอาออกหายไปเมื่อโหลดรายการใหม่
export default function StudentHome() {
  const { student, notice } = useStudent()
  const term = useQuery(termQuery)
  const classes = useQuery(myClassroomsQuery)
  const myWork = useQuery(myWorkQuery(null))
  const [now] = useState(() => Date.now())
  const [joining, setJoining] = useState(false)
  const headingRef = useRef<HTMLHeadingElement>(null)
  const queryClient = useQueryClient()
  const toast = useToast()
  const list = classes.data ?? []
  const workRows = myWork.data ?? []
  const due = dueSoon(workRows)
  const pendingIn = (classId: string) =>
    workRows.filter((r) => r.classroom_id === classId && isPending(r)).length
  const hasWork = (classId: string) => workRows.some((r) => r.classroom_id === classId)

  return (
    <main className={styles.page} data-width={list.length === 0 ? 'narrow' : undefined}>
      <div className={styles.greet}>
        <span className={styles.eyebrow}>
          {term.data ? th.student.homeEyebrow(term.data.name, shortDate()) : shortDate()}
        </span>
        <h1>{th.identity.hello(firstName(student.display_name))}</h1>
        <p>
          {list.length === 0
            ? th.identity.noClass
            : due.length > 0
              ? th.work.pendingGreeting(workRows.filter(isPending).length)
              : myWork.data && workRows.length > 0
                ? th.work.allSent
                : th.student.withClasses}
        </p>
      </div>
      {notice && (
        <p className={styles.note} data-tone="green" role="status">
          <CircleCheck aria-hidden="true" />
          <span>{notice}</span>
        </p>
      )}
      <div className={work.homeCols} data-single={list.length === 0 || undefined}>
        {list.length > 0 && (
          <section className={styles.section} aria-labelledby="dueTitle">
            <div className={styles.sectionHead}>
              <h2 id="dueTitle">{th.work.dueSoon}</h2>
            </div>
            {myWork.isPending ? (
              <p role="status" className={styles.muted}>
                {th.common.loading}
              </p>
            ) : myWork.isError ? (
              <div className={styles.note} data-tone="red" role="alert">
                <TriangleAlert aria-hidden="true" />
                <span>{appErrorOf(myWork.error).message}</span>
                <Button size="sm" variant="ghost" onClick={() => void myWork.refetch()}>
                  {th.teacher.retry}
                </Button>
              </div>
            ) : (
              <DueSoon rows={due} now={now} />
            )}
          </section>
        )}
        <section className={styles.section} aria-labelledby="myClassesTitle">
          <div className={styles.sectionHead}>
            <h2 id="myClassesTitle" ref={headingRef} tabIndex={-1}>
              {th.student.myClasses}
            </h2>
          </div>
          {classes.isPending && (
            <p role="status" className={styles.muted}>
              {th.common.loading}
            </p>
          )}
          {classes.isError && (
            <div className={styles.note} data-tone="red" role="alert">
              <TriangleAlert aria-hidden="true" />
              <span>{appErrorOf(classes.error).message}</span>
              <Button size="sm" variant="ghost" onClick={() => void classes.refetch()}>
                {th.teacher.retry}
              </Button>
            </div>
          )}
          {list.length > 0 && (
            <ul className={styles.classList}>
              {list.map((c, i) => (
                <li key={c.id}>
                  <Link to={`/c/${c.id}`} className={styles.classCard}>
                    <ClassBanner tone={i} eyebrow={term.data?.name ?? ''} title={c.name}>
                      <span className={styles.teacherLine}>
                        <span className={styles.bannerAvatar} aria-hidden="true">
                          {initialOf(c.teacher_name)}
                        </span>
                        {th.student.classMeta(c.teacher_name, c.member_count + 1)}
                      </span>
                    </ClassBanner>
                    <span className={styles.classFoot}>
                      {pendingIn(c.id) > 0 ? (
                        <Chip tone="amber">{th.work.pendingChip(pendingIn(c.id))}</Chip>
                      ) : (
                        <Chip tone="plain">
                          {hasWork(c.id) ? th.work.allSent : th.student.noWorkChip}
                        </Chip>
                      )}
                      <ArrowRight aria-hidden="true" className={styles.go} />
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
          {joining ? (
            <JoinClass
              termName={term.data?.name ?? ''}
              onCancel={() => setJoining(false)}
              onJoined={(c) => {
                setJoining(false)
                toast(th.student.join.joined(c.name), { tone: 'success' })
                void queryClient.invalidateQueries({ queryKey: ['my-classrooms'] })
                headingRef.current?.focus()
              }}
            />
          ) : (
            <button type="button" className={styles.joinCard} onClick={() => setJoining(true)}>
              <span className={styles.joinIcon} aria-hidden="true">
                <KeyRound />
              </span>
              <span>
                <b>{th.student.join.title}</b>
                <span>{th.student.join.cardHint}</span>
              </span>
            </button>
          )}
        </section>
      </div>
    </main>
  )
}
