import { afterEach, describe, expect, it, vi } from 'vitest'
import { th } from '../../copy/th'
import { peekNextPath, rememberNextPath, takeNextPath } from '../../lib/redirect'
import { toAppError } from '../../lib/supabase'
import { normalizeCode } from './api'
import { firstName } from './names'

describe('เข้าชั้นเรียนด้วยรหัส', () => {
  it('รหัสที่พิมพ์ตัวเล็ก เว้นวรรค และขีด แปลงเป็นรูปเดียวกับเซิร์ฟเวอร์', () => {
    expect(normalizeCode(' k7m-2qx ')).toBe('K7M2QX')
    expect(normalizeCode('k7m 2qx')).toBe('K7M2QX')
    expect(normalizeCode('K7M 2QX')).toBe('K7M2QX')
  })

  it('ข้อความตาม UX 4 และ 9', () => {
    expect(th.student.join.notFound).toBe(
      'ไม่พบชั้นเรียนจากรหัสนี้ ตรวจตัวอักษรอีกครั้ง หรือถามคุณครู',
    )
    expect(th.student.join.already).toBe('คุณอยู่ในชั้นเรียนนี้แล้ว')
    expect(th.student.join.closed).toBe(
      'ชั้นเรียนนี้ปิดรับสมาชิกใหม่อยู่ ให้คุณครูเปิดการเข้าห้องก่อน',
    )
    expect(th.student.join.limited).toBe(
      'ใส่รหัสผิดหลายครั้งเกินไป รอสักครู่แล้วลองใหม่ หรือถามคุณครู',
    )
    expect(`${th.login.invitePrefix}${th.login.inviteStrong}${th.login.inviteSuffix}`).toBe(
      'คุณได้รับลิงก์เชิญเข้าชั้นเรียน เข้าสู่ระบบก่อน แล้วระบบจะแสดงชื่อห้องให้ตรวจก่อนเข้าร่วม',
    )
  })

  it('not_member แสดงข้อความตาม UX 7.1 แล้วพากลับหน้าแรก', () => {
    expect(toAppError({ code: 'P0001', message: 'not_member' })).toMatchObject({
      message: 'คุณไม่ได้อยู่ในชั้นเรียนนี้แล้ว ถ้าคิดว่าผิดพลาดให้แจ้งคุณครู',
      action: 'go_home_reload_role',
    })
  })

  it('ชื่อสำหรับคำทักทาย', () => {
    expect(firstName('อนุชา อิ นทร์แก้ว')).toBe('อนุชา')
    expect(firstName('  ชนิดา ชัยมงคล ')).toBe('ชนิดา')
  })
})

describe('ลิงก์เชิญก่อนล็อกอิน', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('จำ /join/:code ไว้ (ตัวกรอง path เดิม) A01 อ่านได้โดยไม่ลบ แล้ว callback อ่านแล้วลบ', () => {
    const store = new Map<string, string>()
    vi.stubGlobal('sessionStorage', {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => store.set(k, v),
      removeItem: (k: string) => store.delete(k),
    })
    rememberNextPath('/join/K7M2QX')
    expect(peekNextPath()).toBe('/join/K7M2QX')
    expect(peekNextPath()).toBe('/join/K7M2QX')
    expect(takeNextPath()).toBe('/join/K7M2QX')
    expect(peekNextPath()).toBeNull()
    rememberNextPath('//evil.com/join/X')
    expect(peekNextPath()).toBeNull()
  })
})
