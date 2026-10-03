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
  storage_full: {
    message:
      'ตอนนี้ยังอัปโหลดไฟล์ไม่ได้ · พื้นที่เก็บไฟล์ของระบบเต็มชั่วคราว ไม่ใช่ปัญหาจากเครื่องหรืออินเทอร์เน็ตของคุณ',
    action: 'storage_full_notice',
  },
  term_ended: { message: 'ภาคเรียนนี้ปิดแล้ว ทำรายการนี้ไม่ได้', action: 'reload' },
  score_locked: {
    message:
      'เปลี่ยนคะแนนเต็มและการหักคะแนนส่งช้าไม่ได้แล้ว เพราะบันทึกคะแนนไปแล้ว ปรับรายคนได้ที่หน้าตรวจงาน',
    action: 'field',
  },
  reason_required: { message: 'กรุณาใส่เหตุผล', action: 'focus_field' },
  stale_revision: { message: 'ข้อมูลนี้ถูกแก้จากหน้าจออื่นแล้ว', action: 'reload_latest' },
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
