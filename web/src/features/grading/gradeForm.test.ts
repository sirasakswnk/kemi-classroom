import { describe, expect, it } from 'vitest'
import {
  evaluateDraft,
  formulaParts,
  initialDraft,
  type GradeContext,
  type GradeDraft,
} from './gradeForm'

const late: GradeContext = { fullScore: 10, latePct: 50, timing: 'late', storedOverride: null }
const onTime: GradeContext = { ...late, timing: 'on_time' }
const draft = (d: Partial<GradeDraft> = {}): GradeDraft => ({
  raw: '',
  pass: false,
  overrideOpen: false,
  overrideText: '',
  reason: '',
  ...d,
})

describe('evaluateDraft', () => {
  it('งานสายหักตาม % ของงาน', () => {
    expect(evaluateDraft(late, draft({ raw: '7' }))).toMatchObject({
      raw: 7,
      pct: 50,
      net: 4,
      override: false,
    })
  })

  it('งานทันไม่หัก', () => {
    expect(evaluateDraft(onTime, draft({ raw: '7' }))).toMatchObject({ pct: 0, net: 7 })
  })

  it('รับเลขไทย', () => {
    expect(evaluateDraft(onTime, draft({ raw: '๙' })).raw).toBe(9)
  })

  it('คะแนนเกินเต็ม ติดลบ หรือทศนิยม → raw ผิด', () => {
    for (const raw of ['11', '-1', '7.5', 'ก'])
      expect(evaluateDraft(late, draft({ raw })).problems).toContain('raw')
  })

  it('เว้นคะแนนและไม่ติ๊กยืนยัน → บันทึกไม่ได้; ติ๊กอย่างเดียวพอ', () => {
    expect(evaluateDraft(late, draft()).problems).toEqual(['empty'])
    expect(evaluateDraft(late, draft({ pass: true })).problems).toEqual([])
  })

  it('ปรับเฉพาะคนต้องมีเหตุผล และใช้ % นั้นคำนวณ', () => {
    const open = draft({ raw: '7', overrideOpen: true, overrideText: '20' })
    expect(evaluateDraft(late, open)).toMatchObject({
      pct: 20,
      net: 6,
      override: true,
      reasonNeeded: true,
    })
    expect(evaluateDraft(late, open).problems).toEqual(['reason'])
    expect(evaluateDraft(late, { ...open, reason: '  ป่วย ' }).problems).toEqual([])
  })

  it('% เฉพาะคนผิดช่วง', () => {
    expect(
      evaluateDraft(late, draft({ overrideOpen: true, overrideText: '101', pass: true })).problems,
    ).toContain('override')
  })

  it('เหตุผลยาวเกิน 2,000 ตัว', () => {
    const d = draft({ pass: true, overrideOpen: true, overrideText: '0', reason: 'ก'.repeat(2001) })
    expect(evaluateDraft(late, d).problems).toEqual(['reason_too_long'])
  })

  it('ค่าที่บันทึกไว้แล้วส่งกลับเท่าเดิมไม่ต้องมีเหตุผล; ล้างต้องมีเหตุผล', () => {
    const stored = { ...late, storedOverride: 20 }
    const keep = initialDraft({ raw_score: 7, passed: true, penalty_override_pct: 20 }, 'late')
    expect(keep.overrideOpen).toBe(true)
    expect(evaluateDraft(stored, keep)).toMatchObject({
      overridePct: 20,
      reasonNeeded: false,
      net: 6,
    })
    const cleared = { ...keep, overrideOpen: false }
    expect(evaluateDraft(stored, cleared)).toMatchObject({
      overridePct: null,
      reasonNeeded: true,
      net: 4,
    })
  })

  it('งานกลายเป็นทัน: ซ่อนการปรับ ส่งค่าค้างกลับเท่าเดิม ไม่หัก', () => {
    const ctx = { ...onTime, storedOverride: 20 }
    const d = initialDraft({ raw_score: 7, passed: false, penalty_override_pct: 20 }, 'on_time')
    expect(d.overrideOpen).toBe(false)
    expect(evaluateDraft(ctx, d)).toMatchObject({
      overridePct: 20,
      reasonNeeded: false,
      pct: 0,
      net: 7,
      problems: [],
    })
  })
})

describe('formulaParts', () => {
  it('ตัวอย่างใน UX 9', () => {
    expect(formulaParts(7, 50)).toEqual({ expression: '7 × 50% = 3.5', net: 4, rounded: true })
    expect(formulaParts(7, 30)).toEqual({ expression: '7 × 70% = 4.9', net: 5, rounded: true })
    expect(formulaParts(8, 50)).toEqual({ expression: '8 × 50% = 4', net: 4, rounded: false })
  })

  it('ยังไม่มีคะแนนหรือไม่หัก → ไม่แสดงสูตร', () => {
    expect(formulaParts(null, 50)).toBeNull()
    expect(formulaParts(7, 0)).toBeNull()
  })
})
