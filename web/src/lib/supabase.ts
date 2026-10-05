import { createClient } from '@supabase/supabase-js'
import { th } from '../copy/th'
import type { Database } from './database.types'

// ---------------------------------------------------------------------------
// Supabase client — ใช้ publishable key เท่านั้น (ห้าม service role ในเว็บ: CLAUDE.md ส่วน 5)
// PKCE: Google ส่งกลับมาที่ /auth/callback?code=… แล้วหน้า callback แลก code เป็น session เอง
// (detectSessionInUrl: false เพื่อไม่ให้ client แลกซ้ำตอนเริ่มทำงาน)
// ---------------------------------------------------------------------------
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
if (!url || !key) {
  throw new Error('ไม่พบ VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY — ดู web/.env.example')
}

export const supabase = createClient<Database>(url, key, {
  auth: {
    flowType: 'pkce',
    detectSessionInUrl: false,
    persistSession: true,
    autoRefreshToken: true,
  },
})

// ---------------------------------------------------------------------------
// แปลงรหัสข้อผิดพลาดจากเซิร์ฟเวอร์เป็นข้อความไทย — UX_DESIGN 7.1
// RPC แจ้งข้อผิดพลาดตามกติกาด้วย ERRCODE P0001 และ MESSAGE = รหัส (TECHNICAL_BUILD_PLAN 4.1 ข้อ 7)
// ---------------------------------------------------------------------------
export const ERROR_CODES = [
  'not_authenticated',
  'provider_not_allowed',
  'account_conflict',
  'account_required',
  'forbidden',
  'admin_mode_required',
  'rate_limited',
  'storage_full',
  'term_ended',
  'full_score_locked',
  'reward_locked',
  'after_solution_locked',
  'reason_required',
  'stale_revision',
  'already_bound',
  'teacher_required',
  'name_invalid',
  'not_member',
  'identity_required',
  'account_not_found',
  'account_bound_elsewhere',
  'account_not_student',
  'rebind_same_account',
  'account_ambiguous',
  'student_not_found',
  'email_invalid',
  'teacher_email_exists',
  'teacher_name_invalid',
  'last_teacher',
  'post_title_invalid',
  'post_body_required',
  'post_body_too_long',
  'full_score_invalid',
  'late_penalty_invalid',
  'reward_tokens_invalid',
  'due_at_invalid',
  'close_at_invalid',
  'close_before_due',
  'download_budget_reached',
] as const

export type ErrorCode = (typeof ERROR_CODES)[number]

/** สิ่งที่หน้าเว็บต้องทำต่อ (คอลัมน์ขวาของ UX 7.1) */
export type ErrorAction =
  | 'relogin' // พากลับ A01 แล้วกลับหน้าเดิมหลังล็อกอิน (ไม่แสดงเป็นข้อผิดพลาด)
  | 'sign_out' // ออกจากระบบให้
  | 'switch_account' // แสดงอีเมลที่ล็อกอินอยู่ + ลิงก์ “เปลี่ยนบัญชี”
  | 'ensure_and_retry' // เรียก ensure_account() แล้วลองคำสั่งเดิมอีก 1 ครั้ง (ไม่แสดง)
  | 'go_home_reload_role' // ปุ่มกลับหน้าแรก + โหลดบทบาทใหม่
  | 'enter_admin_mode' // ปุ่มเข้าโหมดผู้ดูแล
  | 'retry_later'
  | 'storage_full_notice' // กล่องข้อความ J10.3
  | 'reload' // โหลดหน้าใหม่ให้ตรงสถานะ
  | 'field' // แสดงใต้ช่องที่เกี่ยวข้อง
  | 'focus_field' // แสดงใต้ช่องแล้วย้ายโฟกัสไปที่ช่อง
  | 'reload_latest' // ปุ่ม “โหลดข้อมูลล่าสุด” โดยเก็บสิ่งที่พิมพ์ไว้
  | 'fallback' // ข้อความสำรอง + รหัสอ้างอิงตัวเล็ก

export interface AppError {
  code: ErrorCode | 'unknown'
  /** ข้อความไทยที่แสดง (สำหรับ relogin คือข้อความบน A01; ensure_and_retry คือข้อความสำรองถ้าลองซ้ำแล้วยังไม่ได้) */
  message: string
  action: ErrorAction
  /** รหัสอ้างอิงตัวเล็ก เฉพาะข้อความสำรอง */
  ref: string | null
}

const ACTIONS: Record<ErrorCode, ErrorAction> = {
  not_authenticated: 'relogin',
  provider_not_allowed: 'sign_out',
  account_conflict: 'switch_account',
  account_required: 'ensure_and_retry',
  forbidden: 'go_home_reload_role',
  admin_mode_required: 'enter_admin_mode',
  rate_limited: 'retry_later',
  storage_full: 'storage_full_notice',
  term_ended: 'reload',
  // T02 โหมดแก้ไข (P3-02b): ช่องล็อกระหว่างเปิดฟอร์ม — ข้อความใต้ช่อง แล้วเปลี่ยนช่องเป็นค่าล่าสุดสีจาง (UX 9)
  full_score_locked: 'field',
  reward_locked: 'field',
  after_solution_locked: 'field',
  reason_required: 'focus_field',
  stale_revision: 'reload_latest',
  // A02: ไม่แสดงเป็นข้อผิดพลาด ปิดป๊อปอัปแล้วโหลดข้อมูลใหม่ (UX 4)
  already_bound: 'reload',
  teacher_required: 'field',
  name_invalid: 'focus_field',
  // UX 7.1: แสดงข้อความแล้วพากลับหน้าแรก
  not_member: 'go_home_reload_role',
  // UX 7.1: เปิด A02 ให้เลือกชื่อก่อน (โหลดข้อมูลนักเรียนใหม่)
  identity_required: 'reload',
  // T05 แก้การผูก (P2-08): แสดงใต้ช่องอีเมล
  account_not_found: 'field',
  account_bound_elsewhere: 'field',
  account_not_student: 'field',
  rebind_same_account: 'field',
  account_ambiguous: 'field',
  student_not_found: 'reload',
  // D01 บัญชีครู (P2-09)
  email_invalid: 'focus_field',
  teacher_email_exists: 'field',
  teacher_name_invalid: 'focus_field',
  last_teacher: 'field',
  // T02 สร้าง/แก้โพสต์ (P3-02/P3-02b): ด่านหลังของการตรวจฝั่งหน้าเว็บ — แสดงใต้ช่องที่เกี่ยวข้อง
  post_title_invalid: 'focus_field',
  post_body_required: 'field',
  post_body_too_long: 'field',
  full_score_invalid: 'field',
  late_penalty_invalid: 'field',
  reward_tokens_invalid: 'field',
  due_at_invalid: 'field',
  close_at_invalid: 'field',
  close_before_due: 'field',
  // ตัวดูไฟล์ (P3-05; ตัวดูมากับ P3-08/P3-09): ครบงบเปิดดูของวัน/B2 เกินเพดาน — เปิดได้อีกครั้ง 07:00 น.
  download_budget_reached: 'retry_later',
}

const isErrorCode = (value: unknown): value is ErrorCode =>
  typeof value === 'string' && (ERROR_CODES as readonly string[]).includes(value)

const field = (error: unknown, name: string): unknown =>
  typeof error === 'object' && error !== null ? (error as Record<string, unknown>)[name] : undefined

// รหัสอ้างอิงสั้น ๆ สำหรับแจ้งครู/ผู้ดูแล — ไม่ใส่ข้อความยาวหรือข้อมูลส่วนตัว
function referenceOf(error: unknown): string {
  const code = field(error, 'code')
  if (typeof code === 'string' && code) {
    const message = field(error, 'message')
    return code === 'P0001' && typeof message === 'string' ? `P0001:${message.slice(0, 40)}` : code
  }
  if (error instanceof TypeError) return 'network'
  const name = field(error, 'name')
  return typeof name === 'string' && name ? name : 'unknown'
}

export function toAppError(error: unknown): AppError {
  const message = field(error, 'message')
  if (field(error, 'code') === 'P0001' && isErrorCode(message)) {
    const code = message
    const text = code === 'account_required' ? th.errors.fallback : th.errors[code]
    return { code, message: text, action: ACTIONS[code], ref: null }
  }
  return {
    code: 'unknown',
    message: th.errors.fallback,
    action: 'fallback',
    ref: referenceOf(error),
  }
}
