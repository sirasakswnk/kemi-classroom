/// <reference types="node" />
// ทดสอบตัวอ่านรายชื่อด้วยไฟล์สมมติใน exports/sample-roster/ เท่านั้น (ห้ามใช้ไฟล์จริงของครู)
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import * as XLSX from 'xlsx'
import { describe, expect, it } from 'vitest'
import { detectLayout, extractRows, guessGroupName, type RosterDraftRow } from './parseRoster'
import { readSheet } from './readSheet'
import { toPayload, validateRoster } from './validateRoster'

const SAMPLES = resolve(process.cwd(), '../exports/sample-roster')

async function load(buffer: ArrayBuffer | Buffer) {
  const data = buffer instanceof ArrayBuffer ? buffer : new Uint8Array(buffer).buffer
  const sheet = await readSheet(data)
  const layout = detectLayout(sheet)
  if (!layout) throw new Error('ไม่พบหัวตาราง')
  const { rows, tooMany } = extractRows(sheet, layout.dataStartRow, layout.mapping)
  return { sheet, layout, rows, tooMany }
}
const loadSample = (name: string) => load(readFileSync(resolve(SAMPLES, name)))

// สร้างไฟล์ .xlsx ในหน่วยความจำ (หัวตาราง 2 แถวแบบไฟล์ของครู)
function buildXlsx(rows: unknown[][]): ArrayBuffer {
  const sheet = XLSX.utils.aoa_to_sheet([
    ['เลขที่', 'เลขประจำตัว', 'ชื่อ - สกุล', null, null, 'กา'],
    [],
    ...rows,
  ])
  sheet['!merges'] = [
    { s: { r: 0, c: 0 }, e: { r: 1, c: 0 } },
    { s: { r: 0, c: 1 }, e: { r: 1, c: 1 } },
    { s: { r: 0, c: 2 }, e: { r: 1, c: 4 } },
  ]
  const book = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(book, sheet, 'Sheet1')
  return XLSX.write(book, { type: 'array', bookType: 'xlsx' }) as ArrayBuffer
}

const byRoll = (rows: RosterDraftRow[], roll: string) => rows.find((r) => r.roll === roll)!

describe('ไฟล์ปกติ', () => {
  it('5-2: หัวตาราง 2 แถว คำนำหน้า/ชื่อ/นามสกุล 3 ช่อง ตัดช่องว่างหัวท้าย คงช่องว่างกลางคำ', async () => {
    const { layout, rows, tooMany } = await loadSample('sample-roster-5-2-FAKE.xlsx')
    expect(layout.headerRow).toBe(0)
    expect(layout.dataStartRow).toBe(2)
    expect(layout.mapping).toEqual({ roll: 0, code: 1, prefix: 2, first: 3, last: 4 })
    expect(rows).toHaveLength(47)
    expect(tooMany).toBe(false)
    expect(rows[0]).toEqual({
      sourceRow: 3,
      roll: '1',
      code: '90009',
      prefix: 'นาย',
      first: 'ณัฐวุฒิ',
      last: 'จันทร์เพ็ญ',
    })
    expect(byRoll(rows, '21').first).toBe('วีรภัทร')
    expect(byRoll(rows, '6').last).toBe('อิ นทร์แก้ว')
    expect(validateRoster(rows)).toEqual([])
  })

  it('5-3: หัว “เลขปประจำตัว” ที่สะกดผิดยังจับเป็นเลขประจำตัว และตัดช่องว่างหน้านามสกุล', async () => {
    const { layout, rows } = await loadSample('sample-roster-5-3-FAKE.xlsx')
    expect(layout.headers[1]).toBe('เลขปประจำตัว')
    expect(layout.mapping.code).toBe(1)
    expect(rows).toHaveLength(48)
    expect(byRoll(rows, '48').last).toBe('แสงทอง')
    expect(validateRoster(rows)).toEqual([])
  })

  it('5-4: คอลัมน์ “ประเภท” ที่ทำให้คะแนนเลื่อนไม่ถูกอ่าน', async () => {
    const { layout, rows } = await loadSample('sample-roster-5-4-FAKE.xlsx')
    expect(layout.mapping).toEqual({ roll: 0, code: 1, prefix: 2, first: 3, last: 4 })
    expect(layout.headers[5]).toBe('ประเภท')
    expect(rows).toHaveLength(28)
    expect(JSON.stringify(rows)).not.toContain('ไป - กลับ')
    expect(validateRoster(rows)).toEqual([])
  })

  it('ส่งขึ้นเซิร์ฟเวอร์เฉพาะ 5 ช่อง (+ เลขแถว) เลขประจำตัวเป็นข้อความ ไม่มีคะแนน', async () => {
    const { rows } = await loadSample('sample-roster-5-2-FAKE.xlsx')
    const payload = toPayload(rows)
    expect(Object.keys(payload[0]).sort()).toEqual(
      ['first_name', 'last_name', 'name_prefix', 'roll_number', 'row', 'student_code'].sort(),
    )
    expect(payload.every((p) => typeof p.student_code === 'string')).toBe(true)
    // คะแนนในไฟล์ (เช่น 9.5, 7.5) ต้องไม่หลุดไปในข้อมูลที่ส่ง
    expect(JSON.stringify(payload)).not.toMatch(/9\.5|7\.5|13\.5/)
  })
})

describe('ไฟล์ errors (README: exports/sample-roster/README.md)', () => {
  it('เลขประจำตัวซ้ำ (เลขที่ 5–6), เลขที่ซ้ำ (12) และรหัสข้อความมีศูนย์นำหน้า (18) พร้อมข้อความไทย', async () => {
    const { rows } = await loadSample('sample-roster-errors-FAKE.xlsx')
    const issues = validateRoster(rows)
    const summary = issues.map((i) => `${rows[i.index].roll}:${i.kind}`).sort()
    expect(summary).toEqual(
      [
        '5:code_duplicate',
        '6:code_duplicate',
        '12:roll_duplicate',
        '12:roll_duplicate',
        '18:code_length',
      ].sort(),
    )
    const dup = issues.find((i) => i.kind === 'code_duplicate' && rows[i.index].roll === '5')!
    expect(dup.message).toBe('เลขประจำตัวซ้ำกับ แถว 8 · อนุชา อิ นทร์แก้ว')
    const length = issues.find((i) => i.kind === 'code_length')!
    expect(rows[length.index].code).toBe('090174')
    expect(length.confirmable).toBe(true)
    expect(length.message).toContain('6 หลัก ต่างจากคนอื่นที่มี 5 หลัก')
  })

  it('รหัสที่มีศูนย์นำหน้าเก็บตามไฟล์ ไม่เดาแทน: ยืนยันแล้วส่ง “090174” ตามเดิม', async () => {
    const { rows } = await loadSample('sample-roster-errors-FAKE.xlsx')
    const index = rows.findIndex((r) => r.code === '090174')
    expect(validateRoster(rows, new Set([index])).some((i) => i.kind === 'code_length')).toBe(false)
    expect(toPayload(rows)[index].student_code).toBe('090174')
  })

  // README ระบุ “ชื่อว่าง (เลขที่ 10)” และ “เลขประจำตัวว่าง (เลขที่ 23)” แต่ไฟล์ปัจจุบันยังไม่มีสองจุดนี้
  // (เทียบกับ 5-2 แล้วต่างแค่ B8, A15, B20) — ทดสอบด้วยไฟล์ที่สร้างในหน่วยความจำแทนจนกว่าไฟล์ตัวอย่างจะถูกแก้
  it('ชื่อว่างและเลขประจำตัวว่าง (ไฟล์สร้างในเทสต์)', async () => {
    const { rows } = await load(
      buildXlsx([
        [1, 90001, 'นาย', 'สมชาย', 'ใจดี', 9.5],
        [2, 90002, 'นางสาว', '', '', 7],
        [3, null, 'นาย', 'ปิติ', 'ยินดี', 8],
        [4, 90004, 'นาย', 'มานะ', 'ขยัน', 6],
      ]),
    )
    expect(rows).toHaveLength(4)
    const issues = validateRoster(rows).map((i) => `${rows[i.index].roll}:${i.kind}:${i.message}`)
    expect(issues).toEqual([
      '2:name_required:ไม่มีชื่อหรือนามสกุล',
      '3:code_required:ไม่มีเลขประจำตัว',
    ])
  })
})

describe('ขอบเขตและการเดา', () => {
  it('เกิน 300 รายชื่อ: อ่านแค่ 300 และแจ้งให้แยกไฟล์', async () => {
    const many = Array.from({ length: 301 }, (_, i) => [i + 1, 91000 + i, 'นาย', 'ก', 'ข'])
    const { rows, tooMany } = await load(buildXlsx(many))
    expect(rows).toHaveLength(300)
    expect(tooMany).toBe(true)
  })

  it('ไม่มีหัว “เลขที่” = หาหัวตารางไม่เจอ', async () => {
    const book = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(
      book,
      XLSX.utils.aoa_to_sheet([
        ['ลำดับ', 'ชื่อ'],
        [1, 'ก'],
      ]),
      'S',
    )
    const sheet = await readSheet(
      XLSX.write(book, { type: 'array', bookType: 'xlsx' }) as ArrayBuffer,
    )
    expect(detectLayout(sheet)).toBeNull()
  })

  it.each([
    ['sample-roster-5-2-FAKE.xlsx', 'ม.5/2'],
    ['รายชื่อ ม.5-4.xlsx', 'ม.5/4'],
    ['คะแนนเคมี 5_3 ภาค2.xlsx', 'ม.5/3'],
    ['roster.xlsx', ''],
  ])('เดาห้องจากชื่อไฟล์ %s → %j', (name, group) => {
    expect(guessGroupName(name)).toBe(group)
  })
})
