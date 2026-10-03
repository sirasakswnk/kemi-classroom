import { ArrowRight, Lock, Plus, School } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { Card, Chip } from '../../ui'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { ClassBanner } from './ClassBanner'
import styles from './classrooms.module.css'

const today = () =>
  new Intl.DateTimeFormat('th-TH', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'Asia/Bangkok',
  }).format(new Date())

// T01 หน้ารวมห้องครู — ไม่แสดงรหัสชั้นเรียนในหน้านี้ (UX 4); ยอดรอตรวจและแจ้งเตือนมาในระยะ 3–5
export default function TeacherOverview() {
  const { classrooms, displayName, adminMode, term } = useTeacher()

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview }]}>
      <div className={styles.head}>
        <div>
          <span className={styles.eyebrow}>{today()}</span>
          <h1>{adminMode ? th.classrooms.helloAdmin : th.classrooms.hello(displayName)}</h1>
          <p>
            {term?.name} · {th.classrooms.summary(classrooms.length)}
          </p>
        </div>
        <Link to="/t/new-class" className={styles.primaryLink}>
          <Plus aria-hidden="true" />
          {th.classrooms.create.title}
        </Link>
      </div>

      {classrooms.length === 0 ? (
        <div className={styles.empty}>
          <School aria-hidden="true" />
          <b>{th.classrooms.emptyTitle}</b>
          <span>{th.classrooms.emptyBody}</span>
        </div>
      ) : (
        <ul className={styles.cards} aria-label={th.classrooms.listLabel}>
          {classrooms.map((c, i) => (
            <Card as="li" padding="none" key={c.id} className={styles.card}>
              <ClassBanner
                tone={i}
                eyebrow={th.classrooms.students(c.member_count)}
                title={c.name}
              />
              <div className={styles.cardBody}>
                <div>
                  <span className={styles.small}>{th.classrooms.newLabel}</span>
                  <h3>{th.classrooms.noWork}</h3>
                </div>
                <p className={styles.muted}>
                  {c.member_count > 0
                    ? th.classrooms.joined(c.member_count)
                    : th.classrooms.noneJoined}
                </p>
                <div className={styles.cardFoot}>
                  {!c.join_enabled && (
                    <Chip tone="plain" icon={<Lock />}>
                      {th.classrooms.closedChip}
                    </Chip>
                  )}
                  <Link
                    to={`/t/c/${c.id}`}
                    className={styles.softLink}
                    aria-label={th.classrooms.openRoomAria(c.name)}
                  >
                    {th.classrooms.openRoom}
                    <ArrowRight aria-hidden="true" />
                  </Link>
                </div>
              </div>
            </Card>
          ))}
        </ul>
      )}
    </TeacherPage>
  )
}
