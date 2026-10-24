import { describe, expect, it } from 'vitest'
import type { AdminCharm, Rarity } from './api'
import {
  canSaveDraft,
  centerSquare,
  draftOf,
  newDraft,
  previewSymbol,
  ratesState,
  toInput,
  weightOf,
} from './charmForm'

const rarities: Rarity[] = [
  { id: 1, name: 'ทั่วไป', weight: 60, count: 5 },
  { id: 2, name: 'หายาก', weight: 25, count: 4 },
  { id: 3, name: 'พิเศษ', weight: 10, count: 2 },
  { id: 4, name: 'ตำนาน', weight: 5, count: 1 },
]
const charm: AdminCharm = {
  id: '00000000-0000-4000-8000-0000000000c1',
  name: 'พญาเคมี',
  description: 'ทองคำ',
  symbol: 'Au',
  rarity_id: 4,
  position: 12,
  version: 3,
  image_asset_id: null,
  owners: 1,
}

describe('T06 อัตราตามระดับ', () => {
  it('อ่านค่าที่กรอก: ว่าง/ไม่ใช่ตัวเลข = 0', () => {
    expect(weightOf('')).toBe(0)
    expect(weightOf('abc')).toBe(0)
    expect(weightOf('25')).toBe(25)
  })
  it('ยังไม่แก้ → บันทึกไม่ได้; รวม 100 และแก้แล้ว → บันทึกได้', () => {
    const same = ratesState(rarities, { 1: '60', 2: '25', 3: '10', 4: '5' })
    expect(same).toMatchObject({ sum: 100, changed: false, canSave: false })
    const next = ratesState(rarities, { 1: '50', 2: '30', 3: '15', 4: '5' })
    expect(next).toMatchObject({ sum: 100, changed: true, canSave: true })
    expect(next.weights).toEqual([
      { rarity_id: 1, weight: 50 },
      { rarity_id: 2, weight: 30 },
      { rarity_id: 3, weight: 15 },
      { rarity_id: 4, weight: 5 },
    ])
  })
  it('รวมไม่เท่า 100 หรือเกิน 100 ต่อระดับ → บันทึกไม่ได้', () => {
    expect(ratesState(rarities, { 1: '60', 2: '25', 3: '10', 4: '4' })).toMatchObject({
      sum: 99,
      canSave: false,
    })
    expect(ratesState(rarities, { 1: '101', 2: '0', 3: '0', 4: '0' }).canSave).toBe(false)
  })
})

describe('T06 ฟอร์มเครื่องราง', () => {
  it('เพิ่มใหม่: รุ่น 0 ไม่มี id; ชื่อว่าง/ยาวเกินบันทึกไม่ได้', () => {
    const d = newDraft()
    expect(d).toMatchObject({ id: null, version: 0 })
    expect(canSaveDraft(d)).toBe(false)
    expect(canSaveDraft({ ...d, name: 'ก'.repeat(41) })).toBe(false)
    expect(canSaveDraft({ ...d, name: '  ดินสอ  ' })).toBe(true)
    expect(canSaveDraft({ ...d, name: 'ดินสอ', description: 'ก'.repeat(121) })).toBe(false)
  })
  it('ข้อมูลที่ส่ง: ตัดช่องว่าง; คงรูปเดิมไม่ส่ง image_asset_id; ใช้รูปวาด = null', () => {
    const d = { ...draftOf(charm), name: ' พญาเคมี ', description: ' ใหม่ ' }
    expect(toInput(d)).toEqual({
      id: charm.id,
      name: 'พญาเคมี',
      description: 'ใหม่',
      rarity_id: 4,
    })
    expect(toInput({ ...d, image: { kind: 'remove' } }).image_asset_id).toBeNull()
    expect(
      toInput({
        ...d,
        image: {
          kind: 'new',
          assetId: '00000000-0000-4000-8000-0000000000a1',
          previewUrl: 'blob:x',
        },
      }).image_asset_id,
    ).toBe('00000000-0000-4000-8000-0000000000a1')
    expect(toInput(newDraft())).not.toHaveProperty('id')
  })
  it('สัญลักษณ์ตัวอย่าง: ของเดิม หรือตัวแรกของชื่อ', () => {
    expect(previewSymbol(draftOf(charm), charm)).toBe('Au')
    expect(previewSymbol({ ...newDraft(), name: ' ดินสอ' }, undefined)).toBe('ด')
    expect(previewSymbol(newDraft(), undefined)).toBe('★')
  })
  it('ตัดรูปเป็นสี่เหลี่ยมจัตุรัสตรงกลาง', () => {
    expect(centerSquare(800, 600)).toEqual({ sx: 100, sy: 0, size: 600 })
    expect(centerSquare(300, 500)).toEqual({ sx: 0, sy: 100, size: 300 })
    expect(centerSquare(512, 512)).toEqual({ sx: 0, sy: 0, size: 512 })
  })
})
