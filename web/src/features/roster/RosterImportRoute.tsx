import { RequireRole } from '../../app/auth/RequireRole'
import { RosterImportPage } from './RosterImportPage'

// โหลดแยก chunk ตอนเปิดหน้านำเข้า (router.tsx) — ตัวอ่าน Excel (SheetJS) แยกอีกชั้นใน readSheet()
export default function RosterImportRoute() {
  return (
    <RequireRole roles={['teacher']}>
      <RosterImportPage />
    </RequireRole>
  )
}
