import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import {
  drawButton,
  drawErrorText,
  fmtPct,
  reloadsOptions,
  tierOf,
  weightsText,
} from './rewardState'

const copy = th.rewards

describe('S04 สุ่มเครื่องราง', () => {
  it('เปอร์เซ็นต์: ทศนิยม 1 ตำแหน่ง ตัด .0', () => {
    expect(fmtPct(60)).toBe('60%')
    expect(fmtPct(33.33)).toBe('33.3%')
    expect(fmtPct(0)).toBe('0%')
    expect(fmtPct(6.67)).toBe('6.7%')
  })
  it('ปุ่มสุ่มตามสถานะจากเซิร์ฟเวอร์', () => {
    expect(drawButton({ status: 'ok' }, false)).toEqual({
      label: copy.draw,
      disabled: false,
      why: null,
    })
    expect(drawButton({ status: 'insufficient' }, false)).toMatchObject({
      disabled: true,
      why: copy.whyInsufficient,
    })
    expect(drawButton({ status: 'completed' }, false)).toMatchObject({
      label: copy.completed,
      disabled: true,
    })
    expect(drawButton({ status: 'unavailable' }, false)).toMatchObject({
      label: copy.unavailableBtn,
      disabled: true,
      why: copy.whyUnavailable,
    })
  })
  it('กำลังสุ่ม: กดซ้ำไม่ได้', () => {
    expect(drawButton({ status: 'ok' }, true)).toEqual({
      label: copy.drawing,
      disabled: true,
      why: null,
    })
  })
  it('สัดส่วนที่ครูตั้งและสีระดับ', () => {
    const level = { name: '', total: 1, owned: 0, remaining: 1, pct: 0, pct_each: 0 }
    expect(
      weightsText({
        levels: [
          { ...level, rarity_id: 1, weight: 60 },
          { ...level, rarity_id: 2, weight: 25 },
        ],
      }),
    ).toBe('60 / 25')
    expect([1, 2, 3, 4, 9].map(tierOf)).toEqual([0, 1, 2, 3, 3])
  })
  it('ข้อความผิดพลาด: stale_revision ของ S04 และยอดล่าสุด', () => {
    expect(drawErrorText('stale_revision', 'x', null)).toBe(copy.staleRates)
    expect(drawErrorText('insufficient_balance', 'ยอดโทเคนไม่พอ', 0)).toBe(
      'ยอดโทเคนไม่พอ ยอดล่าสุด 0 โทเคน',
    )
    expect(drawErrorText('insufficient_balance', 'ยอดโทเคนไม่พอ', null)).toBe('ยอดโทเคนไม่พอ')
    expect(drawErrorText(null, 'เน็ตหลุด', null)).toBe('เน็ตหลุด')
  })
  it('รหัสที่ต้องโหลดตัวเลือกใหม่ — เน็ตหลุดไม่โหลด (กดลองใหม่ด้วย key เดิม)', () => {
    expect(
      ['stale_revision', 'insufficient_balance', 'draw_completed', 'draw_unavailable'].every(
        reloadsOptions,
      ),
    ).toBe(true)
    expect(reloadsOptions(null)).toBe(false)
    expect(reloadsOptions('rate_limited')).toBe(false)
  })
})
