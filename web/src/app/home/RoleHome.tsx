import { FileSpreadsheet } from 'lucide-react'
import { useNavigate } from 'react-router'
import { th } from '../../copy/th'
import { Button, Chip } from '../../ui'
import type { Role } from '../auth/account'
import { useAuth } from '../auth/useAuth'
import { FullPageCard } from '../common/FullPageStatus'

// หน้าแรกของแต่ละบทบาทในระยะ 1 — ยังเป็นหน้าว่าง (TECHNICAL_BUILD_PLAN ส่วน 10 ระยะ 1)
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
      {role === 'teacher' && (
        <Button icon={<FileSpreadsheet />} onClick={() => navigate('/t/roster/import')}>
          {th.roster.openImport}
        </Button>
      )}
      <Button variant="ghost" onClick={signOut}>
        {th.common.signOut}
      </Button>
    </FullPageCard>
  )
}
