import { th } from '../../copy/th'
import { downloadBlob } from '../../lib/download'
import type { GradeTable } from './api'
import { cellView } from './gradebookState'

// ส่งออก CSV ของตารางคะแนน (TECHNICAL_BUILD_PLAN: UTF-8 BOM เปิดใน Excel แล้วภาษาไทยถูก)
// ค่าข้อความที่ขึ้นต้นด้วย = + - @ (หรือแท็บ/ขึ้นบรรทัดใหม่ แม้มีช่องว่างนำหน้า) ถูกนำหน้าด้วย ' กันไม่ให้ Excel ตีความเป็นสูตร (CSV injection)
// ตัวเลขคะแนนเป็นจำนวนเต็มไม่ติดลบที่เรานำเข้าเอง จึงเขียนตรง ๆ ให้ Excel นับเป็นตัวเลข

export const BOM = String.fromCharCode(0xfeff)
const FORMULA_START = /^[\t\r\n ]*[=+\-@]|^[\t\r]/

export function csvField(value: string | number | null): string {
  if (value === null) return ''
  if (typeof value === 'number') return String(value)
  const safe = FORMULA_START.test(value) ? `'${value}` : value
  return /[",\r\n]/.test(safe) ? `"${safe.replaceAll('"', '""')}"` : safe
}

export function gradeCsv(table: GradeTable): string {
  const copy = th.gradebook.csv
  const head = [
    copy.roll,
    copy.name,
    copy.membership,
    ...table.assignments.map((a) => copy.column(a.title, a.full_score)),
  ]
  const lines = [head.map(csvField).join(',')]
  for (const row of table.rows) {
    const cells = table.assignments.map((a) => {
      const v = cellView(row.cells[a.post_id])
      if (v.kind === 'none') return copy.notSubmitted
      if (v.kind === 'waiting') return copy.waiting
      if (v.kind === 'noScore') return copy.noScore
      return v.net
    })
    lines.push(
      [row.roll_number, row.display_name, row.member ? copy.member : copy.left, ...cells]
        .map(csvField)
        .join(','),
    )
  }
  return `${BOM}${lines.join('\r\n')}\r\n`
}

/** ชื่อไฟล์ปลอดภัยกับ Windows: ตัดอักขระต้องห้ามออก */
export function csvFileName(room: string, term: string | null): string {
  const clean = (s: string) =>
    s
      .replace(/[\\/:*?"<>|]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  return `${[th.gradebook.csv.filePrefix, clean(room), term ? clean(term) : ''].filter(Boolean).join('_')}.csv`
}

/** ดาวน์โหลด CSV ผ่าน Blob (ไม่ผ่านเซิร์ฟเวอร์ — ข้อมูลนักเรียนอยู่ในหน้านี้อยู่แล้ว) */
export function downloadCsv(fileName: string, csv: string) {
  downloadBlob(fileName, new Blob([csv], { type: 'text/csv;charset=utf-8' }))
}
