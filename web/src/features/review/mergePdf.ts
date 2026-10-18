import type { PDFDocument, PDFImage } from 'pdf-lib'

// รวมไฟล์ของงานส่งหนึ่งชุดเป็น PDF เดียว (P4-08, UX 9 “ดาวน์โหลด PDF”) — ทำในเครื่องครูทั้งหมด ไม่ส่งไฟล์ไปที่อื่น
//   รูป JPEG/PNG: หน้าละรูป ขนาดหน้า A4 ตามแนวรูป (รูปแนวนอน → หน้าแนวนอน) ย่อ/ขยายให้พอดีหน้าโดยคงสัดส่วน วางกลางหน้า
//   PDF: คัดลอกทุกหน้าตามเดิม (ไม่แปลงเนื้อหา — ภาพ JPX/JBIG2 ก็ยังอยู่ครบ)
// ไฟล์ที่เปิดไม่ได้ (เสีย มีรหัสผ่าน ชนิดไม่รู้จัก) ไม่ทำให้ทั้งชุดล้ม — เก็บชื่อไว้ใน failed ให้หน้าจอถามว่าจะรวมที่เหลือต่อไหม

export interface MergeInput {
  name: string
  contentType: string
  bytes: Uint8Array
}

export interface MergeResult {
  bytes: Uint8Array
  pages: number
  /** ชื่อไฟล์ที่เปิดไม่ได้ (ตามลำดับ) */
  failed: string[]
}

/** A4 เป็นจุด (1/72 นิ้ว) */
export const A4 = { w: 595.28, h: 841.89 } as const

/** ขนาดหน้าและตำแหน่งรูป: หน้า A4 ตามแนวรูป, รูปพอดีหน้า คงสัดส่วน วางกลาง */
export function fitImage(imgW: number, imgH: number) {
  const landscape = imgW > imgH
  const page = landscape ? { w: A4.h, h: A4.w } : { w: A4.w, h: A4.h }
  const scale = Math.min(page.w / imgW, page.h / imgH)
  const w = imgW * scale
  const h = imgH * scale
  return { page, x: (page.w - w) / 2, y: (page.h - h) / 2, w, h }
}

const isJpeg = (t: string) => t === 'image/jpeg' || t === 'image/jpg'
const isPng = (t: string) => t === 'image/png'
const isPdf = (t: string) => t === 'application/pdf'

/** ไฟล์ตามลำดับที่ส่งมา → PDF เดียว; รูป/PDF ที่เปิดไม่ได้ข้ามและบันทึกใน failed */
export async function mergeToPdf(
  inputs: MergeInput[],
  onProgress?: (done: number, total: number) => void,
): Promise<MergeResult> {
  const { PDFDocument } = await import('pdf-lib')
  const out = await PDFDocument.create()
  const failed: string[] = []
  for (const [i, input] of inputs.entries()) {
    try {
      await addFile(out, input, PDFDocument)
    } catch {
      failed.push(input.name)
    }
    onProgress?.(i + 1, inputs.length)
    // คืนการควบคุมให้หน้าจอวาดความคืบหน้าระหว่างไฟล์
    await new Promise((r) => setTimeout(r, 0))
  }
  const pages = out.getPageCount()
  // ไม่มีหน้าเลย = บันทึกไม่ได้ (PDF ว่าง) ผู้เรียกดูจาก pages
  const bytes = pages > 0 ? await out.save() : new Uint8Array()
  return { bytes, pages, failed }
}

async function addFile(out: PDFDocument, input: MergeInput, Doc: typeof PDFDocument) {
  if (isPdf(input.contentType)) {
    // ไม่ใช้ ignoreEncryption: PDF มีรหัสผ่านต้องล้ม (ไม่คัดลอกหน้าที่อ่านไม่ได้)
    const src = await Doc.load(input.bytes, { updateMetadata: false })
    const copied = await out.copyPages(src, src.getPageIndices())
    // ทำทีเดียวหลังคัดลอกสำเร็จ — ไฟล์ที่ล้มกลางทางไม่ทิ้งหน้าครึ่งเดียว
    for (const p of copied) out.addPage(p)
    return
  }
  let image: PDFImage
  if (isJpeg(input.contentType)) image = await out.embedJpg(input.bytes)
  else if (isPng(input.contentType)) image = await out.embedPng(input.bytes)
  else throw new Error('unsupported_type')
  const fit = fitImage(image.width, image.height)
  const page = out.addPage([fit.page.w, fit.page.h])
  page.drawImage(image, { x: fit.x, y: fit.y, width: fit.w, height: fit.h })
}
