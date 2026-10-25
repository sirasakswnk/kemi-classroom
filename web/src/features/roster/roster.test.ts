/// <reference types="node" />
// ทดสอบตัวอ่านรายชื่อด้วยไฟล์สมมติใน exports/sample-roster/ เท่านั้น (ห้ามใช้ไฟล์จริงของครู)
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import * as XLSX from 'xlsx'
import { describe, expect, it } from 'vitest'
import { detectLayout, extractRows, guessGroupName, type RosterDraftRow } from './parseRoster'
import { readSheet } from './readSheet'
import { nameKey, rowLabel, spacingSuggestion, toPayload, validateRoster } from './validateRoster'

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

/** คำเตือนช่องว่างกลางชื่อเป็น “เลขที่:ช่อง:ค่าเสนอ” และไม่มีข้ออื่น */
function spacing(rows: RosterDraftRow[]) {
  const issues = validateRoster(rows)
  expect(issues.every((i) => i.kind === 'name_spacing')).toBe(true)
  return issues.map((i) => `${rows[i.index].roll}:${i.field}:${i.suggestion}`)
}

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
    // ช่องว่างกลางนามสกุลเป็นคำเตือนพร้อมค่าเสนอ (P7-06a) — ไม่แก้ให้เอง
    expect(spacing(rows)).toEqual(['6:last:อินทร์แก้ว', '34:last:สายสุวรรณ'])
  })

  it('5-3: หัว “เลขปประจำตัว” ที่สะกดผิดยังจับเป็นเลขประจำตัว และตัดช่องว่างหน้านามสกุล', async () => {
    const { layout, rows } = await loadSample('sample-roster-5-3-FAKE.xlsx')
    expect(layout.headers[1]).toBe('เลขปประจำตัว')
    expect(layout.mapping.code).toBe(1)
    expect(rows).toHaveLength(48)
    expect(byRoll(rows, '48').last).toBe('แสงทอง')
    expect(spacing(rows)).toEqual(['23:last:ดวงดี'])
  })

  it('5-4: คอลัมน์ “ประเภท” ที่ทำให้คะแนนเลื่อนไม่ถูกอ่าน', async () => {
    const { layout, rows } = await loadSample('sample-roster-5-4-FAKE.xlsx')
    expect(layout.mapping).toEqual({ roll: 0, code: 1, prefix: 2, first: 3, last: 4 })
    expect(layout.headers[5]).toBe('ประเภท')
    expect(rows).toHaveLength(28)
    expect(JSON.stringify(rows)).not.toContain('ไป - กลับ')
    expect(spacing(rows)).toEqual(['13:last:ศรีสมบูรณ์'])
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
  it('ครบ 5 จุด: รหัสซ้ำ (5–6), ชื่อว่าง (10), เลขที่ซ้ำ (12), รหัสข้อความมีศูนย์นำหน้า (18), รหัสว่าง (23)', async () => {
    const { rows } = await loadSample('sample-roster-errors-FAKE.xlsx')
    expect(rows).toHaveLength(47)
    const issues = validateRoster(rows)
    const summary = issues.map((i) => `${rows[i.index].roll}:${i.kind}`).sort()
    expect(summary).toEqual(
      [
        '5:code_duplicate',
        '6:code_duplicate',
        '10:name_required',
        '12:roll_duplicate',
        '12:roll_duplicate',
        '18:code_length',
        '23:code_required',
        '6:name_spacing',
        '34:name_spacing',
      ].sort(),
    )
  })

  it('ข้อความไทยที่ครูเข้าใจ บอกแถว Excel และชื่อ', async () => {
    const { rows } = await loadSample('sample-roster-errors-FAKE.xlsx')
    const issues = validateRoster(rows)
    const message = (roll: string, kind: string) =>
      issues.find((i) => rows[i.index].roll === roll && i.kind === kind)!.message
    const label = (roll: string) => rowLabel(rows.find((r) => r.roll === roll)!)
    expect(message('5', 'code_duplicate')).toBe('เลขประจำตัวซ้ำกับ แถว 8 · อนุชา อิ นทร์แก้ว')
    expect(message('10', 'name_required')).toBe('ไม่มีชื่อหรือนามสกุล')
    expect(label('10')).toBe('แถว 12 · สุขสวัสดิ์')
    expect(message('12', 'roll_duplicate')).toMatch(/^เลขที่ซ้ำกับ แถว 1[45] · /)
    expect(message('23', 'code_required')).toBe('ไม่มีเลขประจำตัว')
    expect(label('23')).toBe('แถว 25 · ณัฐธิดา แก้วมณี')
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
})

describe('P7-06a ช่องว่างกลางชื่อ และหัวแยกคำนำหน้า/ชื่อ/นามสกุล', () => {
  // หัวตารางแถวเดียว คนละคอลัมน์ (แบบไฟล์ทดสอบ 18 ต.ค. ที่เดิมต้องจับคู่คอลัมน์เอง) + คะแนนท้ายแถว
  function separateXlsx(headers: string[], rows: unknown[][]): ArrayBuffer {
    const book = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet([headers, ...rows]), 'S')
    return XLSX.write(book, { type: 'array', bookType: 'xlsx' }) as ArrayBuffer
  }

  it('หัว เลขที่ | เลขประจำตัว | คำนำหน้า | ชื่อ | นามสกุล จับเองได้ ไม่อ่านคะแนน', async () => {
    const { layout, rows } = await load(
      separateXlsx(
        ['เลขที่', 'เลขประจำตัว', 'คำนำหน้า', 'ชื่อ', 'นามสกุล', 'คะแนน'],
        [
          [1, 90001, 'นาย', 'อนุชา', 'อิ นทร์แก้ว', 9.5],
          [2, 90002, 'นางสาว', 'ณัฐธิดา', 'แก้วมณี', 8],
        ],
      ),
    )
    expect(layout.dataStartRow).toBe(1)
    expect(layout.mapping).toEqual({ roll: 0, code: 1, prefix: 2, first: 3, last: 4 })
    expect(rows[1]).toEqual({
      sourceRow: 3,
      roll: '2',
      code: '90002',
      prefix: 'นางสาว',
      first: 'ณัฐธิดา',
      last: 'แก้วมณี',
    })
    expect(JSON.stringify(toPayload(rows))).not.toContain('9.5')
    expect(spacing(rows)).toEqual(['1:last:อินทร์แก้ว'])
  })

  it.each([
    [
      ['เลขที่', 'รหัสนักเรียน', 'คำนำหน้าชื่อ', 'ชื่อจริง', 'สกุล'],
      { prefix: 2, first: 3, last: 4 },
    ],
    [['เลขที่', 'เลขประจำตัว', 'ชื่อ', 'นามสกุล'], { prefix: null, first: 2, last: 3 }],
    [['ชื่อ', 'นามสกุล', 'คำนำหน้า', 'เลขที่', 'เลขประจำตัว'], { prefix: 2, first: 0, last: 1 }],
  ])('หัวแบบอื่น %j', async (headers, expected) => {
    const { layout } = await load(separateXlsx(headers, [[1, 2, 3, 4, 5]]))
    expect(layout.mapping).toMatchObject(expected)
  })

  it('ครูเลือกได้ทีละช่อง: ใช้ค่าเสนอ หรือคงค่าเดิม — ค่าในรายการไม่ถูกแก้เอง', async () => {
    const { rows } = await loadSample('sample-roster-5-2-FAKE.xlsx')
    const i6 = rows.findIndex((r) => r.roll === '6')
    const i34 = rows.findIndex((r) => r.roll === '34')
    expect(toPayload(rows)[i6].last_name).toBe('อิ นทร์แก้ว')
    // ใช้ค่าเสนอกับเลขที่ 6 (หน้าเว็บแก้ช่องเป็นค่าเสนอ) · คงค่าเดิมของเลขที่ 34
    const edited = rows.map((r, i) => (i === i6 ? { ...r, last: 'อินทร์แก้ว' } : r))
    expect(validateRoster(edited, new Set(), new Set([nameKey(i34, 'last')]))).toEqual([])
    expect(toPayload(edited)[i34].last_name).toBe('สา ยสุวรรณ')
    // คงค่าเดิมแค่ช่องนามสกุล ไม่ครอบช่องชื่อของแถวเดียวกัน
    expect(validateRoster(rows, new Set(), new Set([nameKey(i6, 'first')]))).toHaveLength(2)
  })

  it('ช่องว่างที่มองไม่เห็น (NBSP, zero-width) ก็เตือน · ค่าเสนอตัดออกทั้งหมด', () => {
    expect(spacingSuggestion('ศร\u00a0ีสมบูรณ์')).toBe('ศรีสมบูรณ์')
    expect(spacingSuggestion('แก้ว\u200bมณี')).toBe('แก้วมณี')
    expect(spacingSuggestion('ดว  งดี')).toBe('ดวงดี')
    expect(spacingSuggestion('แก้วมณี')).toBeNull()
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
