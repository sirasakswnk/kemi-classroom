import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import type { StatusRow } from './api'
import {
  countRows,
  filterRows,
  isImage,
  paginate,
  parseFilter,
  phaseBadge,
  rowBadges,
} from './reviewState'

const row = (n: number, over: Partial<StatusRow> = {}): StatusRow => ({
  student_id: `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
  roll_number: n,
  display_name: `นักเรียน ${n}`,
  member: true,
  submission_id: null,
  first_submitted_at: null,
  last_submitted_at: null,
  content_revision: null,
  timing: null,
  graded: false,
  file_count: 0,
  ...over,
})
const sent = (n: number, over: Partial<StatusRow> = {}) =>
  row(n, {
    submission_id: `00000000-0000-4000-8000-${String(900 + n).padStart(12, '0')}`,
    first_submitted_at: '2026-10-01T01:00:00Z',
    last_submitted_at: '2026-10-01T01:00:00Z',
    content_revision: 1,
    timing: 'on_time',
    file_count: 1,
    ...over,
  })

describe('สถานะรับงาน (T08/T03)', () => {
  const due = '2026-10-10T13:00:00Z'
  it('เปิดรับ / ครบกำหนดแต่ยังไม่ปิดรับ / ปิดรับแล้ว / รับหลังเฉลย', () => {
    expect(phaseBadge('open', due, Date.parse('2026-10-10T13:00:00Z')).label).toBe(
      th.review.phase.open,
    )
    expect(phaseBadge('open', due, Date.parse('2026-10-10T13:00:01Z')).label).toBe(
      th.review.phase.dueOpen,
    )
    expect(phaseBadge('closed', due, 0).label).toBe(th.review.phase.closed)
    expect(phaseBadge('after_solution', due, 0).label).toBe(th.review.phase.afterSolution)
  })
})

describe('ตาราง T03', () => {
  const rows = [
    row(1),
    sent(2),
    sent(3, { timing: 'late', content_revision: 2 }),
    sent(4, { member: false }),
  ]
  it('ตัวกรอง ทั้งหมด/ส่งแล้ว/ยังไม่ส่ง และค่าที่ไม่รู้จัก = ทั้งหมด', () => {
    expect(filterRows(rows, 'sub').map((r) => r.roll_number)).toEqual([2, 3, 4])
    expect(filterRows(rows, 'not').map((r) => r.roll_number)).toEqual([1])
    expect(parseFilter('xyz')).toBe('all')
    expect(parseFilter('not')).toBe('not')
  })
  it('ยอด: ส่งแล้ว ยังไม่ส่ง รอตรวจ ส่งช้า', () => {
    expect(countRows(rows)).toEqual({ total: 4, submitted: 3, not: 1, waiting: 3, late: 1 })
  })
  it('ป้ายแถว: ส่งแล้ว / ส่งแก้แล้ว + ส่งช้า / ออกจากห้องแล้ว / ยังไม่ส่ง', () => {
    expect(rowBadges(rows[0]).map((b) => b.label)).toEqual([th.review.status.not])
    expect(rowBadges(rows[1]).map((b) => b.label)).toEqual([th.review.status.submitted])
    expect(rowBadges(rows[2]).map((b) => b.label)).toEqual([
      th.review.status.revised(2),
      th.review.status.late,
    ])
    expect(rowBadges(rows[3]).map((b) => b.label)).toEqual([
      th.review.status.submitted,
      th.review.status.left,
    ])
  })
  it('แบ่งหน้า 15 คน และตัดหน้าที่เกินช่วง', () => {
    const many = Array.from({ length: 32 }, (_, i) => row(i + 1))
    expect(paginate(many, 1)).toMatchObject({ page: 1, pages: 3, from: 0 })
    expect(paginate(many, 3).rows.map((r) => r.roll_number)).toEqual([31, 32])
    expect(paginate(many, 9).page).toBe(3)
    expect(paginate(many, Number.NaN).page).toBe(1)
    expect(paginate([], 2)).toMatchObject({ page: 1, pages: 1, rows: [] })
  })
  it('ชนิดไฟล์รูป', () => {
    expect(isImage('image/jpeg')).toBe(true)
    expect(isImage('application/pdf')).toBe(false)
  })
})
