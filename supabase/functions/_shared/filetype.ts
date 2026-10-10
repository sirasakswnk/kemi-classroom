// ชนิดไฟล์จาก magic number (ไบต์ต้นไฟล์) — ไม่เชื่อ MIME หรือชื่อไฟล์จากหน้าเว็บ (TECHNICAL_DESIGN 9 ข้อ 2)
// ขั้น complete อ่านแค่ 16 ไบต์แรก ซึ่งพอสำหรับทั้งสามชนิด
export type FileType = 'image/jpeg' | 'image/png' | 'application/pdf'

const SIGNATURES: [FileType, number[]][] = [
  ['image/jpeg', [0xff, 0xd8, 0xff]],
  ['image/png', [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]],
  ['application/pdf', [0x25, 0x50, 0x44, 0x46, 0x2d]], // %PDF-
]

export function detectType(bytes: Uint8Array): FileType | null {
  for (const [type, sig] of SIGNATURES) {
    if (bytes.length >= sig.length && sig.every((b, i) => bytes[i] === b)) return type
  }
  return null
}
