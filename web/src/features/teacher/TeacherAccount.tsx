import { ChevronRight, CircleUserRound, LogOut, ShieldCheck } from 'lucide-react'
import { Link } from 'react-router'
import { useAuth } from '../../app/auth/useAuth'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { Button, Chip } from '../../ui'
import { classTone } from '../classrooms/tone'
import { TeacherPage } from './TeacherLayout'
import { useTeacher } from './teacherContext'
import styles from './TeacherAccount.module.css'

// T12 บัญชีของฉัน (แบบ v2 tAccount): ชื่อ บทบาท บัญชี Google ออกจากระบบ และชั้นเรียนที่ดูแล
export default function TeacherAccount() {
  const { displayName, adminMode, term, classrooms, account } = useTeacher()
  const { state, signOut } = useAuth()
  const email = account.email ?? (state.status === 'ready' ? (state.session.user.email ?? '') : '')
  const copy = th.teacherAccount

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.title }]}>
      <div className={styles.head}>
        <h1>{copy.title}</h1>
        <p>{copy.intro}</p>
      </div>
      <div className={styles.grid}>
        <section className={styles.profile} aria-label={displayName}>
          <span className={styles.avatar} aria-hidden="true">
            {initialOf(displayName)}
          </span>
          <h2>{displayName}</h2>
          <div className={styles.chips}>
            <Chip tone="purple" icon={<ShieldCheck />}>
              {adminMode ? copy.roleAdmin : copy.roleTeacher}
            </Chip>
            {term && <Chip tone="plain">{term.name}</Chip>}
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
          {/* UX 9: ไฟล์แจ้งสัญญาอนุญาต (LGPL-3.0 ของ libheif-js) สร้างตอน build */}
          <a href="/third-party-licenses.txt" className={styles.licenses}>
            {th.licenses}
          </a>
        </section>
        <section className={styles.panel} aria-labelledby="t12Classes">
          <h2 id="t12Classes">{copy.classesTitle}</h2>
          {classrooms.length === 0 ? (
            <p className={styles.hint}>{copy.noClasses}</p>
          ) : (
            <ul className={styles.list}>
              {classrooms.map((c, i) => (
                <li key={c.id}>
                  <Link to={`/t/c/${c.id}`} className={styles.row}>
                    <span className={styles.dot} data-tone={classTone(i)} aria-hidden="true" />
                    <span className={styles.rowText}>
                      <b>{c.name}</b>
                      <span>{copy.classMeta(c.member_count, !c.join_enabled)}</span>
                    </span>
                    <ChevronRight aria-hidden="true" />
                  </Link>
                </li>
              ))}
            </ul>
          )}
          <p className={styles.hint}>{copy.changeHint}</p>
        </section>
      </div>
    </TeacherPage>
  )
}
