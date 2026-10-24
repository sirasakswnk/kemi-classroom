import { useQuery, useQueryClient } from '@tanstack/react-query'
import { X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { markRewardEffectSeen, rewardEffectsQuery } from './api'
import { Coin } from './Medal'
import styles from './rewards.module.css'

const copy = th.rewards
/** การ์ดหายเองหลังเวลานี้ — กดปิดก่อนได้ */
const SHOW_MS = 7000

// เอฟเฟกต์ได้รับโทเคน (UX 7): งานที่ได้โทเคนแต่ยังไม่ได้ดูเอฟเฟกต์ แสดงครั้งเดียวรวมยอด “+3 โทเคน จาก 2 งาน”
// แล้วตั้งดูแล้ว**เฉพาะ id ที่แสดง** (รางวัลที่ได้ระหว่างแสดงยังค้างไว้ครั้งหน้า) · การ์ดลอยด้านบน ไม่ล็อกหน้า
// ไม่บังการอ่าน กดปิดได้ ไม่ขึ้นในกระดิ่ง · โหลดใหม่เมื่อกลับมาที่แท็บ (ได้รับตอนปิดเว็บก็เห็นตอนกลับมา)
export function RewardEffect() {
  const queryClient = useQueryClient()
  const { data } = useQuery(rewardEffectsQuery)
  const [dismissed, setDismissed] = useState<string | null>(null)
  const marked = useRef(new Set<string>())

  const ids = data?.submission_ids ?? []
  const key = ids.join(',')
  const visible = !!data && data.tokens > 0 && ids.length > 0 && key !== dismissed

  useEffect(() => {
    if (!visible || marked.current.has(key)) return
    marked.current.add(key)
    markRewardEffectSeen(key.split(','))
      .then(() => queryClient.invalidateQueries({ queryKey: ['draw-options'] }))
      .catch(() => {
        // ไม่สำเร็จ (เน็ตหลุด) = ยังค้างอยู่ฝั่งเซิร์ฟเวอร์ แสดงอีกครั้งตอนเข้าเว็บครั้งหน้า
        marked.current.delete(key)
      })
  }, [visible, key, queryClient])

  useEffect(() => {
    if (!visible) return
    const timer = setTimeout(() => setDismissed(key), SHOW_MS)
    return () => clearTimeout(timer)
  }, [visible, key])

  if (!visible) return null
  const close = () => setDismissed(key)
  return (
    <div className={styles.fx} role="status">
      <span className={styles.fxCoin}>
        <Coin size={44} />
      </span>
      <span className={styles.fxText}>
        <span className={styles.fxEyebrow}>{copy.fxEyebrow}</span>
        <span className={styles.fxAmount}>
          {copy.fxAmount(data.tokens)}
          <small>{copy.fxWorks(data.works)}</small>
        </span>
      </span>
      <button type="button" className={styles.fxClose} aria-label={copy.fxClose} onClick={close}>
        <X aria-hidden="true" />
      </button>
      <p className={styles.fxBody}>{copy.fxBody}</p>
      <div className={styles.fxActions}>
        <Link to="/draw" className={styles.pill} onClick={close}>
          {copy.fxGo}
        </Link>
      </div>
    </div>
  )
}
