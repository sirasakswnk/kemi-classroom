import { th } from '../../copy/th'
import type { RosterDraftRow } from './parseRoster'

// ตรวจรายชื่อก่อนส่งให้เซิร์ฟเวอร์ (กติกาเดียวกับ private.roster_import_plan ใน 0003_roster.sql)
// แล้วเพิ่มข้อที่ต้องให้ครูดูเอง: เลขประจำตัวยาวไม่เท่าคนอื่น (อาจพิมพ์เกินหรือ Excel ตัดศูนย์นำหน้า) — ไม่เดารหัสแทน
// และชื่อ/นามสกุลที่มีช่องว่างแทรก (P7-06a เช่น “อิ นทร์แก้ว”, “ศร ีสมบูรณ์” — ทำให้ค้นชื่อตอนผูกบัญชีไม่เจอ
// และชื่อไฟล์ PDF เพี้ยน) — เสนอค่าที่ตัดช่องว่าง แต่ไม่แก้เอง ครูเลือกใช้ค่าเสนอหรือคงค่าเดิมทีละช่อง

export type IssueField = 'roll' | 'code' | 'first' | 'last'
export type IssueKind =
  | 'roll_required'
  | 'roll_invalid'
  | 'roll_duplicate'
  | 'roll_taken'
  | 'code_required'
  | 'code_invalid'
  | 'code_duplicate'
  | 'code_length'
  | 'name_required'
  | 'name_spacing'

export interface RosterIssue {
  /** ตำแหน่งในรายการ (ไม่ใช่เลขแถว Excel) */
  index: number
  field: IssueField
  kind: IssueKind
  message: string
  /** code_length ยืนยันว่าถูกต้องได้ ข้ออื่นต้องแก้ */
  confirmable: boolean
  /** name_spacing: ค่าที่เสนอ (ตัดช่องว่างทั้งหมด) — ครูกดใช้หรือเลือกคงค่าเดิม */
  suggestion?: string
}

// ช่องว่างทุกแบบรวมช่องว่างที่มองไม่เห็น (NBSP, zero-width) — trim() ตัดได้แค่หัวท้ายบางตัว
const SPACING = /[\s\u00a0\u200b-\u200d\u2060\ufeff]/
const SPACING_ALL = /[\s\u00a0\u200b-\u200d\u2060\ufeff]+/g

/** ชื่อ/นามสกุลที่มีช่องว่างอยู่ข้างใน → ค่าที่เสนอ (ตัดออกทั้งหมด) · ไม่มี = null */
export function spacingSuggestion(name: string): string | null {
  return SPACING.test(name) ? name.replace(SPACING_ALL, '') : null
}

/** กุญแจของช่องชื่อที่ครูเลือกคงค่าเดิม */
export const nameKey = (index: number, field: 'first' | 'last') => `${index}:${field}`

export const isRollText = (s: string) => /^[0-9]{1,3}$/.test(s) && Number(s) >= 1
export const isCodeText = (s: string) => /^[0-9]{1,20}$/.test(s)

export function rowLabel(row: RosterDraftRow): string {
  const name = [row.first, row.last].filter(Boolean).join(' ')
  return name ? th.roster.rowLabel(row.sourceRow, name) : th.roster.rowLabelNoName(row.sourceRow)
}

// ความยาวเลขประจำตัวที่พบบ่อยที่สุด (ต้องมีอย่างน้อย 3 คนจึงถือเป็นแบบแผน)
function commonCodeLength(rows: RosterDraftRow[]): number | null {
  const counts = new Map<number, number>()
  for (const r of rows)
    if (isCodeText(r.code)) counts.set(r.code.length, (counts.get(r.code.length) ?? 0) + 1)
  let best: [number, number] | null = null
  for (const entry of counts) if (!best || entry[1] > best[1]) best = entry
  return best && best[1] >= 3 ? best[0] : null
}

/**
 * @param confirmedCodes เลขแถว (index) ที่ครูยืนยันว่าเลขประจำตัวยาวไม่เท่าคนอื่นแต่ถูกต้อง
 * @param keptNames ช่องชื่อ (nameKey) ที่ครูเลือกคงค่าเดิมแม้มีช่องว่างแทรก
 */
export function validateRoster(
  rows: RosterDraftRow[],
  confirmedCodes: ReadonlySet<number> = new Set(),
  keptNames: ReadonlySet<string> = new Set(),
): RosterIssue[] {
  const issues: RosterIssue[] = []
  const add = (
    index: number,
    field: IssueField,
    kind: IssueKind,
    message: string,
    confirmable = false,
    suggestion?: string,
  ) =>
    issues.push({
      index,
      field,
      kind,
      message,
      confirmable,
      ...(suggestion === undefined ? {} : { suggestion }),
    })

  const byRoll = new Map<string, number[]>()
  const byCode = new Map<string, number[]>()
  rows.forEach((r, i) => {
    if (isRollText(r.roll))
      byRoll.set(String(Number(r.roll)), [...(byRoll.get(String(Number(r.roll))) ?? []), i])
    if (isCodeText(r.code)) byCode.set(r.code, [...(byCode.get(r.code) ?? []), i])
  })
  const common = commonCodeLength(rows)
  const others = (group: number[] | undefined, i: number) => (group ?? []).filter((j) => j !== i)

  rows.forEach((r, i) => {
    if (!r.roll) add(i, 'roll', 'roll_required', th.roster.issues.roll_required)
    else if (!isRollText(r.roll)) add(i, 'roll', 'roll_invalid', th.roster.issues.roll_invalid)
    else {
      const dup = others(byRoll.get(String(Number(r.roll))), i)
      if (dup.length)
        add(i, 'roll', 'roll_duplicate', th.roster.issues.roll_duplicate(rowLabel(rows[dup[0]])))
    }

    if (!r.code) add(i, 'code', 'code_required', th.roster.issues.code_required)
    else if (!isCodeText(r.code)) add(i, 'code', 'code_invalid', th.roster.issues.code_invalid)
    else {
      const dup = others(byCode.get(r.code), i)
      if (dup.length)
        add(i, 'code', 'code_duplicate', th.roster.issues.code_duplicate(rowLabel(rows[dup[0]])))
      else if (common !== null && r.code.length !== common && !confirmedCodes.has(i)) {
        add(i, 'code', 'code_length', th.roster.issues.code_length(r.code.length, common), true)
      }
    }

    if (!r.first) add(i, 'first', 'name_required', th.roster.issues.name_required)
    else if (!r.last) add(i, 'last', 'name_required', th.roster.issues.name_required)

    for (const field of ['first', 'last'] as const) {
      const suggestion = spacingSuggestion(r[field])
      if (suggestion && !keptNames.has(nameKey(i, field)))
        add(i, field, 'name_spacing', th.roster.issues.name_spacing(suggestion), true, suggestion)
    }
  })
  return issues
}

/** ข้อมูลที่ส่งขึ้นเซิร์ฟเวอร์: 5 ช่องเท่านั้น เลขประจำตัวเป็นข้อความเสมอ */
export interface RosterPayloadRow {
  row: number
  roll_number: number
  student_code: string
  name_prefix: string | null
  first_name: string
  last_name: string
}

export function toPayload(rows: RosterDraftRow[]): RosterPayloadRow[] {
  return rows.map((r) => ({
    row: r.sourceRow,
    roll_number: Number(r.roll),
    student_code: r.code,
    name_prefix: r.prefix || null,
    first_name: r.first,
    last_name: r.last,
  }))
}
