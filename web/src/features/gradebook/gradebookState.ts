import type { Cell, GradeTable, RoomOption } from './api'

// ตารางคะแนน T04 — ตรรกะที่ไม่ผูกหน้าจอ (UX 9: แยก “ยังไม่ส่ง”, “รอตรวจ”, “0” ให้ชัด)

export type CellView =
  | { kind: 'none' }
  | { kind: 'waiting' }
  | { kind: 'noScore'; late: boolean }
  | { kind: 'score'; net: number; late: boolean }

export function cellView(cell: Cell | undefined): CellView {
  if (!cell) return { kind: 'none' }
  if (cell.state === 'waiting') return { kind: 'waiting' }
  return cell.net === null
    ? { kind: 'noScore', late: cell.late }
    : { kind: 'score', net: cell.net, late: cell.late }
}

export const PER_PAGE = 15

export function pageCount(total: number): number {
  return Math.max(1, Math.ceil(total / PER_PAGE))
}

/** หน้า (เริ่ม 1) ที่ถูกบีบให้อยู่ในช่วงที่มีจริง */
export function clampPage(page: number, total: number): number {
  return Math.min(Math.max(1, page), pageCount(total))
}

export function pageRows<T>(rows: T[], page: number): T[] {
  const p = clampPage(page, rows.length)
  return rows.slice((p - 1) * PER_PAGE, p * PER_PAGE)
}

export interface TermGroup {
  termId: string
  name: string
  rooms: RoomOption[]
}

/** ภาคเรียนที่ครูมีห้อง (ใหม่ → เก่า) พร้อมห้องในภาคเรียนนั้น (เก่า → ใหม่ตามวันสร้าง) */
export function termGroups(rooms: RoomOption[]): TermGroup[] {
  const groups = new Map<string, TermGroup & { startedAt: string }>()
  for (const r of rooms) {
    const g = groups.get(r.term_id) ?? {
      termId: r.term_id,
      name: r.terms.name,
      startedAt: r.terms.started_at,
      rooms: [],
    }
    g.rooms.push(r)
    groups.set(r.term_id, g)
  }
  return [...groups.values()]
    .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))
    .map((g) => ({
      termId: g.termId,
      name: g.name,
      rooms: [...g.rooms].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)),
    }))
}

/** จำนวนเซลล์ตามสถานะทั้งตาราง (ใช้สรุปใต้หัวตาราง) */
export function tableTotals(table: GradeTable) {
  let waiting = 0
  for (const row of table.rows)
    for (const cell of Object.values(row.cells)) if (cell.state === 'waiting') waiting += 1
  return { students: table.rows.length, assignments: table.assignments.length, waiting }
}
