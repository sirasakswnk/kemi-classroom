import { describe, expect, it } from 'vitest'
import { remaining } from './commentText'

describe('remaining', () => {
  it('ไม่นับช่องว่างหัวท้าย', () => {
    expect(remaining('  ครู  ')).toBe(1997)
  })

  it('นับแบบ code point (สระและวรรณยุกต์ไทยนับแยก แบบเดียวกับ length() ของ Postgres)', () => {
    expect(remaining('ที่')).toBe(1997)
  })

  it('เกินเพดานเป็นค่าติดลบ', () => {
    expect(remaining('ก'.repeat(2001))).toBe(-1)
  })
})
