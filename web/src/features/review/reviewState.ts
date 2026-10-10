import { th } from '../../copy/th'
import type { ChipTone } from '../../ui'
import type { Intake, StatusRow } from './api'

// สถานะที่ครูเห็น (UX 9, แบบ v2 phaseChip/statusChips/tStatus) — คิดจากผลของเซิร์ฟเวอร์ (intake, timing, graded)

const copy = th.review

export interface Badge {
  label: string
  tone: ChipTone
}

/** สถานะรับงานของงาน: เปิดรับ / ครบกำหนดแต่ยังไม่ปิดรับ / ปิดรับแล้ว / รับหลังเฉลย */
export function phaseBadge(intake: Intake, dueAt: string, now: number): Badge {
  if (intake === 'closed') return { label: copy.phase.closed, tone: 'plain' }
  if (intake === 'after_solution') return { label: copy.phase.afterSolution, tone: 'green' }
  if (now <= Date.parse(dueAt)) return { label: copy.phase.open, tone: 'amber' }
  return { label: copy.phase.dueOpen, tone: 'purple' }
}

export type StatusFilter = 'all' | 'sub' | 'not'
export const STATUS_FILTERS: StatusFilter[] = ['all', 'sub', 'not']

export function parseFilter(value: string | null): StatusFilter {
  return value === 'sub' || value === 'not' ? value : 'all'
}

export function filterRows(rows: StatusRow[], filter: StatusFilter): StatusRow[] {
  if (filter === 'sub') return rows.filter((r) => r.submission_id)
  if (filter === 'not') return rows.filter((r) => !r.submission_id)
  return rows
}

export const PAGE_SIZE = 15

/** หน้าที่ขอ (1 ขึ้นไป) ตัดให้อยู่ในช่วง แล้วคืนแถวของหน้านั้น */
export function paginate<T>(rows: T[], page: number, size = PAGE_SIZE) {
  const pages = Math.max(1, Math.ceil(rows.length / size))
  const current = Math.min(Math.max(1, Number.isFinite(page) ? Math.floor(page) : 1), pages)
  const from = (current - 1) * size
  return { page: current, pages, from, rows: rows.slice(from, from + size) }
}

/** ป้ายสถานะของแถวในตาราง T03 */
export function rowBadges(row: StatusRow): Badge[] {
  const out: Badge[] = []
  if (!row.submission_id) out.push({ label: copy.status.not, tone: 'plain' })
  else if ((row.content_revision ?? 1) > 1)
    out.push({ label: copy.status.revised(row.content_revision ?? 2), tone: 'purple' })
  else out.push({ label: copy.status.submitted, tone: 'purple' })
  if (row.timing === 'late') out.push({ label: copy.status.late, tone: 'red' })
  if (!row.member) out.push({ label: copy.status.left, tone: 'outline' })
  return out
}

export interface Counts {
  total: number
  submitted: number
  not: number
  waiting: number
  late: number
}

export function countRows(rows: StatusRow[]): Counts {
  const submitted = rows.filter((r) => r.submission_id)
  return {
    total: rows.length,
    submitted: submitted.length,
    not: rows.length - submitted.length,
    waiting: submitted.filter((r) => !r.graded).length,
    late: submitted.filter((r) => r.timing === 'late').length,
  }
}

export const isImage = (contentType: string) => contentType.startsWith('image/')
