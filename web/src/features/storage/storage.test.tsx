import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import { formatSize } from './api'
import { UploadBlocked } from './Storage'

describe('พื้นที่เก็บไฟล์', () => {
  it('ขนาดแบบที่ B2 คิด (1 GB = 10⁹ ไบต์)', () => {
    expect(formatSize(9_500_000_000)).toBe('9.50 GB')
    expect(formatSize(5_619_358)).toBe('5.6 MB')
    expect(formatSize(822_617)).toBe('823 KB')
    expect(formatSize(12)).toBe('12 ไบต์')
  })
  it('กล่องแจ้งเต็มของนักเรียน (J10.3) ไม่มีปุ่มชวนอัปเกรด', () => {
    const html = renderToString(<UploadBlocked />)
    expect(html).toContain(th.storage.blockedTitle)
    expect(html).toContain('ไม่ใช่ปัญหาจากเครื่องหรืออินเทอร์เน็ตของคุณ')
    expect(html).toContain('role="status"')
    expect(html).not.toMatch(/อัปเกรด|<button/)
  })
})
