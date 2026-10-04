import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import { toAppError } from '../../lib/supabase'
import { ClaimResultSchema, SearchResultSchema, canSearch, initialOf } from './identity'
import { NamePicker } from './NamePicker'

const REF = '7f1c2a4e-1b2c-4d5e-8f90-1234567890ab'

describe('ผลจาก RPC', () => {
  it('search_roster: รับเฉพาะ ref ชื่อปิดบางส่วน ห้อง เลขที่ (ช่องอื่นถูกตัดทิ้ง)', () => {
    const parsed = SearchResultSchema.parse({
      matches: [
        {
          ref: REF,
          masked_name: 'อนุ•• อิ•• นท••••',
          group_name: 'ม.5/2',
          roll_number: 6,
          student_code: '90044',
        },
      ],
      bound: false,
      remaining: 9,
    })
    expect(parsed.matches[0]).toEqual({
      ref: REF,
      masked_name: 'อนุ•• อิ•• นท••••',
      group_name: 'ม.5/2',
      roll_number: 6,
    })
  })

  it('claim_identity: claimed / name_taken / expired เท่านั้น', () => {
    expect(
      ClaimResultSchema.parse({
        status: 'claimed',
        display_name: 'อนุชา อิ นทร์แก้ว',
        group_name: 'ม.5/2',
        roll_number: 6,
      }).status,
    ).toBe('claimed')
    expect(ClaimResultSchema.parse({ status: 'name_taken' })).toEqual({ status: 'name_taken' })
    expect(ClaimResultSchema.parse({ status: 'expired' })).toEqual({ status: 'expired' })
    expect(ClaimResultSchema.safeParse({ status: 'other' }).success).toBe(false)
  })

  it('already_bound จาก RPC เป็นรหัสที่รู้จัก ไม่ใช่ข้อความสำรอง', () => {
    const e = toAppError({ code: 'P0001', message: 'already_bound' })
    expect(e.code).toBe('already_bound')
    expect(e.message).toBe('บัญชีนี้เลือกชื่อเรียบร้อยแล้ว')
  })
})

describe('ตัวช่วย', () => {
  it('ปุ่มค้นหากดได้เมื่อพิมพ์อย่างน้อย 2 ตัวอักษร ไม่นับช่องว่าง', () => {
    expect(canSearch('')).toBe(false)
    expect(canSearch('  ก  ')).toBe(false)
    expect(canSearch('9 0')).toBe(true)
    expect(canSearch('สมชาย ใจดี')).toBe(true)
  })

  it('ตัวอักษรแรกของชื่อปิดบางส่วน', () => {
    expect(initialOf('อนุ•• อิ••')).toBe('อ')
    expect(initialOf('')).toBe('')
  })
})

describe('ข้อความตาม UX_DESIGN ส่วน 4', () => {
  it('ข้อความผลค้นและผลยืนยัน', () => {
    expect(th.identity.notFound).toBe(
      'ไม่พบรายชื่อ ตรวจว่าพิมพ์เลขประจำตัวหรือชื่อ-นามสกุลครบและถูกต้อง หรือติดต่อคุณครู',
    )
    expect(th.identity.bound).toBe('รายชื่อนี้เชื่อมกับบัญชีแล้ว ให้คุณครูช่วยตรวจสอบ')
    expect(`${th.identity.searchLimitedTitle} ${th.identity.searchLimited}`).toBe(
      'ค้นหลายครั้งเกินไป รอสักครู่แล้วลองใหม่ หรือติดต่อคุณครู',
    )
    expect(th.identity.expired).toBe('หมดเวลายืนยันแล้ว กดค้นหาอีกครั้งเพื่อเลือกชื่อของคุณ')
    expect(th.identity.claimLimited).toBe(
      'ยืนยันหลายครั้งเกินไป รอสักครู่แล้วลองใหม่ หรือติดต่อคุณครู',
    )
    expect(th.identity.place('ม.5/1', 12)).toBe('ม.5/1 · เลขที่ 12')
  })
})

describe('A02 ขั้นค้นหา', () => {
  const html = renderToStaticMarkup(
    <NamePicker
      email="student@example.com"
      onSwitchAccount={() => {}}
      onClaimed={() => {}}
      onAlreadyBound={() => {}}
    />,
  )

  it('ลำดับใน DOM ตรงกับที่เห็น: ขั้น → หัวเรื่อง → บัญชี → ช่องค้น → คำแนะนำ', () => {
    const order = [
      th.identity.step(1),
      th.identity.searchTitle,
      th.identity.signedInAs('student@example.com'),
      th.identity.switchAccount,
      'id="pickQuery"',
      `>${th.identity.search}</button>`,
      th.identity.hint,
    ].map((s) => html.indexOf(s))
    expect(order.every((i) => i >= 0)).toBe(true)
    expect([...order].sort((a, b) => a - b)).toEqual(order)
  })

  it('ช่องค้นมีป้ายชื่อ และปุ่มค้นหายังกดไม่ได้จนกว่าจะพิมพ์', () => {
    expect(html).toContain(`<label class="sr-only" for="pickQuery">${th.identity.queryLabel}`)
    expect(html).toMatch(/<button(?=[^>]*type="submit")(?=[^>]*disabled="")/)
  })

  it('ไม่มีปุ่มปิด (แผ่นปิดไม่ได้จนเลือกชื่อเสร็จ)', () => {
    expect(html).not.toContain(th.dialog.close)
  })
})
