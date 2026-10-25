import { describe, expect, it } from 'vitest'
import { th } from '../copy/th'
import { ERROR_CODES, toAppError, type ErrorAction, type ErrorCode } from './supabase'

// ข้อผิดพลาดแบบที่ PostgREST ส่งกลับจาก RPC ที่ raise P0001
const rpcError = (message: string) => ({ code: 'P0001', message, details: null, hint: null })

// ทุกแถวของ UX_DESIGN 7.1: รหัส → ข้อความ → สิ่งที่หน้าเว็บทำ
const TABLE: Record<ErrorCode, { message: string; action: ErrorAction }> = {
  not_authenticated: { message: 'กรุณาเข้าสู่ระบบอีกครั้ง', action: 'relogin' },
  provider_not_allowed: { message: 'เข้าสู่ระบบได้ด้วยบัญชี Google เท่านั้น', action: 'sign_out' },
  account_conflict: {
    message: 'เชื่อมบัญชีนี้กับระบบไม่สำเร็จ กรุณาแจ้งคุณครู',
    action: 'switch_account',
  },
  account_required: { message: th.errors.fallback, action: 'ensure_and_retry' },
  forbidden: { message: 'คุณไม่มีสิทธิ์ทำรายการนี้', action: 'go_home_reload_role' },
  admin_mode_required: { message: 'ต้องเข้าหน้าครูในโหมดผู้ดูแลก่อน', action: 'enter_admin_mode' },
  rate_limited: { message: 'ทำรายการถี่เกินไป รอสักครู่แล้วลองใหม่', action: 'retry_later' },
  already_bound: { message: 'บัญชีนี้เลือกชื่อเรียบร้อยแล้ว', action: 'reload' },
  teacher_required: { message: 'เลือกครูเจ้าของชั้นเรียนก่อน', action: 'field' },
  name_invalid: { message: 'ใส่ชื่อชั้นเรียน ไม่เกิน 80 ตัวอักษร', action: 'focus_field' },
  not_member: {
    message: 'คุณไม่ได้อยู่ในชั้นเรียนนี้แล้ว ถ้าคิดว่าผิดพลาดให้แจ้งคุณครู',
    action: 'go_home_reload_role',
  },
  identity_required: { message: 'เลือกชื่อของคุณก่อน แล้วกลับมาเข้าชั้นเรียน', action: 'reload' },
  account_not_found: {
    message: 'ไม่พบบัญชีนี้ ให้นักเรียนเข้าสู่ระบบด้วยบัญชีนี้ก่อนแล้วลองอีกครั้ง',
    action: 'field',
  },
  account_bound_elsewhere: {
    message: 'บัญชีนี้เชื่อมกับนักเรียนคนอื่นอยู่ ให้แก้การผูกของคนนั้นก่อน',
    action: 'field',
  },
  account_not_student: {
    message: 'บัญชีนี้เป็นบัญชีครูหรือผู้ดูแล ผูกกับนักเรียนไม่ได้',
    action: 'field',
  },
  rebind_same_account: { message: 'บัญชีนี้ผูกกับนักเรียนคนนี้อยู่แล้ว', action: 'field' },
  account_ambiguous: { message: 'พบหลายบัญชีที่ใช้อีเมลนี้ แจ้งผู้ดูแลระบบ', action: 'field' },
  student_not_found: {
    message: 'ไม่พบนักเรียนคนนี้ โหลดรายชื่อใหม่แล้วลองอีกครั้ง',
    action: 'reload',
  },
  email_invalid: { message: 'ใส่อีเมลบัญชี Google ให้ถูกต้อง', action: 'focus_field' },
  teacher_email_exists: { message: 'อีเมลนี้อยู่ในรายการบัญชีครูแล้ว', action: 'field' },
  teacher_name_invalid: { message: 'ใส่ชื่อครู ไม่เกิน 60 ตัวอักษร', action: 'focus_field' },
  last_teacher: {
    message: 'ต้องมีบัญชีครูอย่างน้อย 1 บัญชี เพิ่มบัญชีใหม่ก่อนแล้วค่อยเอาบัญชีนี้ออก',
    action: 'field',
  },
  storage_full: {
    message:
      'ตอนนี้ยังอัปโหลดไฟล์ไม่ได้ · พื้นที่เก็บไฟล์ของระบบเต็มชั่วคราว ไม่ใช่ปัญหาจากเครื่องหรืออินเทอร์เน็ตของคุณ',
    action: 'storage_full_notice',
  },
  term_ended: { message: 'ภาคเรียนนี้ปิดแล้ว ทำรายการนี้ไม่ได้', action: 'reload' },
  full_score_locked: {
    message:
      'เปลี่ยนคะแนนเต็มและการหักคะแนนส่งช้าไม่ได้แล้ว เพราะบันทึกคะแนนไปแล้ว ปรับรายคนได้ที่หน้าตรวจงาน',
    action: 'field',
  },
  reward_locked: {
    message: 'เปลี่ยนจำนวนโทเคนไม่ได้แล้ว เพราะมีนักเรียนส่งงานนี้แล้ว',
    action: 'field',
  },
  after_solution_locked: {
    message: 'เปลี่ยนการรับงานหลังเฉลยไม่ได้แล้ว เพราะเผยแพร่เฉลยไปแล้ว',
    action: 'field',
  },
  post_title_invalid: { message: 'ใส่ชื่อ 1–120 ตัวอักษร', action: 'focus_field' },
  post_body_required: {
    message: 'ใส่ข้อความหรือแนบไฟล์อย่างน้อยหนึ่งอย่างก่อนโพสต์',
    action: 'field',
  },
  post_file_unavailable: {
    message: 'ไฟล์บางไฟล์ใช้ไม่ได้แล้ว นำไฟล์นั้นออกแล้วแนบใหม่',
    action: 'field',
  },
  post_body_too_long: { message: 'ข้อความยาวเกิน 10,000 ตัวอักษร ตัดให้สั้นลง', action: 'field' },
  full_score_invalid: {
    message: 'คะแนนเต็มต้องเป็นจำนวนเต็มตั้งแต่ 1 ถึง 1,000,000',
    action: 'field',
  },
  late_penalty_invalid: { message: 'ใส่ 0–100 (0 = ไม่หัก)', action: 'field' },
  reward_tokens_invalid: {
    message: 'จำนวนโทเคนไม่ถูกต้อง ใส่จำนวนเต็มไม่เกิน 1,000',
    action: 'field',
  },
  due_at_invalid: { message: 'วันเวลาไม่ถูกต้อง เลือกใหม่อีกครั้ง', action: 'field' },
  close_at_invalid: { message: 'วันเวลาไม่ถูกต้อง เลือกใหม่อีกครั้ง', action: 'field' },
  close_before_due: { message: 'วันปิดรับต้องไม่ก่อนกำหนดส่ง', action: 'field' },
  too_many_files: { message: 'แนบได้สูงสุด 10 ไฟล์', action: 'field' },
  file_too_large: {
    message: 'ไฟล์นี้ใหญ่เกินกำหนด · รูปหลังย่อไม่เกิน 2 MB · PDF ไม่เกิน 10 MB',
    action: 'field',
  },
  file_type_not_allowed: { message: 'รับเฉพาะไฟล์ JPG · PNG · HEIC · PDF', action: 'field' },
  batch_too_large: { message: 'ไฟล์รวมเกิน 20 MB นำบางไฟล์ออกก่อน', action: 'field' },
  upload_not_found: { message: 'ยังไม่พบไฟล์ที่อัปโหลด ลองอัปโหลดใหม่อีกครั้ง', action: 'field' },
  upload_in_progress: { message: 'ระบบกำลังบันทึกไฟล์นี้ รอสักครู่แล้วลองใหม่', action: 'field' },
  upload_expired: { message: 'การอัปโหลดนี้หมดเวลาแล้ว กรุณาเลือกไฟล์อีกครั้ง', action: 'field' },
  upload_size_mismatch: {
    message: 'ไฟล์ที่อัปโหลดไม่ครบหรือขนาดไม่ตรง กรุณาอัปโหลดใหม่',
    action: 'field',
  },
  upload_type_mismatch: {
    message: 'ไฟล์นี้ไม่ใช่รูป JPG/PNG หรือ PDF จริง กรุณาเลือกไฟล์อื่น',
    action: 'field',
  },
  upload_failed: { message: 'บันทึกไฟล์ไม่สำเร็จ กรุณาอัปโหลดไฟล์นี้ใหม่', action: 'field' },
  // S03 ส่งงาน (UX 7.1, P3-07/P3-08)
  submission_closed: {
    message: 'งานนี้ปิดรับแล้ว ส่งงานไม่ได้ ถ้าจำเป็นให้แจ้งคุณครู',
    action: 'reload',
  },
  resubmit_not_allowed: {
    message:
      'เลยกำหนดส่งหรือคุณครูตรวจแล้ว ส่งแก้ได้เมื่อคุณครูเปิดสิทธิ์แก้ไข งานชุดเดิมยังอยู่ครบ',
    action: 'reload',
  },
  submission_files_required: { message: 'แนบไฟล์อย่างน้อย 1 ไฟล์ก่อนส่งงาน', action: 'field' },
  submission_file_unavailable: {
    message: 'มีไฟล์ที่ใช้ส่งไม่ได้แล้ว โหลดหน้าใหม่แล้วแนบไฟล์อีกครั้ง งานชุดเดิมยังอยู่ครบ',
    action: 'field',
  },
  download_budget_reached: {
    message:
      'วันนี้เปิดไฟล์ครบโควตาของระบบแล้ว เปิดได้อีกครั้งเวลา 07:00 น. ไม่ใช่ปัญหาจากเครื่องของคุณ',
    action: 'retry_later',
  },
  reason_required: { message: 'กรุณาใส่เหตุผล', action: 'focus_field' },
  stale_revision: { message: 'ข้อมูลนี้ถูกแก้จากหน้าจออื่นแล้ว', action: 'reload_latest' },
  // T03 แผงผลตรวจ (UX 7.1 — score_invalid ใต้ช่องแสดงช่วงตามคะแนนเต็มของงาน)
  score_invalid: { message: 'ใส่คะแนนเป็นจำนวนเต็ม 0 ถึงคะแนนเต็ม', action: 'focus_field' },
  penalty_not_late: {
    message: 'งานนี้นับเป็นส่งทันกำหนดแล้ว จึงไม่มีการหักส่งช้าให้ปรับ',
    action: 'reload',
  },
  comment_too_long: { message: 'ข้อความยาวเกิน 2,000 ตัวอักษร ตัดให้สั้นลง', action: 'field' },
  preview_changed: {
    message:
      'มีนักเรียนส่งหรือครูตรวจงานเพิ่มระหว่างนี้ รายชื่อด้านล่างอัปเดตแล้ว ตรวจอีกครั้งแล้วกดยืนยัน',
    action: 'field',
  },
  close_required: { message: 'ปิดรับงานก่อนเผยแพร่เฉลย', action: 'field' },
  solution_published: {
    message: 'เผยแพร่เฉลยแล้ว เปิดรับเพิ่มได้ผ่านตัวเลือกรับงานหลังเฉลยเท่านั้น',
    action: 'reload',
  },
  // T05 ปรับโทเคน (UX 7.1, P5-03) — หน้าต่างต่อท้ายยอดล่าสุด
  insufficient_balance: { message: 'ยอดโทเคนไม่พอ', action: 'field' },
  // S04 สุ่ม (UX 7.1, P5-04)
  draw_completed: { message: 'สะสมครบแล้ว', action: 'field' },
  draw_unavailable: { message: 'ยังไม่มีรายการที่สุ่มได้ รอครูปรับอัตราสุ่ม', action: 'field' },
  // T06 (UX 7.1, P5-07)
  rates_must_total_100: { message: 'อัตรารวมของทุกระดับต้องเท่ากับ 100%', action: 'field' },
  // T07 (UX 7.1, P5-08)
  term_name_taken: { message: 'มีภาคเรียนชื่อนี้แล้ว ตั้งชื่ออื่น', action: 'focus_field' },
  // T07 ข้อมูลภาคเรียนเก่า (UX 7.1, P6-05)
  export_mismatch: {
    message: 'ข้อมูลเปลี่ยนระหว่างดาวน์โหลด ดาวน์โหลดใหม่อีกครั้งก่อนยืนยันลบ',
    action: 'field',
  },
  export_budget_reached: {
    message:
      'วันนี้ดาวน์โหลดครบโควตาของระบบแล้ว ดาวน์โหลดต่อได้หลัง 07:00 น. โดยต่อจากไฟล์ที่ค้างอยู่ ไม่ต้องเริ่มใหม่',
    action: 'retry_later',
  },
}

const FALLBACK = 'ทำรายการไม่สำเร็จ ลองใหม่อีกครั้ง ถ้ายังไม่ได้ให้แจ้งคุณครู'

describe('toAppError — UX_DESIGN 7.1', () => {
  it('ตารางในเทสต์ครบทุกรหัสที่หน้าเว็บรู้จัก', () => {
    expect(Object.keys(TABLE).sort()).toEqual([...ERROR_CODES].sort())
  })

  it.each(Object.entries(TABLE))('%s', (code, expected) => {
    const e = toAppError(rpcError(code))
    expect(e).toEqual({ code, message: expected.message, action: expected.action, ref: null })
    // ไม่แสดงรหัสภาษาอังกฤษเป็นข้อความหลัก
    expect(e.message).not.toContain(code)
  })

  it('รหัส P0001 ที่ไม่รู้จัก → ข้อความสำรองพร้อมรหัสอ้างอิง', () => {
    expect(toAppError(rpcError('brand_new_code'))).toEqual({
      code: 'unknown',
      message: FALLBACK,
      action: 'fallback',
      ref: 'P0001:brand_new_code',
    })
  })

  it('รหัสที่รู้จักแต่ไม่ได้มาจาก P0001 ไม่ถูกตีความเป็นรหัสของเรา', () => {
    expect(toAppError({ code: '42501', message: 'forbidden' })).toMatchObject({
      code: 'unknown',
      action: 'fallback',
      ref: '42501',
    })
  })

  it('สิทธิ์ฐานข้อมูล (42501) → ข้อความสำรอง', () => {
    expect(
      toAppError({ code: '42501', message: 'permission denied for function ensure_account' }),
    ).toEqual({ code: 'unknown', message: FALLBACK, action: 'fallback', ref: '42501' })
  })

  it('เครือข่ายขัดข้อง → ข้อความสำรอง ref network', () => {
    expect(toAppError(new TypeError('Failed to fetch'))).toMatchObject({
      message: FALLBACK,
      ref: 'network',
    })
  })

  it('ข้อผิดพลาดของ Supabase Auth ใช้ชื่อเป็นรหัสอ้างอิง', () => {
    expect(toAppError({ name: 'AuthApiError', message: 'invalid flow state' })).toMatchObject({
      message: FALLBACK,
      ref: 'AuthApiError',
    })
  })

  it.each([null, undefined, 'oops', 42])('ค่าแปลก (%s) → ข้อความสำรอง', (value) => {
    expect(toAppError(value)).toEqual({
      code: 'unknown',
      message: FALLBACK,
      action: 'fallback',
      ref: 'unknown',
    })
  })

  it('รหัสอ้างอิงตัดข้อความยาวไม่เกิน 40 ตัวอักษร', () => {
    expect(toAppError(rpcError('x'.repeat(200))).ref).toBe(`P0001:${'x'.repeat(40)}`)
  })
})
