import { Info, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { Navigate, useLocation } from 'react-router'
import { th } from '../../copy/th'
import { supabase, toAppError, type AppError } from '../../lib/supabase'
import { FullPageStatus } from '../common/FullPageStatus'
import { BrandLogo, Benzene } from '../common/brand'
import { homeFor } from './account'
import styles from './auth.module.css'
import { GoogleButton } from './GoogleButton'
import { useAuth } from './useAuth'

// A01 เข้าสู่ระบบ — หน้าเดียวสำหรับทุกบทบาท (UX_DESIGN ส่วน 4, แบบ v2 sLogin)
export function LoginPage() {
  const { state } = useAuth()
  const location = useLocation()
  const [busy, setBusy] = useState(false)
  const [startError, setStartError] = useState<AppError | null>(null)
  const failed = (location.state as { failed?: boolean } | null)?.failed === true

  if (state.status === 'loading') return <FullPageStatus />
  if (state.status === 'ready') return <Navigate to={homeFor(state.account.role)} replace />
  // ล็อกอินแล้วแต่สร้างบัญชีไม่สำเร็จ: หน้าแรกแสดงข้อความตาม UX 7.1
  if (state.status === 'error') return <Navigate to="/" replace />

  const notice = state.notice

  const signIn = async () => {
    setBusy(true)
    setStartError(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
        // ให้เลือกบัญชีทุกครั้ง: สลับบัญชีส่วนตัว/โรงเรียนได้
        queryParams: { prompt: 'select_account' },
      },
    })
    // สำเร็จ = เบราว์เซอร์กำลังไปหน้า Google
    if (error) {
      setStartError(toAppError(error))
      setBusy(false)
    }
  }

  return (
    <div className={styles.login}>
      <header className={styles.hero}>
        <Benzene className={styles.benzene} />
        <BrandLogo className={styles.logo} />
        <h1>{th.appName}</h1>
        <p>{th.login.tagline}</p>
      </header>

      <main className={styles.body}>
        {notice && (
          <p className={styles.notePurple}>
            <Info aria-hidden="true" />
            <span>{notice}</span>
          </p>
        )}
        {(failed || startError) && (
          <div className={styles.noteRed} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              <b>{th.login.failedTitle}</b>
              <br />
              {startError ? startError.message : th.login.failedBody}
              {startError?.ref && (
                <small className={styles.ref}> {th.errors.reference(startError.ref)}</small>
              )}
            </span>
          </div>
        )}

        <GoogleButton onClick={signIn} disabled={busy} aria-busy={busy || undefined}>
          {th.login.google}
        </GoogleButton>
        <p className={styles.hint}>{th.login.hint}</p>

        <ol className={styles.how} aria-label={th.login.stepsLabel}>
          {th.login.steps.map((s, i) => (
            <li key={s.title}>
              <span className={styles.howNum} aria-hidden="true">
                {i + 1}
              </span>
              <span>
                <b>{s.title}</b>
                {s.detail && <span>{s.detail}</span>}
              </span>
            </li>
          ))}
        </ol>
      </main>

      <footer className={styles.foot}>{th.login.foot}</footer>
    </div>
  )
}
