// เวลาไทย (Asia/Bangkok = UTC+7 ไม่มีเวลาออมแสง) ↔ UTC — ฐานข้อมูลเก็บ UTC หน้าเว็บรับและแสดงเวลาไทย (CLAUDE.md ส่วน 5)

const ZONE = 'Asia/Bangkok'
const OFFSET = '+07:00'
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const TIME_RE = /^\d{2}:\d{2}$/

const partsFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

/** วันที่และเวลาไทยของเวลาหนึ่ง: { date: 'YYYY-MM-DD', time: 'HH:mm' } (ตรงกับค่าของ <input type="date|time">) */
export function bangkokParts(when: Date | string): { date: string; time: string } {
  const parts = Object.fromEntries(
    partsFormat.formatToParts(new Date(when)).map((p) => [p.type, p.value]),
  )
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}`,
  }
}

/** วันที่ + เวลาไทย → ISO แบบ UTC (นาทีเต็ม) หรือ null ถ้ารูปแบบผิดหรือไม่มีวันนั้นจริง (เช่น 31 เม.ย.) */
export function bangkokToUtcIso(date: string, time: string): string | null {
  if (!DATE_RE.test(date) || !TIME_RE.test(time)) return null
  const when = new Date(`${date}T${time}:00${OFFSET}`)
  if (Number.isNaN(when.getTime())) return null
  const back = bangkokParts(when)
  if (back.date !== date || back.time !== time) return null
  return when.toISOString()
}

/** เลื่อนวันที่แบบปฏิทิน (YYYY-MM-DD) — ไม่ขึ้นกับเขตเวลาของเครื่อง */
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10)
}

const dayMonth = new Intl.DateTimeFormat('th-TH', {
  timeZone: ZONE,
  day: 'numeric',
  month: 'short',
})
const dayMonthYear = new Intl.DateTimeFormat('th-TH', {
  timeZone: ZONE,
  day: 'numeric',
  month: 'short',
  year: 'numeric',
})

/** วันที่แบบไทยสั้น เช่น “11 พ.ย.” — ใส่ปี (พ.ศ.) เมื่อไม่ใช่ปีเดียวกับตอนนี้ */
export function thaiDate(when: Date | string, now: Date = new Date()): string {
  const sameYear = bangkokParts(when).date.slice(0, 4) === bangkokParts(now).date.slice(0, 4)
  return (sameYear ? dayMonth : dayMonthYear).format(new Date(when))
}

/** เวลาไทย เช่น “20:00” */
export function thaiTime(when: Date | string): string {
  return bangkokParts(when).time
}
