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

// S01 ชั้นเรียนของฉัน (แบบ v2 sHome): การ์ดห้องที่เข้าแล้ว + ปุ่มเข้าชั้นเรียน
// “ใกล้กำหนดส่ง” มาพร้อมงานในระยะ 3; ห้องที่ถูกเอาออกหายไปเมื่อโหลดรายการใหม่ (RPC my_classrooms)
export default function StudentHome() {
  const { student, notice } = useStudent()
  const term = useQuery(termQuery)
  const classes = useQuery(myClassroomsQuery)
  const [joining, setJoining] = useState(false)
  const headingRef = useRef<HTMLHeadingElement>(null)
  const queryClient = useQueryClient()
  const toast = useToast()
  const list = classes.data ?? []

  return (
    <main className={styles.page} data-width="narrow">
      <div className={styles.greet}>
        <span className={styles.eyebrow}>
          {term.data ? th.student.homeEyebrow(term.data.name, shortDate()) : shortDate()}
        </span>
        <h1>{th.identity.hello(firstName(student.display_name))}</h1>
        <p>{list.length > 0 ? th.student.withClasses : th.identity.noClass}</p>
      </div>
      {notice && (
        <p className={styles.note} data-tone="green" role="status">
          <CircleCheck aria-hidden="true" />
          <span>{notice}</span>
        </p>
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
                    <Chip tone="plain">{th.student.noWorkChip}</Chip>
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
    </main>
  )
}
