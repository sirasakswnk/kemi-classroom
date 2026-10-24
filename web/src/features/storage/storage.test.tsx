import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import { formatSize, type StorageReconcile, type StorageStatus } from './api'
import { adminStorageAlerts } from './adminAlerts'
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

describe('D01 แถบเตือนบนสุด (P6-04b)', () => {
  const copy = th.storage.adminAlert
  const NOW = new Date('2026-10-25T08:00:00Z')
  const status = (level: StorageStatus['level'], percent: number): StorageStatus => ({
    level,
    percent,
    admin_warn_pct: 80,
    teacher_warn_pct: 90,
  })
  const reconcile = (diff: number, exceeds: boolean): StorageReconcile => ({
    finished_at: '2026-10-24T21:31:00Z',
    b2_bytes: 300_000_000 + diff,
    db_bytes: 300_000_000,
    diff_bytes: diff,
    offset_bytes: Math.max(diff, 0),
    exceeds_threshold: exceeds,
  })

  it('ยังไม่ถึงเกณฑ์ผู้ดูแลและยอดไม่ต่างเกินเกณฑ์ → ไม่มีแถบ', () => {
    expect(adminStorageAlerts(status('ok', 79.9), reconcile(1_000, false), NOW)).toEqual([])
    expect(adminStorageAlerts(undefined, null, NOW)).toEqual([])
  })

  it('80% (เกณฑ์ผู้ดูแล) → เหลือง บอกว่าครูยังไม่เห็น · 90% → ครูได้แจ้งแล้ว · เต็ม → แดง', () => {
    expect(adminStorageAlerts(status('admin_warn', 82.5), null, NOW)).toEqual([
      { key: 'storage', tone: 'amber', title: copy.used('82.5'), body: copy.adminWarnBody(80, 90) },
    ])
    expect(adminStorageAlerts(status('teacher_warn', 91), null, NOW)[0]).toMatchObject({
      tone: 'amber',
      body: copy.teacherWarnBody,
    })
    expect(adminStorageAlerts(status('full', 100), null, NOW)[0]).toMatchObject({
      tone: 'red',
      title: copy.full,
    })
  })

  it('ธงยอด B2 ต่างเกินเกณฑ์ → แถบบอกขนาดต่าง ทิศทาง และเวลาเทียบ (ไม่ลบไฟล์)', () => {
    const [more] = adminStorageAlerts(status('ok', 10), reconcile(250_000_000, true), NOW)
    expect(more).toEqual({
      key: 'reconcile',
      tone: 'amber',
      title: copy.diff('250.0 MB'),
      body: copy.diffMore('25 ต.ค. 04:31 น.'),
    })
    const [less] = adminStorageAlerts(status('ok', 10), reconcile(-20_000_000, true), NOW)
    expect(less.title).toBe(copy.diff('20.0 MB'))
    expect(less.body).toBe(copy.diffLess('25 ต.ค. 04:31 น.'))
    expect(
      adminStorageAlerts(status('full', 100), reconcile(5, true), NOW).map((a) => a.key),
    ).toEqual(['storage', 'reconcile'])
  })
})
