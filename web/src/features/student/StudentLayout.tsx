import { useMemo, useState } from 'react'
import { Link, Outlet } from 'react-router'
import { useAuth } from '../../app/auth/useAuth'
import { BrandLogo } from '../../app/common/brand'
import { FullPageCard, FullPageStatus } from '../../app/common/FullPageStatus'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { Button, useToast } from '../../ui'
import { NamePicker } from '../identity/NamePicker'
import { useMyStudent } from '../identity/useMyStudent'
import { StudentContext, type StudentContextValue } from './studentContext'
import styles from './student.module.css'

// โครงหน้านักเรียน: หัวเว็บ (ชื่อเว็บ → หน้าแรก, รูปแทนตัว → S06) + ด่านเลือกชื่อ (A02)
// ทุกหน้านักเรียนรวมลิงก์เชิญ /join/:code ต้องผูกชื่อก่อน — ยังไม่ผูกแสดง A02 ทับพื้นหลังต้อนรับ (UX 4)
export function StudentLayout() {
  const { state: auth, signOut } = useAuth()
  const userId = auth.status === 'ready' ? auth.session.user.id : ''
  const { state, reload, setStudent } = useMyStudent(userId)
  const toast = useToast()
  const [notice, setNotice] = useState<string | null>(null)
  const student = state.status === 'ready' ? state.student : null

  const value = useMemo<StudentContextValue | null>(
    () => (student ? { student, notice, reloadStudent: reload } : null),
    [student, notice, reload],
  )

  if (auth.status !== 'ready' || state.status === 'loading') return <FullPageStatus />
  const email = auth.account.email ?? auth.session.user.email ?? ''

  if (state.status === 'error') {
    const { error } = state
    return (
      <FullPageCard title={th.identity.loadFailed}>
        <p>
          {error.message}
          {error.ref && <small className={styles.ref}> {th.errors.reference(error.ref)}</small>}
        </p>
        <Button onClick={reload}>{th.identity.retry}</Button>
        <Button variant="ghost" onClick={signOut}>
          {th.common.signOut}
        </Button>
      </FullPageCard>
    )
  }

  return (
    <div className={styles.app}>
      <header className={styles.top}>
        <Link to="/" className={styles.brand} aria-label={th.student.homeAria}>
          <BrandLogo />
          <span>{th.appName}</span>
        </Link>
        {value && (
          <Link to="/me" className={styles.avatarBtn} aria-label={th.student.account}>
            {initialOf(value.student.display_name)}
          </Link>
        )}
      </header>
      {value ? (
        <StudentContext value={value}>
          <Outlet />
        </StudentContext>
      ) : (
        <>
          <main className={styles.page} data-width="narrow">
            <div className={styles.greet}>
              <span className={styles.eyebrow}>{th.identity.bgEyebrow}</span>
              <h1>{th.identity.bgTitle}</h1>
              <p>{th.identity.bgBody}</p>
            </div>
            <div className={styles.skel} aria-hidden="true" />
            <div className={styles.skel} data-short="true" aria-hidden="true" />
          </main>
          <NamePicker
            email={email}
            onSwitchAccount={signOut}
            onClaimed={(name) => {
              setStudent({ display_name: name })
              toast(th.identity.claimed(name), { tone: 'success' })
            }}
            onAlreadyBound={() => {
              setNotice(th.errors.already_bound)
              reload()
            }}
          />
        </>
      )}
    </div>
  )
}
