import { Archive } from 'lucide-react'
import { th } from '../../copy/th'
import { Chip } from '../../ui'
import { useRoomTerm } from './useRoomTerm'
import styles from './RoomTerm.module.css'

// ป้าย “ภาคเรียนก่อน” ของห้องเทอมเก่า (UX ข้อใหม่ใต้ “[ยืนยัน I5]”, P5-09) — ใช้ทั้งหน้าครูและนักเรียน

/** หัวห้องบนแถบสี: “ชื่อภาคเรียน” + ป้ายภาคเรียนก่อน */
export function RoomEyebrow({ termId }: { termId: string | undefined }) {
  const { name, past } = useRoomTerm(termId)
  return (
    <>
      {name}
      {past && <span className={styles.bannerTag}>{th.classrooms.pastTerm}</span>}
    </>
  )
}

/** ป้ายในหน้าอื่นของห้อง (หน้างาน ตารางคะแนน ตัวดูงาน) — แสดงเฉพาะห้องเทอมเก่า */
export function PastTermChip({ termId }: { termId: string | undefined }) {
  const { past } = useRoomTerm(termId)
  if (!past) return null
  return (
    <Chip tone="plain" icon={<Archive />} className={styles.chip}>
      {th.classrooms.pastTerm}
    </Chip>
  )
}
