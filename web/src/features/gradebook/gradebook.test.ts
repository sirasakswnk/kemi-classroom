import { describe, expect, it } from 'vitest'
import type { GradeTable, RoomOption } from './api'
import { BOM, csvField, csvFileName, gradeCsv } from './gradeCsv'
import {
  cellView,
  clampPage,
  pageCount,
  pageRows,
  PER_PAGE,
  tableTotals,
  termGroups,
} from './gradebookState'

const A = '00000000-0000-4000-8000-00000000000a'
const B = '00000000-0000-4000-8000-00000000000b'
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`

const table = (): GradeTable => ({
  classroom_id: uuid(1),
  term_id: uuid(2),
  term_name: '2/2569',
  assignments: [
    {
      post_id: A,
      title: 'งาน A',
      due_at: '2026-10-01T13:00:00Z',
      full_score: 10,
      published_at: '2026-09-20T01:00:00Z',
    },
    {
      post_id: B,
      title: '=HYPERLINK("x")',
      due_at: '2026-10-05T13:00:00Z',
      full_score: 20,
      published_at: '2026-09-25T01:00:00Z',
    },
  ],
  rows: [
    {
      student_id: uuid(11),
      roll_number: 1,
      display_name: 'สมชาย, ใจดี',
      member: true,
      cells: { [A]: { state: 'graded', raw: 9, net: 8, late: true }, [B]: { state: 'waiting' } },
    },
    {
      student_id: uuid(12),
      roll_number: null,
      display_name: '-แทรกสูตร',
      member: false,
      cells: { [A]: { state: 'graded', raw: null, net: null, late: false } },
    },
    {
      student_id: uuid(13),
      roll_number: 3,
      display_name: 'ศูนย์ คะแนน',
      member: true,
      cells: { [A]: { state: 'graded', raw: 0, net: 0, late: false } },
    },
  ],
})

describe('T04 สถานะของช่อง', () => {
  it('ไม่มีเซลล์ = ยังไม่ส่ง · waiting = รอตรวจ · มีคะแนน · 0 ไม่ใช่ว่าง · ไม่ให้คะแนน', () => {
    expect(cellView(undefined)).toEqual({ kind: 'none' })
    expect(cellView({ state: 'waiting' })).toEqual({ kind: 'waiting' })
    expect(cellView({ state: 'graded', raw: 9, net: 8, late: true })).toEqual({
      kind: 'score',
      net: 8,
      late: true,
    })
    expect(cellView({ state: 'graded', raw: 0, net: 0, late: false })).toEqual({
      kind: 'score',
      net: 0,
      late: false,
    })
    expect(cellView({ state: 'graded', raw: null, net: null, late: false })).toEqual({
      kind: 'noScore',
      late: false,
    })
  })
  it('ยอดรอตรวจทั้งตาราง', () => {
    expect(tableTotals(table())).toEqual({ students: 3, assignments: 2, waiting: 1 })
  })
})

describe('T04 แบ่งหน้า', () => {
  const rows = Array.from({ length: 40 }, (_, i) => i)
  it('15 คนต่อหน้า', () => {
    expect(PER_PAGE).toBe(15)
    expect(pageCount(40)).toBe(3)
    expect(pageCount(0)).toBe(1)
    expect(pageRows(rows, 1)).toHaveLength(15)
    expect(pageRows(rows, 3)).toEqual([30, 31, 32, 33, 34, 35, 36, 37, 38, 39])
  })
  it('หน้านอกช่วงถูกบีบเข้าช่วง', () => {
    expect(clampPage(0, 40)).toBe(1)
    expect(clampPage(9, 40)).toBe(3)
    expect(pageRows(rows, 99)[0]).toBe(30)
  })
})

describe('T04 เลือกภาคเรียน/ห้อง', () => {
  const room = (id: number, term: number, started: string, created: string): RoomOption => ({
    id: uuid(id),
    name: `ห้อง ${id}`,
    term_id: uuid(100 + term),
    created_at: created,
    terms: { name: `เทอม ${term}`, started_at: started },
  })
  it('ภาคเรียนใหม่ก่อน; ห้องในภาคเรียนเรียงตามวันสร้าง', () => {
    const g = termGroups([
      room(1, 1, '2026-05-01T00:00:00Z', '2026-05-02T00:00:00Z'),
      room(3, 2, '2026-10-01T00:00:00Z', '2026-10-05T00:00:00Z'),
      room(2, 2, '2026-10-01T00:00:00Z', '2026-10-02T00:00:00Z'),
    ])
    expect(g.map((x) => x.name)).toEqual(['เทอม 2', 'เทอม 1'])
    expect(g[0].rooms.map((r) => r.name)).toEqual(['ห้อง 2', 'ห้อง 3'])
  })
})

describe('CSV', () => {
  it('ค่าที่ขึ้นต้นด้วย = + - @ ถูกกันเป็นสูตร (รวมแท็บ/ขึ้นบรรทัดใหม่/ช่องว่างนำหน้า)', () => {
    expect(csvField('=1+1')).toBe("'=1+1")
    expect(csvField('+66')).toBe("'+66")
    expect(csvField('-2')).toBe("'-2")
    expect(csvField('@SUM(A1)')).toBe("'@SUM(A1)")
    expect(csvField('\t=1')).toBe("'\t=1")
    expect(csvField('  =cmd')).toBe("'  =cmd")
    expect(csvField('\r=1')).toBe('"\'\r=1"')
    expect(csvField('ปกติ')).toBe('ปกติ')
    expect(csvField('a=b')).toBe('a=b')
  })
  it('ครอบด้วย " เมื่อมีจุลภาค เครื่องหมายคำพูด หรือขึ้นบรรทัดใหม่ และเติม " ซ้อน', () => {
    expect(csvField('ก, ข')).toBe('"ก, ข"')
    expect(csvField('พูดว่า "สวัสดี"')).toBe('"พูดว่า ""สวัสดี"""')
    expect(csvField('บรรทัด1\nบรรทัด2')).toBe('"บรรทัด1\nบรรทัด2"')
  })
  it('ตัวเลขเขียนตรง ๆ และค่าว่างเป็นช่องว่าง', () => {
    expect(csvField(0)).toBe('0')
    expect(csvField(12)).toBe('12')
    expect(csvField(null)).toBe('')
  })
  it('ไฟล์: BOM นำหน้า, CRLF, ส่วนหัวมีคะแนนเต็ม, แยก ยังไม่ส่ง/รอตรวจ/0/ไม่มีคะแนน', () => {
    const csv = gradeCsv(table())
    expect(csv.startsWith(BOM)).toBe(true)
    const lines = csv.slice(BOM.length).split('\r\n')
    expect(lines.pop()).toBe('')
    expect(lines).toEqual([
      `เลขที่,ชื่อ-นามสกุล,สถานะในห้อง,งาน A (เต็ม 10),"'=HYPERLINK(""x"") (เต็ม 20)"`,
      '1,"สมชาย, ใจดี",อยู่ในห้อง,8,รอตรวจ',
      ",'-แทรกสูตร,ออกจากห้องแล้ว,ตรวจแล้ว (ไม่มีคะแนน),ยังไม่ส่ง",
      '3,ศูนย์ คะแนน,อยู่ในห้อง,0,ยังไม่ส่ง',
    ])
  })
  it('CSV เฉพาะงานเดียว (เก็บไว้ก่อนลบงาน): คอลัมน์ของงานนั้นเท่านั้น และชื่อไฟล์มีชื่องาน', () => {
    const lines = gradeCsv(table(), A).slice(BOM.length).split('\r\n')
    expect(lines[0]).toBe('เลขที่,ชื่อ-นามสกุล,สถานะในห้อง,งาน A (เต็ม 10)')
    expect(lines[1]).toBe('1,"สมชาย, ใจดี",อยู่ในห้อง,8')
    expect(lines[3]).toBe('3,ศูนย์ คะแนน,อยู่ในห้อง,0')
    expect(csvFileName('เคมี 5/4', '2/2569', 'งาน: ก/ข')).toBe('คะแนน_เคมี 5 4_2 2569_งาน ก ข.csv')
  })
  it('ชื่อไฟล์ CSV คงสระ/วรรณยุกต์ไทย (ตัดเฉพาะอักขระต้องห้าม)', () => {
    expect(csvFileName('อินทร์แก้ว กิ่งก้าน ๆ ศุภกฤต ณัฐพงษ์ ก็ ก์', '2/2569')).toBe(
      'คะแนน_อินทร์แก้ว กิ่งก้าน ๆ ศุภกฤต ณัฐพงษ์ ก็ ก์_2 2569.csv',
    )
  })
  it('ชื่อไฟล์ตัดอักขระต้องห้ามของ Windows', () => {
    expect(csvFileName('เคมี 5/4', '2/2569')).toBe('คะแนน_เคมี 5 4_2 2569.csv')
    expect(csvFileName('ห้อง*?', null)).toBe('คะแนน_ห้อง.csv')
  })
})
