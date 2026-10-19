import { parseWholeNumber } from '../posts/postForm'
import { netScore } from './score'

// แผงผลตรวจ T03 (UX 9, แบบ v2 g-panel) — คิดผลก่อนบันทึกและตัดสินว่าปุ่มบันทึกใช้ได้หรือไม่
// กติกาตรงกับ grade_submission (0025/0026): ผ่าน/ไม่ผ่านส่งทุกครั้ง (ไม่ติ๊ก = รอยืนยันความครบถ้วน) คะแนนเว้นว่างได้
// ปรับ % รายคนได้เฉพาะงานที่นับเป็นสาย; ค่าที่ค้างจากตอนเคยสายส่งกลับไปเท่าเดิมเมื่องานนับเป็นทัน (L2 ฉบับ 17 ต.ค.)

export const REASON_MAX = 2000

export interface GradeContext {
  fullScore: number
  /** % หักของงาน */
  latePct: number
  /** ทัน/สายตามกำหนดปัจจุบัน (คิดจากเวลาส่งครั้งแรก) */
  timing: 'on_time' | 'late'
  /** % หักเฉพาะคนที่บันทึกไว้แล้ว (null = ใช้ของงาน) */
  storedOverride: number | null
}

export interface GradeDraft {
  raw: string
  pass: boolean
  /** เปิดกล่อง "ปรับการหักเฉพาะคนนี้" อยู่ (มีผลเฉพาะงานสาย) */
  overrideOpen: boolean
  overrideText: string
  reason: string
}

export type DraftProblem = 'raw' | 'override' | 'reason' | 'reason_too_long' | 'empty'

export interface GradeEvaluation {
  /** คะแนนดิบที่อ่านได้ (null = เว้นว่าง) */
  raw: number | null
  /** % หักที่ใช้คำนวณ (0 เมื่อทัน) */
  pct: number
  /** ใช้ % เฉพาะคน (ไม่ใช่ของงาน) */
  override: boolean
  net: number | null
  /** ค่าที่ส่งไป p_override_pct */
  overridePct: number | null
  /** ค่า override เปลี่ยนจากที่บันทึกไว้ → ต้องมีเหตุผล */
  reasonNeeded: boolean
  problems: DraftProblem[]
}

const charLength = (text: string) => [...text].length

/** ค่าเริ่มของแผงจากผลตรวจที่บันทึกแล้ว */
export function initialDraft(
  grade: { raw_score: number | null; passed: boolean; penalty_override_pct: number | null } | null,
  timing: GradeContext['timing'],
): GradeDraft {
  const stored = grade?.penalty_override_pct ?? null
  return {
    raw: grade?.raw_score != null ? String(grade.raw_score) : '',
    pass: grade?.passed ?? false,
    overrideOpen: timing === 'late' && stored != null,
    overrideText: stored != null ? String(stored) : '',
    reason: '',
  }
}

export function evaluateDraft(ctx: GradeContext, draft: GradeDraft): GradeEvaluation {
  const problems: DraftProblem[] = []
  const rawText = draft.raw.trim()
  let raw: number | null = null
  if (rawText) {
    raw = parseWholeNumber(rawText)
    if (raw == null || raw > ctx.fullScore) {
      problems.push('raw')
      raw = null
    }
  }

  let overridePct: number | null
  if (ctx.timing === 'late') {
    if (draft.overrideOpen && draft.overrideText.trim()) {
      overridePct = parseWholeNumber(draft.overrideText)
      if (overridePct == null || overridePct > 100) {
        problems.push('override')
        overridePct = ctx.storedOverride
      }
    } else {
      overridePct = null
    }
  } else {
    // ทัน: ไม่แสดงการปรับ และส่งค่าที่ค้างไว้กลับไปเท่าเดิม (ไม่ล้างเองโดยไม่มีเหตุผล)
    overridePct = ctx.storedOverride
  }

  const reasonNeeded = overridePct !== ctx.storedOverride
  const reasonLength = charLength(draft.reason.trim())
  if (reasonNeeded && reasonLength === 0) problems.push('reason')
  if (reasonNeeded && reasonLength > REASON_MAX) problems.push('reason_too_long')
  // UX 9: บันทึกได้เมื่อมีคะแนนหรือยืนยันงานครบถ้วนอย่างน้อยหนึ่งอย่าง (ไม่บังคับทั้งคู่)
  if (raw == null && !rawText && !draft.pass) problems.push('empty')

  const override = ctx.timing === 'late' && overridePct != null
  const pct = ctx.timing === 'late' ? (overridePct ?? ctx.latePct) : 0
  return {
    raw,
    pct,
    override,
    net: raw == null ? null : netScore(raw, pct),
    overridePct,
    reasonNeeded,
    problems,
  }
}

/** ตัวเลขทศนิยมไม่เกิน 2 ตำแหน่ง (ตัดศูนย์ท้าย) สำหรับแสดงสูตร */
export function decimal(value: number): string {
  return String(Math.round(value * 100) / 100)
}

/** แถวสูตรของงานสาย (UX 9): "7 × 50% = 3.5" แล้ว "ปัดขึ้น → 4" — null เมื่อยังไม่มีคะแนนหรือไม่หัก */
export function formulaParts(
  raw: number | null,
  pct: number,
): { expression: string; net: number; rounded: boolean } | null {
  if (raw == null || pct === 0) return null
  const exact = (raw * (100 - pct)) / 100
  return {
    expression: `${raw} × ${100 - pct}% = ${decimal(exact)}`,
    net: netScore(raw, pct),
    rounded: !Number.isInteger(exact),
  }
}
