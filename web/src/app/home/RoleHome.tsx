import { ShieldCheck } from 'lucide-react'
import { useNavigate } from 'react-router'
import { th } from '../../copy/th'
import { Button, Chip } from '../../ui'
import type { Role } from '../auth/account'
import { useAuth } from '../auth/useAuth'
import { FullPageCard } from '../common/FullPageStatus'
import { enterAdminMode } from '../../features/teacher/adminMode'

// หน้าแรกผู้ดูแลชั่วคราว (D01 มาใน P2-09) — ครูใช้ T01 (/t) นักเรียนใช้ StudentHome แล้ว
export function RoleHome({ role }: { role: Role }) {
  const { state, signOut } = useAuth()
  const navigate = useNavigate()
  if (state.status !== 'ready') return null
  const email = state.account.email ?? state.session.user.email ?? ''

  return (
    <FullPageCard title={th.appName}>
      <Chip tone="purple" style={{ justifySelf: 'start' }}>
        {th.home.roles[role]}
      </Chip>
      {email && <p>{th.login.signedInAs(email)}</p>}
      <p style={{ color: 'var(--ink-2)' }}>{th.home.placeholder}</p>
      {role === 'admin' && (
        // L6: เข้าหน้าครูในโหมดผู้ดูแล (D01 เต็มรูปแบบมาใน P2-09)
        <Button
          icon={<ShieldCheck />}
          onClick={() => {
            enterAdminMode()
            navigate('/t')
          }}
        >
          {th.teacher.enterAdmin}
        </Button>
      )}
      <Button variant="ghost" onClick={signOut}>
        {th.common.signOut}
      </Button>
    </FullPageCard>
  )
}
