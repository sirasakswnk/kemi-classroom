// เตรียมไฟล์ก่อนอัปโหลด — TECHNICAL_DESIGN 9 (ย่อรูป ≤ 2 MB, PDF ไม่บีบ, HEIC → JPEG) และ 9.2 ข้อ 7
// ถอดรูปด้วย createImageBitmap (หมุนตาม EXIF) แล้วย่อด้วย canvas ทีละครึ่ง ไม่สร้าง canvas ขนาดเต็มของรูปต้นฉบับ
// (Safari บน iPhone จำกัดพื้นที่ canvas — รูป 48 ล้านพิกเซลวาดลง canvas ครึ่งขนาดได้ แต่ขนาดเต็มไม่ได้)
import { decodeHeic } from './heic'
import { UPLOAD_LIMITS, uploadName, type SourceKind, type UploadType } from './rules'

/** ด้านยาวสูงสุดที่ลองตามลำดับ และคุณภาพ JPEG ที่ลองในแต่ละขนาด — หยุดที่ครั้งแรกที่ ≤ 2 MB */
export const MAX_EDGES = [2560, 2048, 1600, 1280, 1024] as const
export const JPEG_QUALITIES = [0.85, 0.75, 0.65] as const

export interface Size {
  width: number
  height: number
}

/** ขนาดที่ด้านยาวไม่เกิน maxEdge (ไม่ขยายรูปเล็ก) */
export function fitWithin(size: Size, maxEdge: number): Size {
  const scale = Math.min(1, maxEdge / Math.max(size.width, size.height))
  return {
    width: Math.max(1, Math.round(size.width * scale)),
    height: Math.max(1, Math.round(size.height * scale)),
  }
}

/**
 * ขั้นการย่อจากขนาดต้นฉบับถึงเป้าหมาย: ลดทีละครึ่งจนเหลือไม่เกินสองเท่าของเป้าหมาย แล้วจบที่เป้าหมาย
 * (ย่อทีละครั้งเดียวมาก ๆ ด้วย drawImage ได้ภาพแตก/ตัวหนังสือขาด) — คืนเฉพาะขนาดปลายทางของแต่ละขั้น
 */
export function downscaleSteps(source: Size, target: Size): Size[] {
  const steps: Size[] = []
  let w = source.width
  let h = source.height
  while (w / 2 >= target.width * 2 && h / 2 >= target.height * 2) {
    w = Math.round(w / 2)
    h = Math.round(h / 2)
    steps.push({ width: w, height: h })
  }
  steps.push(target)
  return steps
}

/** ลำดับที่ลอง: ทุกคุณภาพของขนาดแรก แล้วจึงลดขนาด */
export function encodeAttempts(): { maxEdge: number; quality: number }[] {
  return MAX_EDGES.flatMap((maxEdge) => JPEG_QUALITIES.map((quality) => ({ maxEdge, quality })))
}

export interface PreparedFile {
  blob: Blob
  type: UploadType
  /** ชื่อที่ส่งให้เซิร์ฟเวอร์ (เปลี่ยนนามสกุลแล้วถ้าแปลงเป็น JPEG) */
  name: string
  /** แปลงชนิด/ย่อแล้ว (false = ส่งไฟล์เดิม) */
  converted: boolean
}

/** ไฟล์ที่เตรียมไม่ได้ — เหตุใช้แสดงข้อความที่แถวไฟล์ */
export class PrepareError extends Error {
  readonly reason: 'heic_failed' | 'image_unreadable' | 'too_large_after_resize'
  constructor(reason: PrepareError['reason']) {
    super(reason)
    this.reason = reason
  }
}

type AnyCanvas = OffscreenCanvas | HTMLCanvasElement

function makeCanvas(size: Size): AnyCanvas {
  if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(size.width, size.height)
  const canvas = document.createElement('canvas')
  canvas.width = size.width
  canvas.height = size.height
  return canvas
}

// คืนหน่วยความจำของ canvas ทันที (Safari เก็บไว้จน GC)
function release(canvas: AnyCanvas) {
  canvas.width = 0
  canvas.height = 0
}

function draw(source: CanvasImageSource, size: Size): AnyCanvas {
  const canvas = makeCanvas(size)
  const ctx = canvas.getContext('2d') as
    OffscreenCanvasRenderingContext2D | CanvasRenderingContext2D | null
  if (!ctx) throw new PrepareError('image_unreadable')
  // พื้นขาว: PNG โปร่งใสแปลงเป็น JPEG แล้วไม่กลายเป็นพื้นดำ
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, size.width, size.height)
  ctx.imageSmoothingEnabled = true
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(source, 0, 0, size.width, size.height)
  return canvas
}

function toJpeg(canvas: AnyCanvas, quality: number): Promise<Blob> {
  if ('convertToBlob' in canvas) return canvas.convertToBlob({ type: 'image/jpeg', quality })
  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new PrepareError('image_unreadable'))),
      'image/jpeg',
      quality,
    ),
  )
}

/** ย่อเป็น JPEG ≤ 2 MB ตามลำดับ encodeAttempts() */
export async function resizeToJpeg(bitmap: ImageBitmap): Promise<Blob> {
  const source: Size = { width: bitmap.width, height: bitmap.height }
  let lastEdge = 0
  let skipEdge = false
  let current: Size | null = null
  let canvas: AnyCanvas | null = null
  try {
    for (const { maxEdge, quality } of encodeAttempts()) {
      if (maxEdge !== lastEdge) {
        lastEdge = maxEdge
        const target = fitWithin(source, maxEdge)
        // รูปเล็กกว่าขนาดนี้: ได้ขนาดเดิมซ้ำ ทุกคุณภาพลองไปแล้ว
        skipEdge =
          current !== null && current.width === target.width && current.height === target.height
        if (!skipEdge) {
          if (canvas) release(canvas)
          canvas = null
          let from: CanvasImageSource = bitmap
          for (const size of downscaleSteps(source, target)) {
            const next = draw(from, size)
            if (canvas) release(canvas)
            canvas = next
            from = next
          }
          current = target
        }
      }
      if (skipEdge || !canvas) continue
      const blob = await toJpeg(canvas, quality)
      if (blob.size <= UPLOAD_LIMITS.maxImageBytes) return blob
    }
  } finally {
    if (canvas) release(canvas)
  }
  throw new PrepareError('too_large_after_resize')
}

async function decodeBitmap(file: Blob, kind: SourceKind): Promise<ImageBitmap> {
  try {
    // Safari 17+ ถอด HEIC เองได้ — ลองก่อน ไม่ต้องโหลดตัวถอด
    return await createImageBitmap(file, { imageOrientation: 'from-image' })
  } catch {
    if (kind !== 'heic') throw new PrepareError('image_unreadable')
  }
  try {
    return await decodeHeic(file)
  } catch {
    throw new PrepareError('heic_failed')
  }
}

/**
 * เตรียมไฟล์หนึ่งไฟล์ (ผ่าน checkOriginal แล้ว):
 *   - PDF ส่งไฟล์เดิม (ไม่บีบ)
 *   - PNG ≤ 2 MB ส่งไฟล์เดิม คงเป็น PNG; ใหญ่กว่านั้นย่อเป็น JPEG
 *   - JPEG/HEIC ย่อและเข้ารหัสใหม่เป็น JPEG เสมอ (หมุนตาม EXIF และตัดข้อมูล EXIF เช่นตำแหน่ง GPS ออก)
 */
export async function prepareFile(file: File, kind: SourceKind): Promise<PreparedFile> {
  if (kind === 'pdf') {
    return {
      blob: file,
      type: 'application/pdf',
      name: uploadName(file.name, 'application/pdf'),
      converted: false,
    }
  }
  if (kind === 'png' && file.size <= UPLOAD_LIMITS.maxImageBytes) {
    return {
      blob: file,
      type: 'image/png',
      name: uploadName(file.name, 'image/png'),
      converted: false,
    }
  }
  const bitmap = await decodeBitmap(file, kind)
  try {
    const blob = await resizeToJpeg(bitmap)
    return { blob, type: 'image/jpeg', name: uploadName(file.name, 'image/jpeg'), converted: true }
  } finally {
    bitmap.close()
  }
}
