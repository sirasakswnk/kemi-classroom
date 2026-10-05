// คำตอบ HTTP ร่วมของ Edge Functions — CORS เฉพาะเว็บของเรา และ error รูปแบบเดียวกับ RPC
// ({ code: 'P0001', message: <รหัส> } ให้ toAppError() ของหน้าเว็บอ่านได้ทันที)

/** origin ที่เรียกได้ถ้าไม่ตั้ง WEB_ORIGINS (dev: production + preview ของ Pages + vite dev) */
export const DEFAULT_WEB_ORIGINS = [
  'https://kemi-classroom.pages.dev',
  'https://*.kemi-classroom.pages.dev',
  'http://localhost:5173',
]

/** WEB_ORIGINS คั่นด้วยจุลภาค — prod ตั้งเป็น production อย่างเดียว (ระยะ 7) */
export function webOrigins(value: string | undefined): string[] {
  const list = (value ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
  return list.length > 0 ? list : DEFAULT_WEB_ORIGINS
}

/** ตรงตัว หรือมี * แทนชื่อย่อยหนึ่งชั้น (เช่น https://*.kemi-classroom.pages.dev แบบเดียวกับ CORS ของ B2) */
export function originAllowed(origin: string, allowed: readonly string[]): boolean {
  return allowed.some((pattern) => {
    const star = pattern.indexOf('*')
    if (star < 0) return origin === pattern
    const head = pattern.slice(0, star)
    const tail = pattern.slice(star + 1)
    if (origin.length <= head.length + tail.length) return false
    if (!origin.startsWith(head) || !origin.endsWith(tail)) return false
    return /^[a-z0-9-]+$/.test(origin.slice(head.length, origin.length - tail.length))
  })
}

export function corsHeaders(
  req: Request,
  allowed: readonly string[],
  methods = 'POST, OPTIONS',
): Headers {
  const headers = new Headers({ Vary: 'Origin' })
  const origin = req.headers.get('origin')
  if (origin && originAllowed(origin, allowed)) {
    headers.set('Access-Control-Allow-Origin', origin)
    headers.set(
      'Access-Control-Allow-Headers',
      'authorization, apikey, content-type, x-client-info',
    )
    headers.set('Access-Control-Allow-Methods', methods)
    headers.set('Access-Control-Max-Age', '3600')
  }
  return headers
}

export function json(body: unknown, status: number, base: Headers): Response {
  const headers = new Headers(base)
  headers.set('Content-Type', 'application/json; charset=utf-8')
  headers.set('Cache-Control', 'no-store')
  return new Response(JSON.stringify(body), { status, headers })
}

// สถานะ HTTP ตามรหัส (TECHNICAL_DESIGN 9: พื้นที่เต็มตอบ 507) — รหัสอื่นเป็น 400
const STATUS: Record<string, number> = {
  not_authenticated: 401,
  account_required: 403,
  forbidden: 403,
  admin_mode_required: 403,
  teacher_required: 403,
  not_member: 403,
  not_found: 404,
  term_ended: 409,
  request_key_conflict: 409,
  rate_limited: 429,
  storage_full: 507,
  internal_error: 500,
  // ขั้น complete (P3-04)
  upload_not_found: 404,
  upload_in_progress: 409,
  upload_expired: 410,
  upload_size_mismatch: 422,
  upload_type_mismatch: 422,
  upload_failed: 502,
  download_budget_reached: 503,
}

export function errorResponse(code: string, base: Headers): Response {
  return json({ code: 'P0001', message: code }, STATUS[code] ?? 400, base)
}
