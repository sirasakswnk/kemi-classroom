// PDF ที่มีภาพซึ่งตัวดูในหน้าตรวจแสดงไม่ได้ (TECHNICAL_DESIGN ส่วน 6 "ตัวดูไฟล์ในหน้าตรวจ", ผู้ใช้เลือกทาง A 18 ต.ค. 2026)
// pdf.js ปิด WebAssembly (CSP ไม่มี 'wasm-unsafe-eval') จึงถอดภาพ JPEG 2000 / JBIG2 ไม่ได้ และเว้นว่างเงียบ ๆ
// ตัวกรองของภาพอยู่ในพจนานุกรมของ stream ซึ่งอยู่ใน object stream ที่บีบอัดไม่ได้ตามสเปก PDF — ค้นไบต์ดิบตรง ๆ จึงพอ
const UNSUPPORTED = ['/JPXDecode', '/JBIG2Decode']

export function hasUnsupportedImages(bytes: Uint8Array): boolean {
  // latin1 แปลงไบต์ละหนึ่งตัวอักษร ไม่ทำให้ไบต์ไบนารีเสีย
  const text = new TextDecoder('latin1').decode(bytes)
  return UNSUPPORTED.some((name) => text.includes(name))
}
