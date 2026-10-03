import type { ReactNode } from 'react'
import { Benzene } from '../../app/common/brand'
import { cx } from '../../lib/cx'
import styles from './ClassBanner.module.css'

// แถบสีม่วงของชั้นเรียน (แบบ v2 .class-banner) — สีวนตามลำดับห้อง
export function ClassBanner({
  tone,
  eyebrow,
  title,
  level = 2,
  size = 'card',
  children,
}: {
  tone: number
  eyebrow: ReactNode
  title: ReactNode
  level?: 1 | 2
  size?: 'card' | 'hero'
  children?: ReactNode
}) {
  const Heading = level === 1 ? 'h1' : 'h2'
  return (
    <div className={cx(styles.banner, styles[size])} data-tone={tone}>
      <Benzene className={styles.benzene} />
      <span className={styles.eyebrow}>{eyebrow}</span>
      <Heading className={styles.title}>{title}</Heading>
      {children}
    </div>
  )
}
