import { Check, X } from 'lucide-react'
import type { CSSProperties, ReactNode } from 'react'
import { th } from '../copy/th'
import { cx } from '../lib/cx'
import styles from './Steps.module.css'

export type StepState = 'done' | 'now' | 'todo' | 'skip'

export interface StepItem {
  label: string
  state: StepState
  /** ไอคอนของขั้น (ไม่ใส่: เสร็จ = ✓, ข้าม = ✕, อื่น ๆ = ลำดับขั้น) */
  icon?: ReactNode
  /** ขั้นรางวัลที่เสร็จแล้วใช้สีทอง */
  gold?: boolean
}

export interface StepsProps {
  /** ชื่อแถบขั้นตอนสำหรับเครื่องอ่านหน้าจอ เช่น “ขั้นตอนของงานนี้” */
  label: string
  steps: StepItem[]
  className?: string
}

// แถบขั้นตอน (แบบ v2 .steps) ในหน้าส่งงานและหน้านำเข้า — ขั้นปัจจุบันมี aria-current="step"
export function Steps({ label, steps, className }: StepsProps) {
  return (
    <ol
      aria-label={label}
      className={cx(styles.steps, className)}
      style={{ '--steps': steps.length } as CSSProperties}
    >
      {steps.map((s, i) => (
        <li
          key={s.label}
          className={cx(styles.step, styles[s.state], s.gold && s.state === 'done' && styles.gold)}
          aria-current={s.state === 'now' ? 'step' : undefined}
        >
          <span className={styles.dot} aria-hidden="true">
            {s.icon ??
              (s.state === 'done' ? <Check /> : s.state === 'skip' ? <X /> : <b>{i + 1}</b>)}
          </span>
          <span>
            {s.label}
            {s.state === 'done' && <span className="sr-only"> ({th.steps.done})</span>}
            {s.state === 'skip' && <span className="sr-only"> ({th.steps.skipped})</span>}
          </span>
        </li>
      ))}
    </ol>
  )
}
