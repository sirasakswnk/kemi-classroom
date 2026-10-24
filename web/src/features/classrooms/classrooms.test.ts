import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import { toAppError } from '../../lib/supabase'
import { initialOf as initialOfTeacher } from '../../lib/initial'
import { compareMembers, inviteLink, type Member } from './api'
import { classTone } from './tone'

const m = (name: string, group: string | null, roll: number | null): Member => ({
  student_id: name,
  joined_at: '',
  display_name: name,
  group_name: group,
  roll_number: roll,
  charm: null,
})

describe('ชั้นเรียน', () => {
  it('สมาชิกเรียงตามห้องในรายชื่อ (ตัวเลขแบบธรรมชาติ) เลขที่ แล้วชื่อ — คนไม่อยู่ในรายชื่อไว้ท้าย', () => {
    const sorted = [
      m('ค', null, null),
      m('ข', 'ม.5/10', 1),
      m('ง', 'ม.5/2', 12),
      m('ก', 'ม.5/2', 3),
      m('จ', 'ม.5/2', 3),
    ].sort(compareMembers)
    expect(sorted.map((x) => x.display_name)).toEqual(['ก', 'จ', 'ง', 'ข', 'ค'])
  })

  it('ลิงก์เชิญใช้รหัสเดียวกับที่พิมพ์', () => {
    expect(inviteLink('K7M2QX', 'https://kemi-classroom.pages.dev')).toBe(
      'https://kemi-classroom.pages.dev/join/K7M2QX',
    )
  })

  it('สีแถบชั้นเรียนวน 5 ชุด', () => {
    expect([0, 1, 4, 5, 6].map(classTone)).toEqual([0, 1, 4, 0, 1])
  })

  it('ตัวอักษรรูปแทนตัวครูข้ามคำว่า “ครู”', () => {
    expect(initialOfTeacher('ครูอิงฟ้า')).toBe('อ')
    expect(initialOfTeacher('ครู สมศรี')).toBe('ส')
    expect(initialOfTeacher('ผู้ดูแลระบบ')).toBe('ผ')
    expect(initialOfTeacher('ครูเคมี (dev)')).toBe('ค')
    expect(initialOfTeacher('ไพลิน')).toBe('พ')
    expect(initialOfTeacher('')).toBe('')
  })

  it('รหัสข้อผิดพลาดของ T09 ตาม UX 7.1', () => {
    expect(toAppError({ code: 'P0001', message: 'name_invalid' })).toMatchObject({
      message: 'ใส่ชื่อชั้นเรียน ไม่เกิน 80 ตัวอักษร',
      action: 'focus_field',
    })
    expect(toAppError({ code: 'P0001', message: 'teacher_required' })).toMatchObject({
      message: 'เลือกครูเจ้าของชั้นเรียนก่อน',
      action: 'field',
    })
    expect(toAppError({ code: 'P0001', message: 'join_code_exhausted' }).action).toBe('fallback')
  })

  it('ข้อความเอาออกและปิดการเข้าห้องตาม UX 9', () => {
    expect(th.classrooms.room.removeTitle('สมชาย ใจดี', 'เคมี ม.5/1')).toBe(
      'เอา สมชาย ใจดี ออกจาก เคมี ม.5/1?',
    )
    expect(th.classrooms.room.removeBody).toBe(
      'งาน คะแนน และโทเคนที่ได้แล้วไม่ถูกลบ ถ้านักเรียนใส่รหัสห้องนี้อีกครั้งจะเห็นงานเดิม',
    )
    expect(th.classrooms.room.closedBadge).toBe('ปิดการเข้าห้องอยู่')
    expect(th.classrooms.room.codeAria('K7M2QX')).toBe('แสดงรหัสชั้นเรียน K 7 M 2 Q X เต็มจอ')
  })
})
