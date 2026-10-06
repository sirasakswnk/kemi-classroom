import { TriangleAlert } from 'lucide-react'
import { useId, type ComponentProps, type ReactNode } from 'react'
import { th } from '../copy/th'
import { cx } from '../lib/cx'
import styles from './Field.module.css'
import { FieldContext, useControlProps } from './fieldContext'

export interface FieldProps {
  label: ReactNode
  /** คำอธิบายใต้ช่อง */
  hint?: ReactNode
  /** ข้อความผิดพลาดอยู่ใกล้ช่อง มีไอคอนและคำ ไม่พึ่งสีอย่างเดียว (UX 13) */
  error?: ReactNode
  /** ต่อท้ายชื่อช่องว่า “· ไม่บังคับ” */
  optional?: boolean
  /** id ของช่องกรอก (ไม่ใส่ = สร้างให้) */
  id?: string
  className?: string
  children: ReactNode
}

// ห่อ label + ช่องกรอก + คำอธิบาย + ข้อผิดพลาด แล้วผูก id/aria ให้ Input/Textarea ด้านในอัตโนมัติ
export function Field({
  label,
  hint,
  error,
  optional = false,
  id,
  className,
  children,
}: FieldProps) {
  const autoId = useId()
  const controlId = id ?? `${autoId}control`
  const hintId = hint ? `${autoId}hint` : undefined
  const errorId = error ? `${autoId}error` : undefined

  return (
    <div className={cx(styles.field, className)}>
      <label className={styles.label} htmlFor={controlId}>
        {label}
        {optional && <span className={styles.optional}> · {th.field.optional}</span>}
      </label>
      <FieldContext
        value={{
          id: controlId,
          describedBy: cx(hintId, errorId) || undefined,
          invalid: Boolean(error),
        }}
      >
        {children}
      </FieldContext>
      {hint && (
        <p id={hintId} className={styles.hint}>
          {hint}
        </p>
      )}
      {error && (
        <p id={errorId} className={styles.error}>
          <TriangleAlert aria-hidden="true" />
          <span>{error}</span>
        </p>
      )}
    </div>
  )
}

export function Input({ className, ...rest }: ComponentProps<'input'>) {
  return <input {...rest} {...useControlProps(rest)} className={cx(styles.control, className)} />
}

export function Textarea({ className, ...rest }: ComponentProps<'textarea'>) {
  return (
    <textarea
      {...rest}
      {...useControlProps(rest)}
      className={cx(styles.control, styles.textarea, className)}
    />
  )
}

export function Select({ className, ...rest }: ComponentProps<'select'>) {
  return (
    <select
      {...rest}
      {...useControlProps(rest)}
      className={cx(styles.control, styles.select, className)}
    />
  )
}
