import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../lib/cx'
import styles from './Chip.module.css'

export type ChipTone = 'purple' | 'green' | 'amber' | 'red' | 'gold' | 'plain' | 'outline'

export interface ChipProps extends HTMLAttributes<HTMLSpanElement> {
  tone?: ChipTone
  /** ป้ายสถานะต้องมีทั้งคำและไอคอนเสมอ ไม่พึ่งสีอย่างเดียว (UX 13) */
  icon?: ReactNode
}

export function Chip({ tone = 'plain', icon, className, children, ...rest }: ChipProps) {
  return (
    <span {...rest} className={cx(styles.chip, styles[tone], className)}>
      {icon && (
        <span className={styles.icon} aria-hidden="true">
          {icon}
        </span>
      )}
      {children}
    </span>
  )
}
