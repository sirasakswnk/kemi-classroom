import { CircleCheck, LogOut } from 'lucide-react'
import { useState } from 'react'
import { useAuth } from '../../app/auth/useAuth'
import { FullPageCard, FullPageStatus } from '../../app/common/FullPageStatus'
import { th } from '../../copy/th'
import { Button, Card, useToast } from '../../ui'
import { NamePicker } from './NamePicker'
import styles from './StudentHome.module.css'
import { useMyStudent } from './useMyStudent'

// หน้าแรกนักเรียน: ยังไม่ผูกชื่อ → A02 (แผ่นปิดไม่ได้) บนพื้นหลังต้อนรับ; ผูกแล้ว → หน้าแรกแบบยังไม่มีห้อง (แบบ v2 sWelcome)
// ช่องเข้าชั้นเรียนด้วยรหัสมาใน P2-07
export function StudentHome() {
  const { state: auth, signOut } = useAuth()
  const userId = auth.status === 'ready' ? auth.session.user.id : ''
  const { state, reload, setStudent } = useMyStudent(userId)
  const toast = useToast()
  const [notice, setNotice] = useState<string | null>(null)

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

  if (!state.student) {
    return (
      <>
        <main className={styles.page}>
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
    )
  }

  const first = state.student.display_name.split(/\s+/)[0]
  return (
    <main className={styles.page}>
      <div className={styles.greet}>
        <span className={styles.eyebrow}>{th.identity.doneEyebrow}</span>
        <h1>{th.identity.hello(first)}</h1>
        <p>{th.identity.noClass}</p>
      </div>
      {notice && (
        <p className={styles.notice} role="status">
          <CircleCheck aria-hidden="true" />
          <span>{notice}</span>
        </p>
      )}
      <Card className={styles.account}>
        {email && <p>{th.login.signedInAs(email)}</p>}
        <p className={styles.muted}>{th.home.placeholder}</p>
        <Button variant="ghost" icon={<LogOut />} onClick={signOut}>
          {th.common.signOut}
        </Button>
      </Card>
    </main>
  )
}
