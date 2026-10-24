import type { ChipTone } from '../../ui'
import { th } from '../../copy/th'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import type { Grade } from '../grading/api'
import type { SubmissionStatus, WorkRow } from './api'

// สถานะที่หน้าจอแสดง (UX 7) — คิดจากผลของเซิร์ฟเวอร์เท่านั้น (outcome/blocked/timing) ไม่คิดกติกาการรับงานเอง

export interface Badge {
  label: string
  tone: ChipTone
}

const copy = th.work

/** วันเวลาไทยแบบเต็ม เช่น “11 พ.ย. 20:00 น.” */
export const when = (iso: string) => `${thaiDate(iso)} ${thaiTime(iso)} น.`

/** ป้ายของการ์ดงานใน S02/S01 */
export function workBadge(row: WorkRow): Badge {
  if (!row.submitted) {
    if (row.blocked === 'term_ended') return { label: copy.label.termEnded, tone: 'plain' }
    if (row.blocked) return { label: copy.label.closed, tone: 'plain' }
    return { label: copy.label.todo, tone: 'amber' }
  }
  if (row.permission_open) return { label: copy.label.permission, tone: 'purple' }
  if (row.timing === 'late') return { label: copy.label.late, tone: 'red' }
  if ((row.content_revision ?? 1) > 1) return { label: copy.label.revised, tone: 'purple' }
  return { label: copy.label.onTime, tone: 'purple' }
}

/** งานที่ยังต้องทำ: ยังไม่ส่งและยังส่งได้ */
export const isPending = (row: WorkRow) => !row.submitted && row.outcome !== null

export type WorkFilter = 'all' | 'todo' | 'done'

export function filterWork(rows: WorkRow[], filter: WorkFilter): WorkRow[] {
  if (filter === 'todo') return rows.filter((r) => !r.submitted)
  if (filter === 'done') return rows.filter((r) => r.submitted)
  return rows
}

/** เรียงค้าง/ใกล้ส่งก่อน (UX 5): งานที่ยังต้องส่งตามกำหนดจากเร็วไปช้า แล้วงานอื่นจากกำหนดล่าสุด */
export function sortWork(rows: WorkRow[]): WorkRow[] {
  const due = (r: WorkRow) => Date.parse(r.due_at)
  const pending = rows.filter(isPending).sort((a, b) => due(a) - due(b))
  const rest = rows.filter((r) => !isPending(r)).sort((a, b) => due(b) - due(a))
  return [...pending, ...rest]
}

/** S01 “ใกล้กำหนดส่ง”: งานที่ยังต้องส่ง เรียงตามกำหนด (สูงสุด limit ชิ้น) */
export function dueSoon(rows: WorkRow[], limit = 5): WorkRow[] {
  return sortWork(rows.filter(isPending)).slice(0, limit)
}

/** S01 กล่อง “ใกล้กำหนดส่ง” ว่าง: ห้องยังไม่มีงานเลย ≠ มีงานและส่งครบแล้ว */
export function dueEmpty(rows: WorkRow[]): 'noWork' | 'allSent' {
  return rows.length ? 'allSent' : 'noWork'
}

const DAY_MS = 24 * 60 * 60 * 1000

/** ป้ายเวลาใน S01: เลยกำหนด (ยังส่งได้แบบสาย) / เหลือไม่ถึง 24 ชม. / ไม่มี */
export function dueHint(dueAt: string, now: number): 'overdue' | 'soon' | null {
  const left = Date.parse(dueAt) - now
  if (left < 0) return 'overdue'
  if (left < DAY_MS) return 'soon'
  return null
}

export const sameFiles = (a: readonly string[], b: readonly string[]) =>
  a.length === b.length && a.every((id, i) => id === b[i])

/** S03: ป้ายหัว “งานของฉัน” — หลังครูตรวจชุดล่าสุดแล้วใช้สถานะตาม UX 7 (ไม่ค้างที่ “รอครูตรวจ”) */
export function mineBadge(
  status: SubmissionStatus,
  ui: { editing: boolean; attached: boolean },
  grade: GradeView | null = null,
): Badge {
  const sub = status.submission
  if (sub && ui.editing) return { label: copy.label.editing, tone: 'amber' }
  if (!sub) {
    if (status.blocked === 'term_ended') return { label: copy.label.termEnded, tone: 'plain' }
    if (status.blocked) return { label: copy.label.closed, tone: 'plain' }
    if (ui.attached) return { label: copy.label.attached, tone: 'amber' }
    return { label: copy.label.todo, tone: 'amber' }
  }
  if (status.permission_open) return { label: copy.label.permission, tone: 'purple' }
  if (grade && !grade.stale) {
    if (!grade.passed && status.current_term && grade.score)
      return { label: copy.label.scored(grade.score.net), tone: 'amber' }
    const chip = gradeChip(grade, status)
    return { label: chip.label, tone: chip.tone }
  }
  if (sub.timing === 'late') return { label: copy.label.late, tone: 'red' }
  if (sub.content_revision > 1) return { label: copy.label.revised, tone: 'purple' }
  return { label: copy.label.onTime, tone: 'purple' }
}

/** ผลตรวจที่นักเรียนเห็น (S03 ส่วนคะแนน — UX 7): คิดจากแถว grades เทียบกับชุดที่ส่งล่าสุด */
export interface GradeView {
  /** ผลเป็นของชุดก่อนหน้า — ส่งแก้แล้วรอครูตรวจชุดใหม่ (ผลเดิมยังแสดงไว้) */
  stale: boolean
  /** ชุดที่ส่งที่ครูตรวจ */
  revision: number
  /** ครูยืนยันงานครบถ้วนแล้ว (ไม่ยืนยัน = “รอครูยืนยันความครบถ้วน” ไม่ใช้คำว่าไม่ผ่าน) */
  passed: boolean
  /** null = ครูบันทึกเฉพาะความครบถ้วน ยังไม่ให้คะแนน */
  score: { raw: number; penaltyPct: number; deduction: number; net: number } | null
  /** ครูตั้งการหักเฉพาะคน (0 = ยกเว้น) — เหตุผลอยู่ในความคิดเห็น */
  override: number | null
  late: boolean
}

export function gradeView(grade: Grade | null, currentRevision: number): GradeView | null {
  if (!grade) return null
  const { raw_score: raw, net_score: net } = grade
  return {
    stale: grade.graded_revision < currentRevision,
    revision: grade.graded_revision,
    passed: grade.passed,
    score:
      raw !== null && net !== null
        ? { raw, penaltyPct: grade.applied_penalty_pct, deduction: raw - net, net }
        : null,
    override: grade.penalty_override_pct,
    late: grade.timing === 'late',
  }
}

/** แถบขั้นตอน ส่งงาน → ครูตรวจ → งานครบถ้วน → ได้โทเคน (ขั้นสุดท้ายเมื่อเซิร์ฟเวอร์ให้รางวัลแล้ว — ไม่ถอนตาม I3) */
export function stepStates(
  status: SubmissionStatus,
  grade: GradeView | null = null,
): ('done' | 'now' | 'todo')[] {
  if (!status.submission) return ['now', 'todo', 'todo', 'todo']
  const token = status.reward_granted ? 'done' : 'todo'
  if (!grade || grade.stale) return ['done', 'now', 'todo', token]
  return grade.passed ? ['done', 'done', 'done', token] : ['done', 'done', 'now', token]
}

/** ป้ายส่วนคะแนน S03 (UX 7): ได้รางวัลแล้ว / งานภาคเรียนก่อน / ครบถ้วน / รอยืนยัน / รอตรวจชุดใหม่ */
export function gradeChip(
  view: GradeView | null,
  status: Pick<SubmissionStatus, 'reward_granted' | 'reward_tokens' | 'current_term'>,
): { label: string; tone: 'amber' | 'green' | 'plain' } {
  const g = copy.grade
  if (!view) return { label: g.waiting, tone: 'amber' }
  if (view.stale) return { label: g.staleChip, tone: 'amber' }
  if (view.passed && status.reward_granted && status.reward_tokens > 0)
    return { label: g.rewarded(status.reward_tokens), tone: 'green' }
  if (!status.current_term) return { label: g.oldTerm, tone: 'plain' }
  return view.passed ? { label: g.complete, tone: 'green' } : { label: g.pending, tone: 'amber' }
}

/** ข้อความแทนฟอร์มเมื่อส่ง/ส่งแก้ไม่ได้ตอนนี้ */
export function blockedReason(code: string): string {
  if (code === 'term_ended') return copy.lockedTermEnded
  if (code === 'resubmit_not_allowed') return copy.lockedPastDue
  if (code === 'submission_closed') return th.errors.submission_closed
  return th.errors.fallback
}
