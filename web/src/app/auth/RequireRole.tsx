import { TriangleAlert } from 'lucide-react'
import { useEffect, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router'
import { th } from '../../copy/th'
import { rememberNextPath } from '../../lib/redirect'
import { Button } from '../../ui'
import { FullPageCard, FullPageStatus } from '../common/FullPageStatus'
import styles from './auth.module.css'
import { homeFor, type Role } from './account'
import { useAuth } from './useAuth'

// ให้เข้าหน้านี้ได้เฉพาะบทบาทที่ระบุ — บทบาทมาจาก ensure_account() ขณะนั้น
// ยังไม่ล็อกอิน: จำหน้านี้ไว้แล้วไป A01; บทบาทไม่ตรง: ไปหน้าแรกของบทบาทตัวเอง
export function RequireRole({ roles, children }: { roles: Role[]; children: ReactNode }) {
  const { state } = useAuth()
  const location = useLocation()
  const here = location.pathname + location.search + location.hash

  useEffect(() => {
    if (state.status === 'signed_out') rememberNextPath(here)
  }, [state.status, here])

  if (state.status === 'loading') return <FullPageStatus />
  if (state.status === 'signed_out') return <Navigate to="/login" replace />
  if (state.status === 'error') return <AccountError />
  if (!roles.includes(state.account.role)) {
    return <Navigate to={homeFor(state.account.role)} replace />
  }
  return children
}

// ensure_account() ไม่สำเร็จ — ข้อความตาม UX 7.1
function AccountError() {
  const { state, signOut, reloadAccount } = useAuth()
  if (state.status !== 'error') return null
  const { error, session } = state
  const email = session.user.email

  return (
    <FullPageCard title={th.login.failedTitle}>
      <p className={styles.noteRed}>
        <TriangleAlert aria-hidden="true" />
        <span>{error.message}</span>
      </p>
      {error.action === 'switch_account' && email && (
        <p className={styles.muted}>{th.login.signedInAs(email)}</p>
      )}
      {error.ref && <p className={styles.ref}>{th.errors.reference(error.ref)}</p>}
      <div className={styles.actions}>
        {error.action === 'switch_account' ? (
          <Button onClick={signOut}>{th.login.switchAccount}</Button>
        ) : (
          <>
            <Button variant="ghost" onClick={signOut}>
              {th.common.signOut}
            </Button>
            <Button onClick={reloadAccount}>{th.login.retry}</Button>
          </>
        )}
      </div>
    </FullPageCard>
  )
}
