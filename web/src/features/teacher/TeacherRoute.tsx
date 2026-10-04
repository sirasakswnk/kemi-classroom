import { RequireRole } from '../../app/auth/RequireRole'
import { TeacherLayout } from './TeacherLayout'

// หน้าครูทั้งหมดอยู่ใต้ /t (โหลดแยก chunk จากหน้านักเรียน) — ครู หรือผู้ดูแลในโหมดผู้ดูแล (ตรวจใน TeacherLayout)
export default function TeacherRoute() {
  return (
    <RequireRole roles={['teacher', 'admin']}>
      <TeacherLayout />
    </RequireRole>
  )
}
