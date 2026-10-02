import type { HTMLAttributes } from 'react'
import { cx } from '../lib/cx'
import styles from './Card.module.css'

export interface CardProps extends HTMLAttributes<HTMLElement> {
  as?: 'div' | 'section' | 'article' | 'li'
  padding?: 'none' | 'md' | 'lg'
  /** เงาชัดขึ้นสำหรับการ์ดที่ต้องเด่น */
  raised?: boolean
}

export function Card({
  as: Tag = 'div',
  padding = 'md',
  raised = false,
  className,
  ...rest
}: CardProps) {
  return (
    <Tag
      {...rest}
      className={cx(styles.card, styles[padding], raised && styles.raised, className)}
    />
  )
}
