import { th } from '../../copy/th'
import { Medal } from './Medal'
import styles from './rewards.module.css'

// เครื่องรางที่นักเรียนเลือกแสดงข้างชื่อในแท็บสมาชิก (แบบ v2 .m-charm) — ตู้ทั้งหมดไม่เปิดให้เพื่อน
export function MemberCharm({
  charm,
  image,
}: {
  charm: { name: string; symbol: string; rarity_id: number }
  /** object URL จาก useCharmImages ของทั้งหน้าจอ (ขอลิงก์รวมครั้งเดียว) — ไม่มี = เหรียญวาด */
  image?: string
}) {
  const label = th.rewards.memberCharm(charm.name)
  return (
    <span className={styles.memberCharm} role="img" aria-label={label} title={charm.name}>
      <Medal rarityId={charm.rarity_id} symbol={charm.symbol} size={28} image={image} />
    </span>
  )
}
