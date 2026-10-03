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

// เก็บไว้ใน sessionStorage ก่อนไป Google (ไม่ส่งผ่าน URL ของ OAuth)
export function rememberNextPath(path: string) {
  const safe = safeNextPath(path)
  try {
    if (safe) sessionStorage.setItem(STORAGE_KEY, safe)
    else sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // โหมดส่วนตัวบางเบราว์เซอร์ใช้ sessionStorage ไม่ได้: กลับหน้าแรกแทน
  }
}

// อ่านโดยไม่ลบ (เช่น A01 ดูว่ามาจากลิงก์เชิญหรือไม่)
export function peekNextPath(): string | null {
  try {
    return safeNextPath(sessionStorage.getItem(STORAGE_KEY))
  } catch {
    return null
  }
}

// อ่านแล้วลบทิ้ง ตรวจซ้ำอีกครั้งตอนอ่าน
export function takeNextPath(): string | null {
  try {
    const value = sessionStorage.getItem(STORAGE_KEY)
    sessionStorage.removeItem(STORAGE_KEY)
    return safeNextPath(value)
  } catch {
    return null
  }
}
