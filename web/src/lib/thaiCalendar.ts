// ปฏิทินและวันที่แบบไทยสำหรับตัวเลือกวันที่/เวลาของระบบ (UX 13 “วันที่และเวลา”) — ไม่พึ่งภาษาของเครื่อง/เบราว์เซอร์
// ชื่อเดือน/วันเขียนตายตัว ปี พ.ศ. = ค.ศ. + 543 · วันที่เป็นสตริง 'YYYY-MM-DD' (วันตามปฏิทินไทย ไม่มีเขตเวลา)

import { bangkokParts } from './thaiTime'

export const MONTHS_SHORT = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
] as const
export const MONTHS_FULL = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
] as const
/** สัปดาห์เริ่มวันอาทิตย์ */
export const WEEKDAYS_SHORT = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'] as const
export const WEEKDAYS_FULL = [
  'อาทิตย์',
  'จันทร์',
  'อังคาร',
  'พุธ',
  'พฤหัสบดี',
  'ศุกร์',
  'เสาร์',
] as const

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/

export interface YMD {
  y: number
  /** 1–12 */
  m: number
  d: number
}

/** แยก 'YYYY-MM-DD' — null ถ้ารูปแบบผิดหรือไม่มีวันนั้นจริง */
export function parseDate(value: string): YMD | null {
  const m = DATE_RE.exec(value)
  if (!m) return null
  const y = Number(m[1])
  const mo = Number(m[2])
  const d = Number(m[3])
  if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null
  return { y, m: mo, d }
}

const pad = (n: number) => String(n).padStart(2, '0')
export const formatDate = ({ y, m, d }: YMD) => `${String(y).padStart(4, '0')}-${pad(m)}-${pad(d)}`

export function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate()
}

/** 0 = อาทิตย์ */
export function weekday({ y, m, d }: YMD): number {
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay()
}

export const buddhistYear = (y: number) => y + 543

/** “พฤ. 8 ต.ค. 2569” */
export function thaiFullDate(value: string): string {
  const p = parseDate(value)
  if (!p) return ''
  return `${WEEKDAYS_SHORT[weekday(p)]} ${p.d} ${MONTHS_SHORT[p.m - 1]} ${buddhistYear(p.y)}`
}

/** สำหรับเครื่องอ่านหน้าจอ: “วันพฤหัสบดีที่ 8 ตุลาคม 2569” */
export function thaiSpokenDate(value: string): string {
  const p = parseDate(value)
  if (!p) return ''
  return `วัน${WEEKDAYS_FULL[weekday(p)]}ที่ ${p.d} ${MONTHS_FULL[p.m - 1]} ${buddhistYear(p.y)}`
}

/** หัวปฏิทิน “ตุลาคม 2569” */
export const monthTitle = (y: number, m: number) => `${MONTHS_FULL[m - 1]} ${buddhistYear(y)}`

/** เลื่อนเดือน (ข้ามปีได้) — วันที่เกินจำนวนวันของเดือนใหม่ปัดเป็นวันสุดท้าย เช่น 31 ม.ค. + 1 เดือน = 28/29 ก.พ. */
export function addMonths(value: YMD, n: number): YMD {
  const total = value.y * 12 + (value.m - 1) + n
  const y = Math.floor(total / 12)
  const m = (total % 12) + 1
  return { y, m, d: Math.min(value.d, daysInMonth(y, m)) }
}

export function addDaysYmd(value: YMD, n: number): YMD {
  const t = new Date(Date.UTC(value.y, value.m - 1, value.d + n))
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() }
}

/** ตารางเดือน: แถวละ 7 วัน (อา.–ส.) ช่องนอกเดือนเป็น null */
export function monthGrid(y: number, m: number): (string | null)[][] {
  const first = weekday({ y, m, d: 1 })
  const days = daysInMonth(y, m)
  const cells: (string | null)[] = Array.from({ length: first }, () => null)
  for (let d = 1; d <= days; d++) cells.push(formatDate({ y, m, d }))
  while (cells.length % 7) cells.push(null)
  const weeks: (string | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7))
  return weeks
}

/** วันนี้ตามเวลาไทย */
export function todayBangkok(now: Date = new Date()): string {
  return bangkokParts(now).date
}

// ---------- เวลา 24 ชั่วโมง ----------
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/

export function parseTime(value: string): { h: number; min: number } | null {
  const m = TIME_RE.exec(value)
  return m ? { h: Number(m[1]), min: Number(m[2]) } : null
}

export const formatTime = (h: number, min: number) => `${pad(h)}:${pad(min)}`

/** ปุ่มลัดเวลา (UX 13) */
export const TIME_SHORTCUTS = ['08:00', '12:00', '16:30', '20:00', '23:59'] as const
export const HOURS = Array.from({ length: 24 }, (_, h) => pad(h))
export const MINUTES = Array.from({ length: 60 }, (_, m) => pad(m))
