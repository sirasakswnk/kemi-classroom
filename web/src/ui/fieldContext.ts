import { createContext, useContext, type ComponentProps } from 'react'
import { cx } from '../lib/cx'

// บริบทของ Field: id/aria ที่ช่องกรอกด้านใน (Input/Select/Textarea, DatePicker) ผูกอัตโนมัติ
export interface FieldContextValue {
  id: string
  describedBy: string | undefined
  invalid: boolean
}

export const FieldContext = createContext<FieldContextValue | null>(null)

export function useControlProps(props: {
  id?: string
  className?: string
  'aria-describedby'?: string
  'aria-invalid'?: ComponentProps<'input'>['aria-invalid']
}) {
  const field = useContext(FieldContext)
  return {
    id: props.id ?? field?.id,
    'aria-describedby': cx(field?.describedBy, props['aria-describedby']) || undefined,
    'aria-invalid': props['aria-invalid'] ?? (field?.invalid ? true : undefined),
  }
}
