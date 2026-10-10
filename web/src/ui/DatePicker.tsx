import { CalendarDays, ChevronLeft, ChevronRight } from 'lucide-react'
import { useEffect, useId, useRef, useState, type KeyboardEvent, type Ref } from 'react'
import { th } from '../copy/th'
import { cx } from '../lib/cx'
import {
  addDaysYmd,
  addMonths,
  formatDate,
  monthGrid,
  monthTitle,
  parseDate,
  thaiFullDate,
  thaiSpokenDate,
  todayBangkok,
  weekday,
  WEEKDAYS_FULL,
  WEEKDAYS_SHORT,
  type YMD,
} from '../lib/thaiCalendar'
import { useControlProps } from './fieldContext'
import fieldStyles from './Field.module.css'
import { Sheet } from './Sheet'
import styles from './Pickers.module.css'

export interface DatePickerProps {
  /** 'YYYY-MM-DD' (วันตามเวลาไทย) หรือ '' */
  value: string
  onChange: (value: string) => void
  /** ชื่อช่อง ใช้เป็นหัวปฏิทินและชื่อปุ่มสำหรับเครื่องอ่านหน้าจอ เช่น “กำหนดส่ง” */
  label: string
  id?: string
  ref?: Ref<HTMLButtonElement>
  /** เวลาปัจจุบัน (ทดสอบ) */
  now?: Date
}

const SHORTCUTS = [
  ['today', 0],
  ['tomorrow', 1],
  ['week', 7],
] as const

// ตัวเลือกวันที่ของระบบ (UX 13): ปุ่มแสดงวันที่ไทยเต็ม “พฤ. 8 ต.ค. 2569” → ปฏิทินเดือนไทย ปี พ.ศ. สัปดาห์เริ่มวันอาทิตย์
// ใน Sheet (มือถือเป็นแผ่นล่าง ตั้งแต่ 768 px เป็นกล่องกลางจอ) + ปุ่มลัด วันนี้ · พรุ่งนี้ · อีก 7 วัน
// ไม่ใช้ <input type="date"> เพราะรูปแบบขึ้นกับภาษาของเครื่อง (เดือน/วัน/ปี)
export function DatePicker({ value, onChange, label, id, ref, now }: DatePickerProps) {
  const control = useControlProps({ id })
  const [open, setOpen] = useState(false)
  const dayRef = useRef<HTMLButtonElement>(null)
  const today = todayBangkok(now)
  const copy = th.picker
  const shown = value ? thaiFullDate(value) : copy.pickDate
  const shortcut = (days: number) => {
    const t = parseDate(today)
    return t ? formatDate(addDaysYmd(t, days)) : today
  }

  return (
    <div className={styles.date}>
      <button
        type="button"
        ref={ref}
        {...control}
        className={cx(fieldStyles.control, styles.trigger)}
        aria-haspopup="dialog"
        aria-label={copy.dateAria(label, shown)}
        onClick={() => setOpen(true)}
      >
        <CalendarDays aria-hidden="true" />
        <span className={cx(!value && styles.placeholder)}>{shown}</span>
      </button>
      <div className={styles.shortcuts} role="group" aria-label={copy.dateShortcuts}>
        {SHORTCUTS.map(([key, days]) => {
          const date = shortcut(days)
          return (
            <button
              key={key}
              type="button"
              className={styles.chip}
              aria-pressed={value === date}
              onClick={() => onChange(date)}
            >
              {copy[key]}
            </button>
          )
        })}
      </div>
      <Sheet
        open={open}
        onClose={() => setOpen(false)}
        title={label}
        align="start"
        initialFocusRef={dayRef}
      >
        {open && (
          <Calendar
            value={value}
            today={today}
            dayRef={dayRef}
            onPick={(date) => {
              onChange(date)
              setOpen(false)
            }}
          />
        )}
      </Sheet>
    </div>
  )
}

function Calendar({
  value,
  today,
  dayRef,
  onPick,
}: {
  value: string
  today: string
  dayRef: Ref<HTMLButtonElement>
  onPick: (date: string) => void
}) {
  const copy = th.picker
  const [focus, setFocus] = useState(() => (parseDate(value) ? value : today))
  const tableRef = useRef<HTMLTableElement>(null)
  const moved = useRef(false)
  const titleId = useId()
  const hintId = useId()
  const p = parseDate(focus) ?? parseDate(today)!
  const weeks = monthGrid(p.y, p.m)

  // หลังเลื่อนด้วยแป้นพิมพ์/ปุ่มเดือน ย้ายโฟกัสไปวันที่เลือกอยู่ (ครั้งแรก Sheet โฟกัสให้ผ่าน initialFocusRef)
  useEffect(() => {
    if (!moved.current) return
    tableRef.current?.querySelector<HTMLButtonElement>(`[data-date="${focus}"]`)?.focus()
  }, [focus])

  const go = (to: YMD, keepFocus = true) => {
    moved.current = keepFocus
    setFocus(formatDate(to))
  }

  const onKeyDown = (e: KeyboardEvent<HTMLButtonElement>) => {
    const step: Record<string, () => YMD> = {
      ArrowLeft: () => addDaysYmd(p, -1),
      ArrowRight: () => addDaysYmd(p, 1),
      ArrowUp: () => addDaysYmd(p, -7),
      ArrowDown: () => addDaysYmd(p, 7),
      Home: () => addDaysYmd(p, -weekday(p)),
      End: () => addDaysYmd(p, 6 - weekday(p)),
      PageUp: () => addMonths(p, e.shiftKey ? -12 : -1),
      PageDown: () => addMonths(p, e.shiftKey ? 12 : 1),
    }
    const next = step[e.key]
    if (!next) return
    e.preventDefault()
    go(next())
  }

  return (
    <div className={styles.calendar}>
      <div className={styles.calHead}>
        <button
          type="button"
          className={styles.navBtn}
          aria-label={copy.prevMonth}
          onClick={() => go(addMonths(p, -1), false)}
        >
          <ChevronLeft aria-hidden="true" />
        </button>
        <b id={titleId} aria-live="polite">
          {monthTitle(p.y, p.m)}
        </b>
        <button
          type="button"
          className={styles.navBtn}
          aria-label={copy.nextMonth}
          onClick={() => go(addMonths(p, 1), false)}
        >
          <ChevronRight aria-hidden="true" />
        </button>
      </div>
      <table
        ref={tableRef}
        className={styles.grid}
        aria-labelledby={titleId}
        aria-describedby={hintId}
      >
        <thead>
          <tr>
            {WEEKDAYS_SHORT.map((w, i) => (
              <th key={w} scope="col" abbr={WEEKDAYS_FULL[i]}>
                {w}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {weeks.map((week, wi) => (
            <tr key={wi}>
              {week.map((date, di) =>
                date ? (
                  <td key={date}>
                    <button
                      type="button"
                      ref={date === focus ? dayRef : undefined}
                      data-date={date}
                      className={styles.day}
                      tabIndex={date === focus ? 0 : -1}
                      aria-pressed={date === value}
                      aria-current={date === today ? 'date' : undefined}
                      aria-label={`${thaiSpokenDate(date)}${date === today ? ` (${copy.todayMark})` : ''}`}
                      onKeyDown={onKeyDown}
                      onClick={() => onPick(date)}
                    >
                      {Number(date.slice(8))}
                    </button>
                  </td>
                ) : (
                  <td key={`e${di}`} />
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
      <p id={hintId} className={styles.hint}>
        {copy.calendarHint}
      </p>
    </div>
  )
}
