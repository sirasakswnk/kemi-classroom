import { addDays, bangkokParts, bangkokToUtcIso } from '../../lib/thaiTime'

// ฟอร์ม T02 (UX_DESIGN ส่วน 9): ค่าเริ่มต้น ตรวจก่อนส่ง และแปลงเป็นก้อน p_post ของ RPC create_post
// เพดานต้องตรงกับฐานข้อมูล (0010_posts check + 0014_post_rpcs) — ตรวจฝั่งหน้าเว็บก่อนส่ง แล้วเซิร์ฟเวอร์ตรวจซ้ำ
export const POST_LIMITS = {
  titleMax: 120,
  bodyMax: 10_000,
  fullScoreMin: 1,
  fullScoreMax: 1_000_000,
  latePctMin: 0,
  latePctMax: 100,
  rewardMin: 0,
  rewardMax: 1000,
} as const

export type PostKind = 'homework' | 'announcement'

export interface PostFormValues {
  kind: PostKind
  title: string
  body: string
  /** ข้อความในช่อง (รับเลขไทยได้) — แปลงตอนตรวจ */
  fullScore: string
  latePct: string
  reward: number
  /** วันที่/เวลาไทยจาก <input type="date|time"> */
  dueDate: string
  dueTime: string
  hasClose: boolean
  closeDate: string
  closeTime: string
  acceptAfterSolution: boolean
}

export type PostField = 'title' | 'body' | 'fullScore' | 'latePct' | 'reward' | 'due' | 'close'

export type PostFormError =
  | 'title_required'
  | 'title_too_long'
  | 'body_required'
  | 'body_too_long'
  | 'full_score_invalid'
  | 'late_penalty_invalid'
  | 'reward_invalid'
  | 'due_invalid'
  | 'close_invalid'
  | 'close_before_due'

/** ก้อน p_post ของ create_post (การบ้านมีช่องคะแนน เวลา และรางวัล ประกาศไม่มี) */
export type PostPayload =
  | { kind: 'announcement'; title: string; body: string }
  | {
      kind: 'homework'
      title: string
      body: string | null
      full_score: number
      late_penalty_pct: number
      reward_tokens: number
      due_at: string
      close_at: string | null
      accept_after_solution: boolean
    }

// ลำดับช่องบนหน้าจอ — โฟกัสช่องแรกที่ผิด
export const FIELD_ORDER: readonly PostField[] = [
  'title',
  'body',
  'fullScore',
  'latePct',
  'due',
  'close',
  'reward',
]

const DEFAULT_TIME = '20:00'

/** ค่าเริ่มต้น: คะแนนเต็ม 10, หัก 50% (J1), โทเคน 1, กำหนดส่งอีก 7 วัน 20:00 น., วันปิดรับ (ถ้าเปิด) อีก 7 วันหลังกำหนดส่ง */
export function defaultPostForm(kind: PostKind, now: Date = new Date()): PostFormValues {
  const dueDate = addDays(bangkokParts(now).date, 7)
  return {
    kind,
    title: '',
    body: '',
    fullScore: '10',
    latePct: '50',
    reward: 1,
    dueDate,
    dueTime: DEFAULT_TIME,
    hasClose: false,
    closeDate: addDays(dueDate, 7),
    closeTime: DEFAULT_TIME,
    acceptAfterSolution: false,
  }
}

const THAI_DIGITS = /[๐-๙]/g

/** จำนวนเต็มไม่ติดลบจากช่องกรอก (รับเลขไทย) — มีทศนิยม เครื่องหมาย หรือตัวอื่นคืน null */
export function parseWholeNumber(text: string): number | null {
  const digits = text.trim().replace(THAI_DIGITS, (d) => String(d.charCodeAt(0) - 0x0e50))
  if (!/^\d+$/.test(digits)) return null
  const value = Number(digits)
  return Number.isSafeInteger(value) ? value : null
}

/** ความยาวแบบนับตัวอักษร (code point) ให้ตรงกับ length() ของ Postgres */
const charLength = (text: string) => [...text].length

export function validatePostForm(values: PostFormValues): {
  errors: Partial<Record<PostField, PostFormError>>
  payload: PostPayload | null
} {
  const errors: Partial<Record<PostField, PostFormError>> = {}
  const title = values.title.trim()
  const body = values.body.trim()
  if (!title) errors.title = 'title_required'
  else if (charLength(title) > POST_LIMITS.titleMax) errors.title = 'title_too_long'
  if (charLength(body) > POST_LIMITS.bodyMax) errors.body = 'body_too_long'
  else if (values.kind === 'announcement' && !body) errors.body = 'body_required'

  if (values.kind === 'announcement') {
    return Object.keys(errors).length
      ? { errors, payload: null }
      : { errors, payload: { kind: 'announcement', title, body } }
  }

  const fullScore = parseWholeNumber(values.fullScore)
  if (
    fullScore === null ||
    fullScore < POST_LIMITS.fullScoreMin ||
    fullScore > POST_LIMITS.fullScoreMax
  ) {
    errors.fullScore = 'full_score_invalid'
  }
  const latePct = parseWholeNumber(values.latePct)
  if (latePct === null || latePct < POST_LIMITS.latePctMin || latePct > POST_LIMITS.latePctMax) {
    errors.latePct = 'late_penalty_invalid'
  }
  if (
    !Number.isInteger(values.reward) ||
    values.reward < POST_LIMITS.rewardMin ||
    values.reward > POST_LIMITS.rewardMax
  ) {
    errors.reward = 'reward_invalid'
  }
  const dueAt = bangkokToUtcIso(values.dueDate, values.dueTime)
  if (!dueAt) errors.due = 'due_invalid'
  let closeAt: string | null = null
  if (values.hasClose) {
    closeAt = bangkokToUtcIso(values.closeDate, values.closeTime)
    if (!closeAt) errors.close = 'close_invalid'
    else if (dueAt && closeAt < dueAt) errors.close = 'close_before_due'
  }

  if (Object.keys(errors).length || fullScore === null || latePct === null || !dueAt) {
    return { errors, payload: null }
  }
  return {
    errors,
    payload: {
      kind: 'homework',
      title,
      body: body || null,
      full_score: fullScore,
      late_penalty_pct: latePct,
      reward_tokens: values.reward,
      due_at: dueAt,
      close_at: closeAt,
      accept_after_solution: values.acceptAfterSolution,
    },
  }
}

/** ข้อความแจ้งเตือนในตัวอย่างฝั่งนักเรียน (J7): กำหนดส่งผ่านไปแล้ว / เหลือไม่ถึง 24 ชม. / ปกติ */
export function dueReminder(
  dueIso: string | null,
  now: Date = new Date(),
): 'past' | 'soon' | 'normal' | null {
  if (!dueIso) return null
  const hours = (new Date(dueIso).getTime() - now.getTime()) / 3_600_000
  if (hours <= 0) return 'past'
  if (hours < 24) return 'soon'
  return 'normal'
}
