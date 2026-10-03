import { RequireRole } from '../../app/auth/RequireRole'
import AdminHome from './AdminHome'

// /admin — เฉพาะ role admin
export default function AdminRoute() {
  return (
    <RequireRole roles={['admin']}>
      <AdminHome />
    </RequireRole>
  )
}
