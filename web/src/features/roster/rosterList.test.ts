import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import { filterRoster, type RosterRow } from './rosterApi'

const row = (name: string, group: string, bound: boolean, classrooms: string[]): RosterRow => ({
  student_id: name,
  display_name: name,
  student_code: '0',
  group_name: group,
  roll_number: 1,
  bound,
  account_email: bound ? 'a•••••@example.com' : null,
  classrooms,
})

describe('T05 รายชื่อ', () => {
  const rows = [
    row('ก', 'ม.5/1', true, ['เคมี ม.5/1']),
    row('ข', 'ม.5/1', false, []),
    row('ค', 'ม.5/2', true, []),
  ]

  it('กรองตามห้องตามรายชื่อและสถานะ', () => {
    expect(filterRoster(rows, '', 'all').map((r) => r.display_name)).toEqual(['ก', 'ข', 'ค'])
    expect(filterRoster(rows, '', 'unbound').map((r) => r.display_name)).toEqual(['ข'])
    expect(filterRoster(rows, '', 'notjoined').map((r) => r.display_name)).toEqual(['ข', 'ค'])
    expect(filterRoster(rows, 'ม.5/2', 'notjoined').map((r) => r.display_name)).toEqual(['ค'])
  })

  it('ข้อความแก้การผูกตาม UX 10', () => {
    expect(th.rosterList.move.warning).toBe(
      'บัญชีเดิมจะออกจากระบบและใช้สิทธิ์ของนักเรียนคนนี้ไม่ได้ทันที งาน คะแนน ชั้นเรียน และโทเคนยังอยู่กับนักเรียนเหมือนเดิม',
    )
    expect(th.rosterList.move.confirm).toBe('ยืนยันเปลี่ยนบัญชี')
    expect(th.rosterList.unbind.warning).toBe(
      'หลังถอด ใครที่ค้นชื่อนี้เจอก่อนจะเลือกได้ ถ้ารู้บัญชีที่ถูกต้องให้ใช้ “ผูกกับบัญชีอื่น” แทน',
    )
    expect(th.errors.account_not_found).toBe(
      'ไม่พบบัญชีนี้ ให้นักเรียนเข้าสู่ระบบด้วยบัญชีนี้ก่อนแล้วลองอีกครั้ง',
    )
    expect(th.errors.account_bound_elsewhere).toBe(
      'บัญชีนี้เชื่อมกับนักเรียนคนอื่นอยู่ ให้แก้การผูกของคนนั้นก่อน',
    )
  })
})
