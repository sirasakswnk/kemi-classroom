import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, ChevronRight, CircleUserRound, LogOut } from 'lucide-react'
import { Link } from 'react-router'
import { useAuth } from '../../app/auth/useAuth'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { Button, Chip } from '../../ui'
import { termQuery } from '../classrooms/api'
import { classTone } from '../classrooms/tone'
import { myClassroomsQuery, myProfileQuery } from './api'
import { useStudent } from './studentContext'
import styles from './student.module.css'

// S06 บัญชีของฉัน (UX 3, แบบ v2 sProfile): ชื่อ เลขที่ เลขประจำตัวจากรายชื่อครู (แก้เองไม่ได้) ชั้นเรียน
// บัญชี Google และออกจากระบบ — ยอดโทเคนและตู้สะสมเติมในระยะ 5 (TECHNICAL_BUILD_PLAN 6)
export default function MyAccount() {
  const { student } = useStudent()
  const { state, signOut } = useAuth()
  const profile = useQuery(myProfileQuery)
  const term = useQuery(termQuery)
  const classes = useQuery(myClassroomsQuery)
  const email =
    state.status === 'ready' ? (state.account.email ?? state.session.user.email ?? '') : ''
  const entry = profile.data?.roster_entries.find((e) => e.term_id === term.data?.id)
  const list = classes.data ?? []
  const copy = th.student.me

  return (
    <main className={styles.page} data-width="narrow">
      <Link to="/" className={styles.back}>
        <ArrowLeft aria-hidden="true" />
        {copy.backHome}
      </Link>
      <section className={styles.profile} aria-labelledby="meTitle">
        <span className={styles.avatarXl} aria-hidden="true">
          {initialOf(student.display_name)}
        </span>
        <h1 id="meTitle">{profile.data?.display_name ?? student.display_name}</h1>
        <div className={styles.chips}>
          {entry && <Chip tone="purple">{copy.place(entry.group_name, entry.roll_number)}</Chip>}
          {profile.data && (
            <Chip tone="plain">
              {copy.code} <span className="num">{profile.data.student_code}</span>
            </Chip>
          )}
        </div>
        <p className={styles.hint}>{copy.fromRoster}</p>
      </section>

      <section className={styles.section} aria-labelledby="meClasses">
        <div className={styles.sectionHead}>
          <h2 id="meClasses">{copy.classes}</h2>
        </div>
        {list.length === 0 ? (
          <p className={styles.muted}>{classes.isPending ? th.common.loading : copy.noClasses}</p>
        ) : (
          <ul className={styles.rowList}>
            {list.map((c, i) => (
              <li key={c.id}>
                <Link to={`/c/${c.id}`} className={styles.rowLink}>
                  <span className={styles.dot} data-tone={classTone(i)} aria-hidden="true" />
                  <span className={styles.rowName}>{c.name}</span>
                  <span className={styles.muted}>{c.teacher_name}</span>
                  <ChevronRight aria-hidden="true" />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className={styles.section} aria-labelledby="meAccount">
        <div className={styles.sectionHead}>
          <h2 id="meAccount">{copy.accountSection}</h2>
        </div>
        <div className={styles.acct}>
          <CircleUserRound aria-hidden="true" />
          <span>
            <b>{email}</b>
            <span>{copy.google}</span>
          </span>
        </div>
        <Button variant="ghost" block icon={<LogOut />} onClick={signOut}>
          {th.common.signOut}
        </Button>
      </section>
    </main>
  )
}
