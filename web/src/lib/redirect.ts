// จำหน้าที่จะกลับไปหลังล็อกอิน — รับเฉพาะ path ภายในเว็บเรา กัน open redirect
// ผ่าน: "/t/c/1", "/?tab=work#x"   ไม่ผ่าน: "//evil.com", "/\evil.com", "https://evil.com", "javascript:…"
const PROBE_ORIGIN = 'https://kemi.invalid'
const MAX_LENGTH = 2048
// อักขระควบคุมและ backslash: เบราว์เซอร์ตีความ "/\host" หรือ "/\t/host" เป็น "//host"
// eslint-disable-next-line no-control-regex
const UNSAFE_CHARS = /[\u0000-\u001f\u007f\\]/

export function safeNextPath(value: unknown): string | null {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_LENGTH) return null
  if (!value.startsWith('/') || value.startsWith('//')) return null
  if (UNSAFE_CHARS.test(value)) return null

  let url: URL
  try {
    url = new URL(value, PROBE_ORIGIN)
  } catch {
    return null
  }
  if (url.origin !== PROBE_ORIGIN) return null
  // ไม่พากลับหน้าเข้าสู่ระบบ/callback (วนซ้ำ)
  if (url.pathname === '/login' || url.pathname.startsWith('/auth/')) return null
  return url.pathname + url.search + url.hash
}

const STORAGE_KEY = 'kemi:next'
// หน้าที่ผู้ใช้กดออกจากระบบเอง — ไม่จำหน้านี้เป็นหน้าหลังล็อกอิน (คนถัดไปบนเครื่องเดียวกันไม่ถูกพาไปหน้าของคนก่อน)
const SIGNED_OUT_KEY = 'kemi:signed-out-from'

/** ที่เก็บแบบ sessionStorage — ส่งตัวจำลองเข้ามาได้ในเทสต์ */
export type PathStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

const sessionStore = (): PathStore | null => {
  try {
    return sessionStorage
  } catch {
    // โหมดส่วนตัวบางเบราว์เซอร์ใช้ sessionStorage ไม่ได้: กลับหน้าแรกของบทบาทแทน
    return null
  }
}

/**
 * ตอนหลุดจากระบบที่หน้า here: ควรจำ path ไหนไว้กลับหลังล็อกอิน (pure)
 * ออกจากระบบเองที่หน้านี้ → ไม่จำ; เซสชันหลุด/เปิดลิงก์ตอนยังไม่ล็อกอิน → จำ (เฉพาะ path ภายในเว็บ)
 */
export function pathToRemember(here: string, signedOutFrom: string | null): string | null {
  if (signedOutFrom !== null && signedOutFrom === here) return null
  return safeNextPath(here)
}

/** ผู้ใช้กดออกจากระบบเองที่หน้า here — ล้างหน้าที่จำไว้ และกันไม่ให้จำหน้านี้ */
export function markManualSignOut(here: string, store: PathStore | null = sessionStore()) {
  try {
    store?.removeItem(STORAGE_KEY)
    store?.setItem(SIGNED_OUT_KEY, here)
  } catch {
    // ใช้ที่เก็บไม่ได้: ไม่มีอะไรถูกจำอยู่แล้ว
  }
}

// เก็บไว้ใน sessionStorage ก่อนไป Google (ไม่ส่งผ่าน URL ของ OAuth) — เรียกจาก RequireRole เมื่อไม่มีเซสชัน
// เครื่องหมาย “ออกจากระบบเอง” ใช้ครั้งเดียว: หน้าที่เปิดหลังจากนั้น (เช่นลิงก์เชิญ) จำตามปกติ
export function rememberNextPath(path: string, store: PathStore | null = sessionStore()) {
  try {
    if (!store) return
    const remember = pathToRemember(path, store.getItem(SIGNED_OUT_KEY))
    store.removeItem(SIGNED_OUT_KEY)
    if (remember) store.setItem(STORAGE_KEY, remember)
    else store.removeItem(STORAGE_KEY)
  } catch {
    // ใช้ที่เก็บไม่ได้: กลับหน้าแรกของบทบาทแทน
  }
}

// อ่านโดยไม่ลบ (เช่น A01 ดูว่ามาจากลิงก์เชิญหรือไม่)
export function peekNextPath(store: PathStore | null = sessionStore()): string | null {
  try {
    return safeNextPath(store?.getItem(STORAGE_KEY))
  } catch {
    return null
  }
}

// อ่านแล้วลบทิ้ง ตรวจซ้ำอีกครั้งตอนอ่าน — null = ไปหน้าแรกแล้ว RequireRole พาไปหน้าของบทบาท
export function takeNextPath(store: PathStore | null = sessionStore()): string | null {
  try {
    const value = store?.getItem(STORAGE_KEY)
    store?.removeItem(STORAGE_KEY)
    store?.removeItem(SIGNED_OUT_KEY)
    return safeNextPath(value)
  } catch {
    return null
  }
}
