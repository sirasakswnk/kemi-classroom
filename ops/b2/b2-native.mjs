// ตัวช่วยของสคริปต์ B2 ที่ผู้ใช้รันเองบนเครื่อง (apply-settings.mjs, proof.mjs)
// - ถามกุญแจแบบไม่แสดงบนจอ ไม่เก็บลงไฟล์ ไม่พิมพ์ค่าออก
// - เรียก Native API v4 ของ B2 และนับจำนวนคำขอ (เพดานรายวันใช้ร่วมทั้งบัญชี — TECHNICAL_DESIGN 9.3 ข้อ 6)

/** bucket ที่สคริปต์ยอมแตะ — kemi-files (prod) รอระยะ 7 */
export const DEV_BUCKET = 'kemi-dev-files'
export const DEV_ENDPOINT = 'https://s3.eu-central-003.backblazeb2.com'

export const counts = { classA: 0, classB: 0, classC: 0, preflight: 0 }

/** ถามค่าลับโดยไม่ echo — ต้องเป็น terminal จริง (PowerShell/Windows Terminal) ไม่งั้นค่าที่พิมพ์อาจโผล่บนจอ */
export function askSecret(label) {
  const { stdin, stdout } = process
  if (!stdin.isTTY || typeof stdin.setRawMode !== 'function') {
    throw new Error(
      'ต้องรันใน PowerShell หรือ Windows Terminal (ช่องนี้ซ่อนตัวอักษรที่พิมพ์ไม่ได้ — ไม่ถามกุญแจเพื่อไม่ให้ค่าโผล่บนจอ)',
    )
  }
  stdout.write(`${label} (ซ่อนตัวอักษร วางแล้วกด Enter): `)
  stdin.setRawMode(true)
  stdin.resume()
  stdin.setEncoding('utf8')
  return new Promise((resolve, reject) => {
    let value = ''
    const done = (fn) => {
      stdin.off('data', onData)
      stdin.setRawMode(false)
      stdin.pause()
      stdout.write('\n')
      fn()
    }
    const onData = (chunk) => {
      for (const c of chunk) {
        if (c === '\r' || c === '\n') return done(() => resolve(value.trim()))
        if (c === '\u0003') return done(() => reject(new Error('ยกเลิก')))
        if (c === '\u007f' || c === '\b') value = value.slice(0, -1)
        else value += c
      }
    }
    stdin.on('data', onData)
  })
}

/** อ่านจาก env (ถ้าผู้ใช้ตั้งไว้ใน session) หรือถาม */
export async function secretFromEnvOrAsk(name, label) {
  const v = process.env[name]?.trim()
  return v ? v : askSecret(label)
}

/** ข้อความ error ของ B2 โดยไม่ยกเนื้อคำตอบทั้งก้อน (กันค่าลับหลุด) */
async function b2Error(res, what) {
  let detail = ''
  try {
    const body = await res.json()
    detail = [body.code, body.message].filter(Boolean).join(': ')
  } catch {
    detail = ''
  }
  return new Error(`${what} ล้มเหลว (HTTP ${res.status}${detail ? ` ${detail}` : ''})`)
}

/** b2_authorize_account (Class C) */
export async function authorize(keyId, appKey) {
  counts.classC++
  const res = await fetch('https://api.backblazeb2.com/b2api/v4/b2_authorize_account', {
    headers: { Authorization: `Basic ${Buffer.from(`${keyId}:${appKey}`).toString('base64')}` },
  })
  if (!res.ok) throw await b2Error(res, 'b2_authorize_account')
  const body = await res.json()
  const storage = body.apiInfo.storageApi
  return {
    accountId: body.accountId,
    token: body.authorizationToken,
    apiUrl: storage.apiUrl,
    s3ApiUrl: storage.s3ApiUrl,
    allowed: storage.allowed,
  }
}

/** เรียก Native API แบบ POST JSON (Class C สำหรับงานจัดการ bucket/key) */
export async function call(auth, name, body) {
  counts.classC++
  const res = await fetch(`${auth.apiUrl}/b2api/v4/${name}`, {
    method: 'POST',
    headers: { Authorization: auth.token, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw await b2Error(res, name)
  return res.json()
}

export function printCounts() {
  console.log(
    `คำขอที่ใช้กับ B2: Class A ${counts.classA} (ไม่นับเพดาน) · Class B ${counts.classB} · Class C ${counts.classC}` +
      (counts.preflight ? ` · CORS preflight (OPTIONS) ${counts.preflight}` : ''),
  )
}
