import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import type { Grade } from '../grading/api'
import type { SubmissionStatus, WorkRow } from './api'
import {
  blockedReason,
  dueEmpty,
  dueHint,
  dueSoon,
  filterWork,
  gradeChip,
  gradeView,
  isPending,
  mineBadge,
  sameFiles,
  sortWork,
  stepStates,
  when,
  workBadge,
} from './workState'

const row = (over: Partial<WorkRow> = {}): WorkRow => ({
  post_id: '00000000-0000-4000-8000-000000000001',
  classroom_id: '00000000-0000-4000-8000-0000000000c1',
  classroom_name: 'เคมี ม.5/1',
  title: 'งาน',
  due_at: '2026-11-10T13:00:00Z',
  close_at: null,
  reward_tokens: 1,
  submitted: false,
  timing: null,
  last_submitted_at: null,
  content_revision: null,
  permission_open: false,
  outcome: 'first_on_time',
  blocked: null,
  ...over,
})

const status = (over: Partial<SubmissionStatus> = {}): SubmissionStatus => ({
  assignment_id: '00000000-0000-4000-8000-000000000001',
  classroom_id: '00000000-0000-4000-8000-0000000000c1',
  server_now: '2026-11-09T00:00:00Z',
  due_at: '2026-11-10T13:00:00Z',
  close_at: null,
  intake: 'open',
  solution_published: false,
  permission_open: false,
  outcome: 'first_on_time',
  blocked: null,
  reward_tokens: 2,
  reward_granted: false,
  current_term: true,
  submission: null,
  ...over,
})

const submitted = (over: Partial<NonNullable<SubmissionStatus['submission']>> = {}) => ({
  submission_id: '00000000-0000-4000-8000-0000000000aa',
  content_revision: 1,
  first_submitted_at: '2026-11-09T01:00:00Z',
  last_submitted_at: '2026-11-09T01:00:00Z',
  first_after_solution: false,
  timing: 'on_time' as const,
  files: [],
  ...over,
})

describe('workBadge (การ์ดงาน S02/S01 — UX 7)', () => {
  it('ยังไม่ส่งและส่งได้ = ยังไม่ส่ง (เหลือง)', () => {
    expect(workBadge(row())).toEqual({ label: th.work.label.todo, tone: 'amber' })
  })
  it('ยังไม่ส่งแต่ส่งไม่ได้แล้ว = ปิดรับแล้ว / ภาคเรียนจบแล้ว', () => {
    expect(workBadge(row({ outcome: null, blocked: 'submission_closed' })).label).toBe(
      th.work.label.closed,
    )
    expect(workBadge(row({ outcome: null, blocked: 'term_ended' })).label).toBe(
      th.work.label.termEnded,
    )
  })
  it('ส่งแล้ว: ทัน/สาย/ส่งแก้/ครูเปิดให้แก้', () => {
    expect(workBadge(row({ submitted: true, timing: 'on_time', content_revision: 1 }))).toEqual({
      label: th.work.label.onTime,
      tone: 'purple',
    })
    expect(workBadge(row({ submitted: true, timing: 'late', content_revision: 1 }))).toEqual({
      label: th.work.label.late,
      tone: 'red',
    })
    expect(workBadge(row({ submitted: true, timing: 'on_time', content_revision: 2 })).label).toBe(
      th.work.label.revised,
    )
    expect(
      workBadge(
        row({ submitted: true, timing: 'late', content_revision: 1, permission_open: true }),
      ).label,
    ).toBe(th.work.label.permission)
  })
})

describe('เรียงและกรองงาน (UX 5)', () => {
  const a = row({ post_id: 'a', due_at: '2026-11-12T13:00:00Z' })
  const b = row({ post_id: 'b', due_at: '2026-11-11T13:00:00Z' })
  const done = row({
    post_id: 'c',
    due_at: '2026-11-20T13:00:00Z',
    submitted: true,
    timing: 'on_time',
  })
  const closed = row({
    post_id: 'd',
    due_at: '2026-11-01T13:00:00Z',
    outcome: null,
    blocked: 'submission_closed',
  })

  it('งานที่ยังต้องส่งขึ้นก่อนตามกำหนด แล้วงานอื่นจากกำหนดล่าสุด', () => {
    expect(sortWork([done, a, closed, b]).map((r) => r.post_id)).toEqual(['b', 'a', 'c', 'd'])
  })
  it('ตัวกรอง ยังไม่ส่ง/ส่งแล้ว', () => {
    expect(filterWork([a, done, closed], 'todo').map((r) => r.post_id)).toEqual(['a', 'd'])
    expect(filterWork([a, done, closed], 'done').map((r) => r.post_id)).toEqual(['c'])
    expect(filterWork([a, done, closed], 'all')).toHaveLength(3)
  })
  it('ใกล้กำหนดส่ง (S01) = เฉพาะงานที่ยังต้องส่ง ไม่เกิน limit', () => {
    expect(isPending(closed)).toBe(false)
    expect(dueSoon([done, a, closed, b], 1).map((r) => r.post_id)).toEqual(['b'])
  })
  it('ใกล้กำหนดส่งว่าง: ห้องยังไม่มีงาน ≠ ส่งครบแล้ว', () => {
    expect(dueEmpty([])).toBe('noWork')
    expect(dueEmpty([done])).toBe('allSent')
    expect(th.work.noWorkTitle).toBe('ยังไม่มีงานในชั้นเรียนนี้')
  })
  it('ป้ายเวลา: เลยกำหนด / เหลือไม่ถึง 24 ชม. / ไม่มี', () => {
    const due = '2026-11-10T13:00:00Z'
    expect(dueHint(due, Date.parse('2026-11-10T13:00:01Z'))).toBe('overdue')
    expect(dueHint(due, Date.parse('2026-11-10T00:00:00Z'))).toBe('soon')
    expect(dueHint(due, Date.parse('2026-11-08T00:00:00Z'))).toBeNull()
  })
})

describe('S03 งานของฉัน', () => {
  it('sameFiles เทียบทั้งชุดและลำดับ', () => {
    expect(sameFiles(['a', 'b'], ['a', 'b'])).toBe(true)
    expect(sameFiles(['b', 'a'], ['a', 'b'])).toBe(false)
    expect(sameFiles(['a'], ['a', 'b'])).toBe(false)
  })
  it('ป้ายหัว: ยังไม่ส่ง → แนบแล้วยังไม่ส่ง → ส่งแล้ว → กำลังแก้', () => {
    expect(mineBadge(status(), { editing: false, attached: false }).label).toBe(th.work.label.todo)
    expect(mineBadge(status(), { editing: false, attached: true }).label).toBe(
      th.work.label.attached,
    )
    const sent = status({ outcome: 'resubmit', submission: submitted() })
    expect(mineBadge(sent, { editing: false, attached: false }).label).toBe(th.work.label.onTime)
    expect(mineBadge(sent, { editing: true, attached: true }).label).toBe(th.work.label.editing)
    expect(
      mineBadge(status({ outcome: null, blocked: 'submission_closed' }), {
        editing: false,
        attached: false,
      }).label,
    ).toBe(th.work.label.closed)
  })
  it('แถบขั้นตอน: ส่งแล้วไปขั้นครูตรวจ', () => {
    expect(stepStates(status())).toEqual(['now', 'todo', 'todo', 'todo'])
    expect(stepStates(status({ submission: submitted() }))).toEqual(['done', 'now', 'todo', 'todo'])
  })
  it('เหตุผลแทนฟอร์มตามรหัส', () => {
    expect(blockedReason('term_ended')).toBe(th.work.lockedTermEnded)
    expect(blockedReason('resubmit_not_allowed')).toBe(th.work.lockedPastDue)
    expect(blockedReason('submission_closed')).toBe(th.errors.submission_closed)
    expect(blockedReason('อื่น')).toBe(th.errors.fallback)
  })
  it('วันเวลาไทยของเวลา UTC', () => {
    expect(when('2026-11-10T13:00:00Z')).toMatch(/10 พ\.ย\..* 20:00 น\.$/)
  })
})

const grade = (over: Partial<Grade> = {}): Grade => ({
  submission_id: '00000000-0000-4000-8000-0000000000s1',
  raw_score: 9,
  passed: true,
  penalty_override_pct: null,
  timing: 'on_time',
  applied_penalty_pct: 0,
  net_score: 9,
  graded_revision: 1,
  graded_at: '2026-11-11T05:00:00Z',
  version: 1,
  ...over,
})

describe('S03 คะแนนและความครบถ้วน', () => {
  it('ยังไม่เคยตรวจ → ไม่มีผลให้แสดง', () => {
    expect(gradeView(null, 1)).toBeNull()
  })
  it('คะแนนทัน: ก่อนหัก = สุทธิ ไม่มีการหัก', () => {
    expect(gradeView(grade({ raw_score: 7, net_score: 7 }), 1)).toEqual({
      stale: false,
      revision: 1,
      passed: true,
      score: { raw: 7, penaltyPct: 0, deduction: 0, net: 7 },
      override: null,
      late: false,
    })
  })
  it('งานสาย: ก่อนหัก 9, หัก 20% → สุทธิ 8 (หัก 1 ปัดขึ้นตามสูตรของเซิร์ฟเวอร์)', () => {
    const v = gradeView(
      grade({ timing: 'late', applied_penalty_pct: 20, raw_score: 9, net_score: 8 }),
      1,
    )
    expect(v?.score).toEqual({ raw: 9, penaltyPct: 20, deduction: 1, net: 8 })
    expect(v?.late).toBe(true)
  })
  it('ไม่ให้คะแนนแต่บันทึกความครบถ้วน → score เป็น null', () => {
    const v = gradeView(grade({ raw_score: null, net_score: null, passed: false }), 1)
    expect(v?.score).toBeNull()
    expect(v?.passed).toBe(false)
  })
  it('ส่งแก้หลังตรวจ → ผลเดิมเป็นของชุดก่อนหน้า (stale)', () => {
    expect(gradeView(grade({ graded_revision: 1 }), 2)?.stale).toBe(true)
    expect(gradeView(grade({ graded_revision: 2 }), 2)?.stale).toBe(false)
  })
  it('แถบขั้นตอนตามผลตรวจ: ครบถ้วน / รอยืนยัน / รอตรวจชุดใหม่', () => {
    const st = status({ outcome: 'resubmit', submission: submitted() })
    expect(stepStates(st, gradeView(grade(), 1))).toEqual(['done', 'done', 'done', 'todo'])
    expect(stepStates(st, gradeView(grade({ passed: false }), 1))).toEqual([
      'done',
      'done',
      'now',
      'todo',
    ])
    expect(stepStates(st, gradeView(grade(), 2))).toEqual(['done', 'now', 'todo', 'todo'])
    const got = status({ outcome: 'resubmit', submission: submitted(), reward_granted: true })
    expect(stepStates(got, gradeView(grade(), 1))).toEqual(['done', 'done', 'done', 'done'])
    // ส่งแก้หลังได้รางวัล: รอตรวจชุดใหม่ แต่โทเคนที่ได้แล้วไม่หาย
    expect(stepStates(got, gradeView(grade(), 2))).toEqual(['done', 'now', 'todo', 'done'])
  })
  it('ป้ายรางวัล UX 7: ได้รับแล้ว / งานภาคเรียนก่อน / ครบถ้วน', () => {
    const v = gradeView(grade(), 1)
    expect(gradeChip(v, status({ reward_granted: true })).label).toBe(
      'งานครบถ้วน · ได้รับ 2 โทเคนแล้ว',
    )
    expect(gradeChip(v, status({ current_term: false })).label).toBe(
      'บันทึกคะแนนแล้ว · งานภาคเรียนก่อน',
    )
    expect(gradeChip(v, status()).label).toBe(th.work.grade.complete)
    // งาน 0 โทเคนไม่บอก “ได้รับ 0”; ผ่าน→ไม่ผ่าน (I3) ไม่อ้างว่างานครบถ้วน
    expect(gradeChip(v, status({ reward_granted: true, reward_tokens: 0 })).label).toBe(
      th.work.grade.complete,
    )
    expect(
      gradeChip(gradeView(grade({ passed: false }), 1), status({ reward_granted: true })).label,
    ).toBe(th.work.grade.pending)
    expect(gradeChip(null, status()).label).toBe(th.work.grade.waiting)
  })
  it('ข้อความไม่ใช้คำว่า “ไม่ผ่าน”', () => {
    expect(JSON.stringify(th.work.grade)).not.toContain('ไม่ผ่าน')
    expect(th.work.grade.pending).toBe('รอครูยืนยันความครบถ้วน')
  })
})

describe('S03 ป้ายหัว “งานของฉัน” หลังครูตรวจ (UX 7)', () => {
  const ui = { editing: false, attached: false }
  const sent = (over: Partial<SubmissionStatus> = {}) =>
    status({ outcome: 'resubmit', submission: submitted(), ...over })
  const label = (s: SubmissionStatus, g: Grade | null) =>
    mineBadge(s, ui, gradeView(g, s.submission?.content_revision ?? 1)).label

  it('ผ่านและได้รางวัลแล้ว → งานครบถ้วน · ได้รับ … โทเคนแล้ว', () => {
    expect(label(sent({ reward_granted: true, reward_tokens: 2 }), grade())).toBe(
      th.work.grade.rewarded(2),
    )
  })
  it('ได้คะแนนแต่ยังไม่ผ่าน → คะแนน … · รอครูยืนยันความครบถ้วน', () => {
    expect(label(sent(), grade({ passed: false, net_score: 7, raw_score: 7 }))).toBe(
      'คะแนน 7 · รอครูยืนยันความครบถ้วน',
    )
    expect(label(sent(), grade({ passed: false, net_score: null, raw_score: null }))).toBe(
      th.work.grade.pending,
    )
  })
  it('ผ่าน (งาน 0 โทเคน/ส่งช้า) → งานครบถ้วน · เทอมเก่า → งานภาคเรียนก่อน', () => {
    expect(label(sent({ reward_tokens: 0 }), grade())).toBe(th.work.grade.complete)
    expect(label(sent({ current_term: false }), grade({ passed: false }))).toBe(
      th.work.grade.oldTerm,
    )
  })
  it('ยังไม่ตรวจ/ส่งแก้หลังตรวจ/ครูเปิดให้แก้ → ป้ายเดิม', () => {
    expect(label(sent(), null)).toBe(th.work.label.onTime)
    const resent = sent({ submission: submitted({ content_revision: 2 }) })
    expect(label(resent, grade())).toBe(th.work.label.revised)
    expect(label(sent({ permission_open: true }), grade())).toBe(th.work.label.permission)
  })
})
