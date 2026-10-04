import { describe, expect, it } from 'vitest'
import { addDays, bangkokParts, bangkokToUtcIso, thaiDate, thaiTime } from '../../lib/thaiTime'
import {
  defaultPostForm,
  dueReminder,
  parseWholeNumber,
  POST_LIMITS,
  validatePostForm,
  type PostFormValues,
} from './postForm'
import { applyScript, toScript } from './script'

describe('ตัวห้อย/ตัวยก', () => {
  it('แปลงตัวเลขและเครื่องหมายเป็นอักขระ Unicode', () => {
    expect(toScript('2', 'sub')).toBe('₂')
    expect(toScript('3+', 'sup')).toBe('³⁺')
    expect(toScript('2−', 'sup')).toBe('²⁻')
    expect(toScript('0123456789+-', 'sub')).toBe('₀₁₂₃₄₅₆₇₈₉₊₋')
  })

  it('ตัวอักษรอื่นคงเดิม', () => {
    expect(toScript('aq', 'sub')).toBe('aq')
    expect(toScript('(g)', 'sub')).toBe('(g)')
  })

  it('แปลงเฉพาะช่วงที่เลือก: H2O → H₂O, Fe3+ → Fe³⁺ แล้วคืนช่วงใหม่', () => {
    expect(applyScript('H2O', 1, 2, 'sub')).toEqual({ value: 'H₂O', start: 1, end: 2 })
    expect(applyScript('Fe3+ ion', 2, 4, 'sup')).toEqual({ value: 'Fe³⁺ ion', start: 2, end: 4 })
  })

  it('ไม่ได้เลือกอะไร → null (บอกให้เลือกก่อน)', () => {
    expect(applyScript('H2O', 1, 1, 'sub')).toBeNull()
  })
})

describe('เวลาไทย ↔ UTC', () => {
  it('เวลาไทยแปลงเป็น UTC ลบ 7 ชั่วโมง เป็นนาทีเต็ม', () => {
    expect(bangkokToUtcIso('2026-11-10', '20:00')).toBe('2026-11-10T13:00:00.000Z')
    expect(bangkokToUtcIso('2026-11-10', '06:30')).toBe('2026-11-09T23:30:00.000Z')
    expect(bangkokToUtcIso('2026-12-31', '23:59')).toBe('2026-12-31T16:59:00.000Z')
  })

  it('รูปแบบผิดหรือวันที่ไม่มีจริง → null', () => {
    expect(bangkokToUtcIso('2026-04-31', '20:00')).toBeNull()
    expect(bangkokToUtcIso('2026-02-29', '20:00')).toBeNull()
    expect(bangkokToUtcIso('2026-11-10', '24:00')).toBeNull()
    expect(bangkokToUtcIso('', '20:00')).toBeNull()
    expect(bangkokToUtcIso('2026-11-10', '')).toBeNull()
    expect(bangkokToUtcIso('10/11/2026', '20:00')).toBeNull()
  })

  it('UTC แปลงกลับเป็นวันที่/เวลาไทย (ข้ามวันได้)', () => {
    expect(bangkokParts('2026-11-09T23:30:00Z')).toEqual({ date: '2026-11-10', time: '06:30' })
    expect(bangkokParts('2026-11-10T13:00:00Z')).toEqual({ date: '2026-11-10', time: '20:00' })
    expect(thaiTime('2026-11-10T13:00:00Z')).toBe('20:00')
  })

  it('ไปกลับได้ค่าเดิม', () => {
    for (const [d, t] of [
      ['2026-01-01', '00:00'],
      ['2026-06-15', '07:00'],
      ['2027-02-28', '16:59'],
    ]) {
      const iso = bangkokToUtcIso(d, t)
      expect(iso && bangkokParts(iso)).toEqual({ date: d, time: t })
    }
  })

  it('เลื่อนวันตามปฏิทิน ข้ามเดือน/ปีได้', () => {
    expect(addDays('2026-11-28', 7)).toBe('2026-12-05')
    expect(addDays('2026-12-30', 3)).toBe('2027-01-02')
  })

  it('วันที่แบบไทย: ปีเดียวกันไม่แสดงปี ข้ามปีแสดงปี พ.ศ.', () => {
    const now = new Date('2026-10-04T05:00:00Z')
    expect(thaiDate('2026-11-10T13:00:00Z', now)).toBe('10 พ.ย.')
    expect(thaiDate('2027-01-05T13:00:00Z', now)).toBe('5 ม.ค. 2570')
  })
})

describe('ตรวจฟอร์ม T02', () => {
  const now = new Date('2026-10-04T05:00:00Z') // 12:00 น. ไทย
  const homework = (patch: Partial<PostFormValues> = {}): PostFormValues => ({
    ...defaultPostForm('homework', now),
    title: 'การคำนวณ Kc',
    ...patch,
  })

  it('ค่าเริ่มต้น: เต็ม 10, หัก 50%, โทเคน 1, ส่งอีก 7 วัน 20:00 น., ไม่ตั้งวันปิดรับ', () => {
    const form = defaultPostForm('homework', now)
    expect(form).toMatchObject({
      fullScore: '10',
      latePct: '50',
      reward: 1,
      dueDate: '2026-10-11',
      dueTime: '20:00',
      hasClose: false,
      closeDate: '2026-10-18',
      acceptAfterSolution: false,
    })
  })

  it('การบ้านที่ถูกต้อง → ก้อน p_post (UTC, ตัดช่องว่าง, รายละเอียดว่างเป็น null)', () => {
    expect(validatePostForm(homework({ title: '  การคำนวณ Kc ', body: '  ' }))).toEqual({
      errors: {},
      payload: {
        kind: 'homework',
        title: 'การคำนวณ Kc',
        body: null,
        full_score: 10,
        late_penalty_pct: 50,
        reward_tokens: 1,
        due_at: '2026-10-11T13:00:00.000Z',
        close_at: null,
        accept_after_solution: false,
      },
    })
  })

  it('ประกาศส่งแค่ชนิด ชื่อ และข้อความ', () => {
    const form = {
      ...defaultPostForm('announcement', now),
      title: 'นัดสอบ',
      body: 'วันศุกร์\nคาบ 3 ',
    }
    expect(validatePostForm(form)).toEqual({
      errors: {},
      payload: { kind: 'announcement', title: 'นัดสอบ', body: 'วันศุกร์\nคาบ 3' },
    })
  })

  it('ชื่อว่าง/ยาวเกิน และประกาศไม่มีข้อความ', () => {
    expect(validatePostForm(homework({ title: '   ' })).errors.title).toBe('title_required')
    expect(
      validatePostForm(homework({ title: 'ก'.repeat(POST_LIMITS.titleMax + 1) })).errors.title,
    ).toBe('title_too_long')
    expect(
      validatePostForm(homework({ title: 'ก'.repeat(POST_LIMITS.titleMax) })).errors.title,
    ).toBeUndefined()
    const announcement = { ...defaultPostForm('announcement', now), title: 'ประกาศ', body: ' ' }
    expect(validatePostForm(announcement).errors.body).toBe('body_required')
    expect(
      validatePostForm(homework({ body: 'ข'.repeat(POST_LIMITS.bodyMax + 1) })).errors.body,
    ).toBe('body_too_long')
  })

  it('นับความยาวเป็นตัวอักษร (ตัวห้อย/อีโมจิไม่นับเกิน) ให้ตรงกับฐานข้อมูล', () => {
    expect(
      validatePostForm(homework({ title: '🧪'.repeat(POST_LIMITS.titleMax) })).errors.title,
    ).toBeUndefined()
  })

  it('K1 คะแนนเต็ม: จำนวนเต็มตั้งแต่ 1 ไม่มีเพดาน 100 (เกินเพดานกันค่าผิดพลาดไม่ได้)', () => {
    expect(validatePostForm(homework({ fullScore: '150' })).errors.fullScore).toBeUndefined()
    expect(validatePostForm(homework({ fullScore: '๒๐' })).payload).toMatchObject({
      full_score: 20,
    })
    for (const bad of ['0', '', '9.5', '-3', '10 คะแนน', String(POST_LIMITS.fullScoreMax + 1)]) {
      expect(validatePostForm(homework({ fullScore: bad })).errors.fullScore).toBe(
        'full_score_invalid',
      )
    }
  })

  it('J1 % หักส่งช้า 0–100', () => {
    expect(validatePostForm(homework({ latePct: '0' })).payload).toMatchObject({
      late_penalty_pct: 0,
    })
    expect(validatePostForm(homework({ latePct: '101' })).errors.latePct).toBe(
      'late_penalty_invalid',
    )
    expect(validatePostForm(homework({ latePct: '' })).errors.latePct).toBe('late_penalty_invalid')
  })

  it('โทเคน 0–1,000', () => {
    expect(validatePostForm(homework({ reward: 0 })).payload).toMatchObject({ reward_tokens: 0 })
    expect(validatePostForm(homework({ reward: 1001 })).errors.reward).toBe('reward_invalid')
  })

  it('กำหนดส่งต้องมีวันและเวลา; วันปิดรับต้องไม่ก่อนกำหนดส่ง', () => {
    expect(validatePostForm(homework({ dueDate: '' })).errors.due).toBe('due_invalid')
    expect(validatePostForm(homework({ dueTime: '' })).errors.due).toBe('due_invalid')
    const before = homework({ hasClose: true, closeDate: '2026-10-11', closeTime: '19:59' })
    expect(validatePostForm(before).errors.close).toBe('close_before_due')
    const same = homework({ hasClose: true, closeDate: '2026-10-11', closeTime: '20:00' })
    expect(validatePostForm(same).payload).toMatchObject({ close_at: '2026-10-11T13:00:00.000Z' })
    expect(validatePostForm(homework({ hasClose: true, closeDate: '' })).errors.close).toBe(
      'close_invalid',
    )
    // ปิดสวิตช์แล้วไม่ส่งวันปิดรับ แม้ช่องวันที่ยังมีค่าเดิม
    expect(
      validatePostForm(homework({ hasClose: false, closeDate: '2020-01-01' })).payload,
    ).toMatchObject({
      close_at: null,
    })
  })

  it('กำหนดส่งที่ผ่านไปแล้วส่งได้ (เตือนสีเหลืองในตัวอย่าง)', () => {
    expect(validatePostForm(homework({ dueDate: '2026-10-01' })).errors.due).toBeUndefined()
  })

  it('เลขจำนวนเต็มจากช่องกรอก', () => {
    expect(parseWholeNumber(' 12 ')).toBe(12)
    expect(parseWholeNumber('๑๕')).toBe(15)
    expect(parseWholeNumber('1e3')).toBeNull()
    expect(parseWholeNumber('99999999999999999999')).toBeNull()
  })
})

describe('ข้อความเตือนในตัวอย่างฝั่งนักเรียน (J7)', () => {
  const now = new Date('2026-10-04T05:00:00Z')
  it('ผ่านไปแล้ว / ไม่ถึง 24 ชม. / ปกติ', () => {
    expect(dueReminder('2026-10-04T05:00:00Z', now)).toBe('past')
    expect(dueReminder('2026-10-03T05:00:00Z', now)).toBe('past')
    expect(dueReminder('2026-10-05T04:59:00Z', now)).toBe('soon')
    expect(dueReminder('2026-10-05T05:00:00Z', now)).toBe('normal')
    expect(dueReminder(null, now)).toBeNull()
  })
})
