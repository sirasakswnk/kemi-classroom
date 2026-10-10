// กติกาไฟล์ก่อนอัปโหลด — SYSTEM_SPEC J4–J6, TECHNICAL_DESIGN 9; ค่าเดียวกับ private.upload_limits() (0016)
// หน้าเว็บตรวจก่อนเริ่มย่อ/อัปโหลด รหัสเดียวกับฝั่งเซิร์ฟเวอร์ (เซิร์ฟเวอร์เป็นด่านหลัง)
// ไบต์แบบ MiB ตามที่ระบบปฏิบัติการแสดง ("20 MB" = 20 × 1024 × 1024)
const MIB = 1024 * 1024

export const UPLOAD_LIMITS = {
  maxFiles: 10,
  /** รูปหลังย่อ (J5) */
  maxImageBytes: 2 * MIB,
  /** PDF ไม่บีบ (J4/J5) */
  maxPdfBytes: 10 * MIB,
  /** รวมต่อชุด (J6: โจทย์และเฉลยนับแยกชุด) */
  maxBatchBytes: 20 * MIB,
  /** รูปต้นฉบับก่อนย่อ (J5) — ตรวจก่อนเริ่มย่อ */
  maxOriginalImageBytes: 20 * MIB,
  /** UX 9: ไฟล์โจทย์/เฉลยรวมเกินนี้แสดงคำแนะนำเรื่องโควตาดาวน์โหลด (ไม่บล็อก) */
  largeSetHintBytes: 5 * MIB,
} as const

export type SourceKind = 'jpeg' | 'png' | 'heic' | 'pdf'
export type UploadType = 'image/jpeg' | 'image/png' | 'application/pdf'

/** รหัสที่หน้าเว็บตรวจเอง (ข้อความอยู่ใน th.errors เหมือนรหัสจากเซิร์ฟเวอร์) */
export type FileRuleCode =
  'too_many_files' | 'file_too_large' | 'file_type_not_allowed' | 'batch_too_large'

const EXT_KIND: Record<string, SourceKind> = {
  jpg: 'jpeg',
  jpeg: 'jpeg',
  png: 'png',
  heic: 'heic',
  heif: 'heic',
  pdf: 'pdf',
}
const TYPE_KIND: Record<string, SourceKind> = {
  'image/jpeg': 'jpeg',
  'image/png': 'png',
  'image/heic': 'heic',
  'image/heif': 'heic',
  'image/heic-sequence': 'heic',
  'image/heif-sequence': 'heic',
  'application/pdf': 'pdf',
}

/** ช่องเลือกไฟล์ — เบราว์เซอร์มือถือบางรุ่นไม่รู้จักนามสกุล HEIC จึงใส่ชนิด image/* ไว้ด้วย (ตรวจซ้ำที่ kindOf) */
export const ACCEPT =
  '.jpg,.jpeg,.png,.heic,.heif,.pdf,image/jpeg,image/png,image/heic,image/heif,application/pdf'

const extensionOf = (name: string) => /\.([a-z0-9]+)$/i.exec(name)?.[1]?.toLowerCase() ?? ''

/**
 * ชนิดไฟล์จาก MIME ก่อน (ถ้ามี) แล้วจึงนามสกุล — Android/Windows บางเครื่องส่ง type ว่างหรือ
 * application/octet-stream ให้ HEIC; เนื้อจริงตรวจซ้ำตอนถอดรูป และเซิร์ฟเวอร์ตรวจ magic number ตอน complete
 */
export function kindOf(file: { name: string; type: string }): SourceKind | null {
  return TYPE_KIND[file.type.toLowerCase()] ?? EXT_KIND[extensionOf(file.name)] ?? null
}

/** ตรวจไฟล์เดี่ยวก่อนเริ่มย่อ: ชนิด (J4) และขนาดต้นฉบับ (J5 รูป ≤ 20 MB, PDF ≤ 10 MB) */
export function checkOriginal(file: {
  name: string
  type: string
  size: number
}): FileRuleCode | null {
  const kind = kindOf(file)
  if (!kind) return 'file_type_not_allowed'
  if (file.size < 1) return 'file_type_not_allowed'
  const max = kind === 'pdf' ? UPLOAD_LIMITS.maxPdfBytes : UPLOAD_LIMITS.maxOriginalImageBytes
  return file.size > max ? 'file_too_large' : null
}

/** ไฟล์ที่พร้อมอัปโหลด (หลังย่อ) เกินเพดานต่อไฟล์หรือไม่ */
export function checkPrepared(type: UploadType, size: number): FileRuleCode | null {
  const max = type === 'application/pdf' ? UPLOAD_LIMITS.maxPdfBytes : UPLOAD_LIMITS.maxImageBytes
  return size > max ? 'file_too_large' : null
}

/** ตรวจทั้งชุด (J6): จำนวนไฟล์และขนาดรวมของไฟล์ที่พร้อม/อัปโหลดแล้ว */
export function checkSet(count: number, totalBytes: number): FileRuleCode | null {
  if (count > UPLOAD_LIMITS.maxFiles) return 'too_many_files'
  if (totalBytes > UPLOAD_LIMITS.maxBatchBytes) return 'batch_too_large'
  return null
}

/**
 * ชื่อไฟล์ที่ส่งให้เซิร์ฟเวอร์ (0016: 1–255 ตัว ไม่มีอักขระควบคุม / หรือ \) — ตัดอักขระต้องห้าม เว้นวรรคซ้ำ
 * แล้วเปลี่ยนนามสกุลตามชนิดหลังแปลง (เช่น IMG_0001.HEIC → IMG_0001.jpg)
 */
export function uploadName(original: string, type: UploadType): string {
  const ext = type === 'image/jpeg' ? 'jpg' : type === 'image/png' ? 'png' : 'pdf'
  // ตัดอักขระควบคุม (รวม DEL) และตัวแบ่งโฟลเดอร์ / กับ \ ออกจากชื่อไฟล์
  const unsafe = (ch: string) => {
    const code = ch.codePointAt(0) ?? 0
    return code < 0x20 || code === 0x7f || ch === '/' || ch === '\\'
  }
  const cleaned = Array.from(original, (ch) => (unsafe(ch) ? ' ' : ch))
    .join('')
    .replace(/\s+/g, ' ')
    .trim()
  const stem = cleaned.replace(/\.[a-z0-9]{1,5}$/i, '').trim() || 'file'
  const suffix = `.${ext}`
  // ตัดตามจำนวน code point ไม่ให้สระ/วรรณยุกต์ไทยขาดกลางคู่ surrogate
  const room = 255 - suffix.length
  const chars = Array.from(stem)
  return (chars.length > room ? chars.slice(0, room).join('').trimEnd() : stem) + suffix
}

/** ขนาดอ่านง่าย: 940 KB, 1.4 MB (ฐาน 1024 ตามป้าย "20 MB") */
export function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`
  const mb = bytes / MIB
  return `${mb >= 10 ? Math.round(mb) : Math.round(mb * 10) / 10} MB`
}
