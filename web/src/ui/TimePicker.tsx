import { useId } from 'react'
import { th } from '../copy/th'
import { formatTime, HOURS, MINUTES, parseTime, TIME_SHORTCUTS } from '../lib/thaiCalendar'
import { Select } from './Field'
import styles from './Pickers.module.css'

export interface TimePickerProps {
  /** 'HH:mm' (24 ชั่วโมง เวลาไทย) หรือ '' */
  value: string
  onChange: (value: string) => void
  /** ชื่อช่อง เช่น “กำหนดส่ง” → กลุ่มชื่อ “เวลากำหนดส่ง (24 ชั่วโมง)” */
  label: string
}

// ตัวเลือกเวลาของระบบ (UX 13): ชั่วโมง 00–23 + นาที 00–59 (select ของเบราว์เซอร์แสดงตัวเลขตรง ๆ ไม่มี AM/PM)
// + ปุ่มลัด 08:00 · 12:00 · 16:30 · 20:00 · 23:59 — ไม่ใช้ <input type="time"> ซึ่งแสดง AM/PM ตามภาษาของเครื่อง
export function TimePicker({ value, onChange, label }: TimePickerProps) {
  const copy = th.picker
  const id = useId()
  const t = parseTime(value)
  const h = t ? HOURS[t.h] : ''
  const m = t ? MINUTES[t.min] : ''
  return (
    <div className={styles.time} role="group" aria-label={copy.timeAria(label)}>
      <div className={styles.selects}>
        <Select
          id={`${id}h`}
          className={styles.select}
          aria-label={copy.hour}
          value={h}
          onChange={(e) => onChange(formatTime(Number(e.target.value), t?.min ?? 0))}
        >
          {!t && <option value="">--</option>}
          {HOURS.map((x) => (
            <option key={x} value={x}>
              {x}
            </option>
          ))}
        </Select>
        <span aria-hidden="true" className={styles.colon}>
          :
        </span>
        <Select
          id={`${id}m`}
          className={styles.select}
          aria-label={copy.minute}
          value={m}
          onChange={(e) => onChange(formatTime(t?.h ?? 0, Number(e.target.value)))}
        >
          {!t && <option value="">--</option>}
          {MINUTES.map((x) => (
            <option key={x} value={x}>
              {x}
            </option>
          ))}
        </Select>
        <span className={styles.unit}>{copy.unit}</span>
      </div>
      <div className={styles.shortcuts} role="group" aria-label={copy.timeShortcuts}>
        {TIME_SHORTCUTS.map((s) => (
          <button
            key={s}
            type="button"
            className={styles.chip}
            aria-pressed={value === s}
            onClick={() => onChange(s)}
          >
            {s}
          </button>
        ))}
      </div>
    </div>
  )
}
