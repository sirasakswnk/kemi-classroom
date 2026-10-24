import { describe, expect, it } from 'vitest'
import {
  markManualSignOut,
  pathToRemember,
  peekNextPath,
  rememberNextPath,
  safeNextPath,
  takeNextPath,
  type PathStore,
} from './redirect'

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

// sessionStorage จำลอง (Vitest รันแบบ node ไม่มี DOM)
const memoryStore = (): PathStore & { size: () => number } => {
  const map = new Map<string, string>()
  return {
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => void map.set(k, v),
    removeItem: (k) => void map.delete(k),
    size: () => map.size,
  }
}

// หลังล็อกอิน AuthCallback ไป takeNextPath() ?? '/' แล้ว RequireRole พาไปหน้าแรกของบทบาท
const afterLogin = (store: PathStore) => takeNextPath(store) ?? '/'

describe('หน้าหลังล็อกอิน (UX 7.1 not_authenticated: กลับหน้าเดิม)', () => {
  it('ออกจากระบบเองที่หน้าครู → ล็อกอินใหม่ไปหน้าแรกของบทบาท ไม่ใช่หน้าเดิม', () => {
    const store = memoryStore()
    rememberNextPath('/t/c/1', store) // เคยจำหน้าไว้ก่อนหน้า
    markManualSignOut('/t/w/9', store)
    rememberNextPath('/t/w/9', store) // RequireRole เห็นว่าไม่มีเซสชันที่หน้าเดิม
    expect(peekNextPath(store)).toBeNull()
    expect(afterLogin(store)).toBe('/')
    expect(store.size()).toBe(0)
  })

  it('เซสชันหลุดเอง → กลับหน้าเดิมหลังล็อกอิน', () => {
    const store = memoryStore()
    rememberNextPath('/w/abc?x=1#c', store)
    expect(afterLogin(store)).toBe('/w/abc?x=1#c')
    expect(afterLogin(store)).toBe('/') // ใช้ครั้งเดียว
  })

  it('เปิด /join/:code ตอนยังไม่ล็อกอิน → กลับไปหน้านั้น (รวมกรณีเพิ่งกดออกจากระบบที่หน้าอื่น)', () => {
    const fresh = memoryStore()
    rememberNextPath('/join/ABC234', fresh)
    expect(peekNextPath(fresh)).toBe('/join/ABC234') // A01 รู้ว่ามาจากลิงก์เชิญ
    expect(afterLogin(fresh)).toBe('/join/ABC234')

    const afterSignOut = memoryStore()
    markManualSignOut('/me', afterSignOut)
    rememberNextPath('/me', afterSignOut)
    rememberNextPath('/join/ABC234', afterSignOut) // เครื่องหมายใช้ครั้งเดียว
    expect(afterLogin(afterSignOut)).toBe('/join/ABC234')
  })

  it('path ภายนอกถูกปฏิเสธ — ไม่จำ และค่าที่ถูกแก้ในที่เก็บก็ไม่ผ่านตอนอ่าน', () => {
    const store = memoryStore()
    rememberNextPath('//evil.com/x', store)
    expect(afterLogin(store)).toBe('/')
    store.setItem('kemi:next', 'https://evil.com')
    expect(afterLogin(store)).toBe('/')
    expect(pathToRemember('https://evil.com', null)).toBeNull()
  })

  it('ตัดสินแบบ pure: ไม่จำเฉพาะหน้าที่กดออกจากระบบเอง', () => {
    expect(pathToRemember('/t/w/9', '/t/w/9')).toBeNull()
    expect(pathToRemember('/t/w/9', null)).toBe('/t/w/9')
    expect(pathToRemember('/join/A', '/t/w/9')).toBe('/join/A')
  })

  it('ใช้ที่เก็บไม่ได้ (โหมดส่วนตัว) → ไปหน้าแรกของบทบาท ไม่ล้ม', () => {
    rememberNextPath('/w/abc', null)
    markManualSignOut('/w/abc', null)
    expect(takeNextPath(null)).toBeNull()
  })
})
