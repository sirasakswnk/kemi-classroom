import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import {
  addDaysYmd,
  addMonths,
  formatDate,
  formatTime,
  HOURS,
  MINUTES,
  monthGrid,
  monthTitle,
  parseDate,
  parseTime,
  thaiFullDate,
  thaiSpokenDate,
  todayBangkok,
} from '../lib/thaiCalendar'
import { DatePicker, Field, TimePicker } from '.'

const ymd = (s: string) => parseDate(s)!

describe('ปฏิทินไทย (UX 13)', () => {
  it('วันที่ไทยเต็ม ปี พ.ศ. ไม่ขึ้นกับภาษาของเครื่อง', () => {
    expect(thaiFullDate('2026-10-08')).toBe('พฤ. 8 ต.ค. 2569')
    expect(thaiFullDate('2027-01-01')).toBe('ศ. 1 ม.ค. 2570')
    expect(thaiSpokenDate('2026-10-08')).toBe('วันพฤหัสบดีที่ 8 ตุลาคม 2569')
    expect(monthTitle(2026, 10)).toBe('ตุลาคม 2569')
    expect(thaiFullDate('ไม่ใช่วันที่')).toBe('')
  })
  it('ตรวจวันที่จริง รวมปีอธิกสุรทิน', () => {
    expect(parseDate('2026-02-29')).toBeNull()
    expect(parseDate('2028-02-29')).toEqual({ y: 2028, m: 2, d: 29 })
    expect(parseDate('2026-13-01')).toBeNull()
    expect(parseDate('2026-04-31')).toBeNull()
  })
  it('เลื่อนเดือน: ข้ามปีทั้งสองทิศ และปัดวันสุดท้ายของเดือน', () => {
    expect(formatDate(addMonths(ymd('2026-12-15'), 1))).toBe('2027-01-15')
    expect(formatDate(addMonths(ymd('2027-01-15'), -1))).toBe('2026-12-15')
    expect(formatDate(addMonths(ymd('2027-01-31'), 1))).toBe('2027-02-28')
    expect(formatDate(addMonths(ymd('2028-01-31'), 1))).toBe('2028-02-29')
    expect(formatDate(addMonths(ymd('2026-10-08'), -12))).toBe('2025-10-08')
  })
  it('เลื่อนวัน: ขอบเดือน/ปี', () => {
    expect(formatDate(addDaysYmd(ymd('2026-12-31'), 1))).toBe('2027-01-01')
    expect(formatDate(addDaysYmd(ymd('2026-03-01'), -1))).toBe('2026-02-28')
    expect(formatDate(addDaysYmd(ymd('2026-10-08'), 7))).toBe('2026-10-15')
  })
  it('ตารางเดือนเริ่มวันอาทิตย์', () => {
    // 1 ต.ค. 2026 = วันพฤหัสบดี → ช่องว่าง 4 ช่อง
    const oct = monthGrid(2026, 10)
    expect(oct[0]).toEqual([null, null, null, null, '2026-10-01', '2026-10-02', '2026-10-03'])
    expect(oct.flat().filter(Boolean)).toHaveLength(31)
    expect(oct.every((w) => w.length === 7)).toBe(true)
    // ก.พ. 2026 เริ่มวันอาทิตย์พอดี 28 วัน = 4 แถว
    expect(monthGrid(2026, 2)).toHaveLength(4)
  })
  it('วันนี้ตามเวลาไทย (UTC 18:00 = วันถัดไปในไทย)', () => {
    expect(todayBangkok(new Date('2026-10-07T18:00:00Z'))).toBe('2026-10-08')
    expect(todayBangkok(new Date('2026-10-07T16:59:00Z'))).toBe('2026-10-07')
  })
})

describe('เวลา 24 ชั่วโมง', () => {
  it('รับ 00:00–23:59 เท่านั้น', () => {
    expect(parseTime('23:59')).toEqual({ h: 23, min: 59 })
    expect(parseTime('00:00')).toEqual({ h: 0, min: 0 })
    expect(parseTime('24:00')).toBeNull()
    expect(parseTime('8:00')).toBeNull()
    expect(formatTime(8, 5)).toBe('08:05')
    expect(HOURS).toHaveLength(24)
    expect(HOURS.at(-1)).toBe('23')
    expect(MINUTES).toHaveLength(60)
    expect(MINUTES.at(-1)).toBe('59')
  })
})

describe('DatePicker / TimePicker', () => {
  it('ตัวเลือกเวลา: select ชั่วโมง/นาที ไม่มี AM/PM และไม่ใช้ input type=time', () => {
    const html = renderToString(<TimePicker label="กำหนดส่ง" value="20:00" onChange={() => {}} />)
    expect(html).not.toMatch(/AM|PM|type="time"/)
    expect(html).toContain('aria-label="เวลากำหนดส่ง (24 ชั่วโมง)"')
    expect(html).toMatch(/<option[^>]*value="23"/)
    for (const s of ['08:00', '12:00', '16:30', '20:00', '23:59'])
      expect(html).toContain(`>${s}</button>`)
    expect(html).toMatch(/aria-pressed="true"[^>]*>20:00</)
  })
  it('ตัวเลือกวันที่: ปุ่มแสดงวันที่ไทย + ปุ่มลัด ผูกกับ label ของ Field ไม่ใช้ input type=date', () => {
    const html = renderToString(
      <Field label="กำหนดส่ง" id="due">
        <DatePicker
          label="กำหนดส่ง"
          value="2026-10-08"
          onChange={() => {}}
          now={new Date('2026-10-07T03:00:00Z')}
        />
      </Field>,
    )
    expect(html).not.toContain('type="date"')
    expect(html).toContain('พฤ. 8 ต.ค. 2569')
    expect(html).toMatch(/<button[^>]*id="due"/)
    // พรุ่งนี้ของวันที่ 7 = วันที่ 8 ที่เลือกอยู่
    expect(html).toMatch(/aria-pressed="true"[^>]*>พรุ่งนี้</)
    expect(html).toMatch(/aria-pressed="false"[^>]*>วันนี้</)
  })
})
