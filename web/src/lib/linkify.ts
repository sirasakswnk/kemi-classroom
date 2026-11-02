// แยกข้อความที่ผู้ใช้พิมพ์ (โพสต์ เฉลย ความคิดเห็น) เป็นส่วนข้อความกับส่วนลิงก์ — สร้าง element ทีละส่วน ไม่แปลงเป็น HTML
// รับเฉพาะ http(s):// ตัวลิงก์เป็น ASCII ล้วน จึงหยุดเองที่อักษรไทย ตัวห้อย/ตัวยก และ ” ที่ติดกับลิงก์
// ห้ามใช้ regex lookbehind: Safari ก่อน 16.4 (อยู่ใน build target) parse ไม่ผ่าน ทำให้ทั้งเว็บโหลดไม่ขึ้น

export type TextSegment =
  { kind: 'text'; text: string } | { kind: 'link'; text: string; href: string }

// ตัด `,https://` / `;https://` ออกเป็นคนละลิงก์ เพราะ , และ ; อยู่กลาง URL ได้
const URL_PATTERN = /https?:\/\/(?:(?![,;]https?:\/\/)[!#-;=?-[\]_a-z~])+/gi

// ข้อความก่อนหน้าที่ทำให้ไม่ใช่จุดเริ่มลิงก์: ติดตัวอักษร ASCII (xhttps://) หรืออยู่ข้างใน scheme อื่น (data:text/html,https://…)
const NOT_URL_START = /[a-z0-9]$|\b(?:javascript|vbscript|data):\S+$/i

/** ตัดวรรคตอนท้ายลิงก์ออก — วงเล็บปิดตัดเฉพาะที่ไม่มีคู่ในลิงก์ เช่น wiki/Acid_(chemistry) คงไว้ */
function trimTrailing(url: string): string {
  const excess = (close: string, open: string) => url.split(close).length - url.split(open).length
  let parens = excess(')', '(')
  let brackets = excess(']', '[')
  let end = url.length
  while (end > 0) {
    const ch = url.charAt(end - 1)
    if (ch === ')' && parens > 0) parens--
    else if (ch === ']' && brackets > 0) brackets--
    else if (!".,;:!?'".includes(ch)) break
    end--
  }
  return url.slice(0, end)
}

function isValidUrl(url: string): boolean {
  try {
    return new URL(url).hostname !== ''
  } catch {
    return false
  }
}

export function linkify(text: string): TextSegment[] {
  const segments: TextSegment[] = []
  let last = 0
  for (const match of text.matchAll(URL_PATTERN)) {
    const url = trimTrailing(match[0])
    const before = text.slice(last, match.index)
    if (NOT_URL_START.test(before) || !isValidUrl(url)) continue
    if (before) segments.push({ kind: 'text', text: before })
    segments.push({ kind: 'link', text: url, href: url })
    last = match.index + url.length
  }
  if (last < text.length) segments.push({ kind: 'text', text: text.slice(last) })
  return segments
}
