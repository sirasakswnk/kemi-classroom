import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { drawOptionsQuery } from './api'
import { Coin } from './Medal'
import styles from './rewards.module.css'

// ยอดโทเคนบนหัวเว็บนักเรียน (แบบ v2 .token-pill) → S04 · ตัวเลขเด้งเมื่อยอดเปลี่ยน (key ใหม่ = เล่นแอนิเมชันใหม่)
export function TokenPill() {
  const { data } = useQuery(drawOptionsQuery)
  if (!data) return null
  return (
    <Link to="/draw" className={styles.pill} aria-label={th.rewards.pillAria(data.balance)}>
      <Coin size={26} />
      <span key={data.balance} className={styles.pillNum}>
        {data.balance}
      </span>
    </Link>
  )
}
