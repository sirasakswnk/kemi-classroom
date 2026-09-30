import { describe, expect, it } from 'vitest'
import { safeNextPath } from './redirect'

describe('safeNextPath — กัน open redirect', () => {
  it.each([
    ['/', '/'],
    ['/t', '/t'],
    ['/t/c/123/w/9', '/t/c/123/w/9'],
    ['/join/ABC234?x=1#top', '/join/ABC234?x=1#top'],
    ['/me?tab=ตู้', '/me?tab=%E0%B8%95%E0%B8%B9%E0%B9%89'],
    // เข้ารหัสไว้: ยังเป็น path ภายในเว็บเรา
    ['/%2F%2Fevil.com', '/%2F%2Fevil.com'],
  ])('ผ่าน: %s', (input, expected) => {
    expect(safeNextPath(input)).toBe(expected)
  })

  it.each([
    ['//evil.com'],
    ['//evil.com/path'],
    ['/\\evil.com'],
    ['/\\/evil.com'],
    ['\\\\evil.com'],
    ['/\t/evil.com'],
    ['/\n/evil.com'],
    ['/a\\b'],
    ['https://evil.com'],
    ['http://localhost:5173/t'],
    ['javascript:alert(1)'],
    ['data:text/html,x'],
    ['evil.com'],
    [' /t'],
    [''],
    ['/login'],
    ['/login?next=/t'],
    ['/auth/callback?code=x'],
    ['/' + 'a'.repeat(3000)],
  ])('ไม่ผ่าน: %j', (input) => {
    expect(safeNextPath(input)).toBeNull()
  })

  it.each([null, undefined, 42, {}, ['/t']])('ไม่ใช่ข้อความ (%j) → null', (input) => {
    expect(safeNextPath(input)).toBeNull()
  })
})
