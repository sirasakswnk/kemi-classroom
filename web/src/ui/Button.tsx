import type { ComponentProps, ReactNode } from 'react'
import { cx } from '../lib/cx'
import styles from './Button.module.css'

export type ButtonVariant = 'primary' | 'soft' | 'ghost' | 'gold' | 'danger'
export type ButtonSize = 'md' | 'sm'

export interface ButtonProps extends ComponentProps<'button'> {
  variant?: ButtonVariant
  size?: ButtonSize
  /** กว้างเต็มพื้นที่ */
  block?: boolean
  /** ไอคอนนำหน้าข้อความ (เช่นจาก lucide-react) — ซ่อนจากเครื่องอ่านหน้าจอ */
  icon?: ReactNode
}

// ทองใช้กับโทเคน ปุ่มสุ่ม และรางวัลเท่านั้น (UX 13)
export function Button({
  variant = 'primary',
  size = 'md',
  block = false,
  icon,
  type = 'button',
  className,
  children,
  ...rest
}: ButtonProps) {
  return (
    <button
      {...rest}
      type={type}
      className={cx(
        styles.btn,
        styles[variant],
        size === 'sm' && styles.sm,
        block && styles.block,
        className,
      )}
    >
      {icon && (
        <span className={styles.icon} aria-hidden="true">
          {icon}
        </span>
      )}
      {children}
    </button>
  )
}
