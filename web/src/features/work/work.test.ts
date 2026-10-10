import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import type { SubmissionStatus, WorkRow } from './api'
import {
  blockedReason,
  dueHint,
  dueSoon,
  filterWork,
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
