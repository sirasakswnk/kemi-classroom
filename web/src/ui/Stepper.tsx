import { Minus, Plus } from 'lucide-react'
import { th } from '../copy/th'
import { cx } from '../lib/cx'
import styles from './Stepper.module.css'

export interface StepperProps {
  value: number
  onChange: (value: number) => void
  /** ชื่อสิ่งที่ปรับ เช่น “โทเคน” → ปุ่ม “ลดโทเคน”/“เพิ่มโทเคน” และประกาศ “โทเคน 3” */
  label: string
  min?: number
  max?: number
  step?: number
  /** รูปแบบตัวเลขที่แสดง เช่น แสดงเครื่องหมาย + สำหรับการปรับยอด */
  format?: (value: number) => string
  disabled?: boolean
  className?: string
}

// ปุ่ม −/+ ปรับจำนวน (แบบ v2 .stepper) — ตั้งโทเคนรางวัลและปรับโทเคนรายคน
// ถึงขอบเขตแล้วใช้ aria-disabled แทน disabled: ปุ่มยังรับโฟกัสอยู่ ผู้ใช้คีย์บอร์ดจึงไม่หลุดตำแหน่ง
export function Stepper({
  value,
  onChange,
  label,
  min = Number.NEGATIVE_INFINITY,
  max = Number.POSITIVE_INFINITY,
  step = 1,
  format = String,
  disabled = false,
  className,
}: StepperProps) {
  const atMin = disabled || value - step < min
  const atMax = disabled || value + step > max

  return (
    <div role="group" aria-label={label} className={cx(styles.stepper, className)}>
      <button
        type="button"
        className={styles.btn}
        aria-label={th.stepper.decrease(label)}
        aria-disabled={atMin || undefined}
        onClick={() => {
          if (!atMin) onChange(value - step)
        }}
      >
        <Minus aria-hidden="true" />
      </button>
      <output className={cx(styles.value, 'num')} aria-live="polite" aria-atomic="true">
        <span className="sr-only">{label} </span>
        {format(value)}
      </output>
      <button
        type="button"
        className={styles.btn}
        aria-label={th.stepper.increase(label)}
        aria-disabled={atMax || undefined}
        onClick={() => {
          if (!atMax) onChange(value + step)
        }}
      >
        <Plus aria-hidden="true" />
      </button>
    </div>
  )
}
