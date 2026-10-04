import { ROSTER_LIMITS, type SheetCell, type SheetData } from './readSheet'

// ตัวอ่านรายชื่อตาม TECHNICAL_DESIGN ส่วน 4 — อ่านเฉพาะ 5 ช่อง ไม่อ่านคะแนน สูตร หรือคอลัมน์อื่น

export type RosterField = 'roll' | 'code' | 'prefix' | 'first' | 'last'
export const ROSTER_FIELDS: RosterField[] = ['roll', 'code', 'prefix', 'first', 'last']

/** คอลัมน์ (เริ่ม 0) ของแต่ละช่อง; null = ไม่มี/ไม่ใช้ (คำนำหน้าไม่บังคับ) */
export type ColumnMapping = Record<RosterField, number | null>

export interface DetectedLayout {
  /** แถวหัวตาราง (เริ่ม 0) */
  headerRow: number
  /** แถวแรกของรายชื่อ (เริ่ม 0) — ถัดจากหัวตารางที่อาจผสาน 2 แถว */
  dataStartRow: number
  mapping: ColumnMapping
  /** ข้อความหัวคอลัมน์ทุกคอลัมน์ (ใช้แสดงในขั้นจับคู่) */
  headers: string[]
}

/** แถวรายชื่อที่อ่านได้ ทุกช่องเป็นข้อความ (ครูแก้ในหน้าตัวอย่างได้) */
export interface RosterDraftRow {
  /** เลขแถวใน Excel (เริ่ม 1) */
  sourceRow: number
  roll: string
  code: string
  prefix: string
  first: string
  last: string
}

const compact = (s: string) => s.replace(/\s+/g, '')

export function cellText(cell: SheetCell | undefined): string {
  if (!cell || cell.v === null || cell.v === undefined) return ''
  if (typeof cell.v === 'number') return String(cell.v)
  return String(cell.v).trim()
}

// ระยะแก้ไขระหว่างข้อความ (สำหรับหัวคอลัมน์ที่สะกดผิดเล็กน้อย เช่น “เลขปประจำตัว”)
function editDistance(a: string, b: string): number {
  const prev = Array.from({ length: b.length + 1 }, (_, j) => j)
  for (let i = 1; i <= a.length; i++) {
    let diag = prev[0]
    prev[0] = i
    for (let j = 1; j <= b.length; j++) {
      const tmp = prev[j]
      prev[j] = Math.min(prev[j] + 1, prev[j - 1] + 1, diag + (a[i - 1] === b[j - 1] ? 0 : 1))
      diag = tmp
    }
  }
  return prev[b.length]
}

const isRollHeader = (h: string) => compact(h) === 'เลขที่'
const isCodeHeader = (h: string) => {
  const c = compact(h)
  return c.includes('ประจำตัว') || c.includes('รหัสนักเรียน') || editDistance(c, 'เลขประจำตัว') <= 2
}
const isNameHeader = (h: string) => compact(h).startsWith('ชื่อ')

function mergeAt(merges: SheetData['merges'], row: number, col: number) {
  return merges.find((m) => m.s.r === row && m.s.c === col)
}

// หาแถวหัวตารางจาก “เลขที่” ในไม่กี่แถวแรก แล้วเดาคอลัมน์จากหัว
// “ชื่อ - สกุล” ที่ผสาน 3 ช่อง = คำนำหน้า · ชื่อ · นามสกุล (ไฟล์จริงของครู); 2 ช่อง = ชื่อ · นามสกุล
export function detectLayout(sheet: SheetData): DetectedLayout | null {
  const { grid, merges } = sheet
  const limit = Math.min(grid.length, ROSTER_LIMITS.headerSearchRows)
  for (let r = 0; r < limit; r++) {
    const headers = (grid[r] ?? []).map(cellText)
    const roll = headers.findIndex(isRollHeader)
    if (roll < 0) continue

    const code = headers.findIndex((h, c) => c !== roll && isCodeHeader(h))
    const nameCol = headers.findIndex((h, c) => c !== roll && c !== code && isNameHeader(h))
    let prefix: number | null = null
    let first: number | null = null
    let last: number | null = null
    if (nameCol >= 0) {
      const merge = mergeAt(merges, r, nameCol)
      const span = merge ? merge.e.c - merge.s.c + 1 : 1
      const nextEmpty = !headers[nameCol + 1] && !headers[nameCol + 2]
      if (span >= 3 || (span === 1 && nextEmpty)) {
        prefix = nameCol
        first = nameCol + 1
        last = nameCol + 2
      } else if (span === 2) {
        first = nameCol
        last = nameCol + 1
      }
    }

    const rollMerge = mergeAt(merges, r, roll)
    const headerHeight = rollMerge ? rollMerge.e.r - rollMerge.s.r + 1 : 1
    const width = Math.max(...grid.slice(r, r + 50).map((row) => row?.length ?? 0), headers.length)
    return {
      headerRow: r,
      dataStartRow: r + headerHeight,
      mapping: { roll, code: code >= 0 ? code : null, prefix, first, last },
      headers: Array.from({ length: width }, (_, c) => headers[c] ?? ''),
    }
  }
  return null
}

// อ่านแถวรายชื่อตั้งแต่ dataStartRow จนเจอแถวที่ 5 ช่องว่างทั้งหมด
// ไม่อ่านคอลัมน์อื่นเลย (คะแนน สูตร ช่องสรุปข้างแถว คอลัมน์ “ประเภท”)
export function extractRows(
  sheet: SheetData,
  dataStartRow: number,
  mapping: ColumnMapping,
): { rows: RosterDraftRow[]; tooMany: boolean } {
  const read = (row: (SheetCell | undefined)[] | undefined, col: number | null) =>
    col === null ? '' : cellText(row?.[col])
  const rows: RosterDraftRow[] = []
  for (let r = dataStartRow; r < sheet.grid.length; r++) {
    const row = sheet.grid[r]
    const draft: RosterDraftRow = {
      sourceRow: r + 1,
      roll: read(row, mapping.roll),
      code: read(row, mapping.code),
      prefix: read(row, mapping.prefix),
      first: read(row, mapping.first),
      last: read(row, mapping.last),
    }
    if (!draft.roll && !draft.code && !draft.prefix && !draft.first && !draft.last) break
    rows.push(draft)
  }
  return {
    rows: rows.slice(0, ROSTER_LIMITS.maxStudents),
    tooMany: rows.length > ROSTER_LIMITS.maxStudents || sheet.truncated,
  }
}

// เดาห้องจากชื่อไฟล์ เช่น “รายชื่อ 5-2.xlsx” → “ม.5/2” [ข้อเสนอ] ให้ครูยืนยัน/แก้
export function guessGroupName(fileName: string): string {
  const m = fileName.match(/(?:^|[^0-9])([1-6])\s*[-_/.]\s*(\d{1,2})(?![0-9])/)
  return m ? `ม.${m[1]}/${Number(m[2])}` : ''
}

/** ชื่อคอลัมน์แบบ Excel (A, B, …) */
export function columnLetter(col: number): string {
  let s = ''
  for (let n = col + 1; n > 0; n = Math.floor((n - 1) / 26))
    s = String.fromCharCode(65 + ((n - 1) % 26)) + s
  return s
}
