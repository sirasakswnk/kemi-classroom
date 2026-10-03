import { th } from '../../copy/th'
import { TeacherPage } from '../teacher/TeacherLayout'
import { RosterImportPage } from './RosterImportPage'

// T05 นำเข้า Excel ใต้โครงหน้าครู (/t/roster/import) — โหลดแยก chunk; ตัวอ่าน Excel (SheetJS) แยกอีกชั้นใน readSheet()
// ครู หรือผู้ดูแลในโหมดผู้ดูแล (ตรวจใน TeacherLayout)
export default function RosterImportRoute() {
  return (
    <TeacherPage
      crumbs={[
        { label: th.teacher.overview, to: '/t' },
        { label: th.teacher.roster, to: '/t/roster' },
        { label: th.roster.title },
      ]}
    >
      <RosterImportPage />
    </TeacherPage>
  )
}
