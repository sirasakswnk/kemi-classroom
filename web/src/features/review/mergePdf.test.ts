import { readFileSync } from 'node:fs'
import { PDFDocument } from 'pdf-lib'
import { describe, expect, it } from 'vitest'
import { A4, fitImage, mergeToPdf, type MergeInput } from './mergePdf'
import { pdfFileName } from './pdfFileName'

const fixture = (name: string) =>
  new Uint8Array(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)))

async function makePdf(sizes: [number, number][]): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  for (const s of sizes) doc.addPage(s)
  return doc.save()
}

const sizesOf = async (bytes: Uint8Array) => {
  const doc = await PDFDocument.load(bytes)
  return doc
    .getPages()
    .map((p) => [Math.round(p.getWidth() * 100) / 100, Math.round(p.getHeight() * 100) / 100])
}

const jpg = (name = 'รูป.jpg'): MergeInput => ({
  name,
  contentType: 'image/jpeg',
  bytes: fixture('landscape.jpg'),
})
const png = (name = 'รูป.png'): MergeInput => ({
  name,
  contentType: 'image/png',
  bytes: fixture('portrait.png'),
})
const pdf = async (name: string, sizes: [number, number][]): Promise<MergeInput> => ({
  name,
  contentType: 'application/pdf',
  bytes: await makePdf(sizes),
})

describe('รวมรูปและ PDF เป็นไฟล์เดียว', () => {
  it('รูปแนวนอน → หน้า A4 แนวนอน, รูปแนวตั้ง → A4 แนวตั้ง, พอดีหน้าคงสัดส่วนและอยู่กลาง', () => {
    const wide = fitImage(400, 200)
    expect(wide.page).toEqual({ w: A4.h, h: A4.w })
    expect(wide.w).toBeCloseTo(A4.h) // ชนกรอบด้านกว้าง
    expect(wide.w / wide.h).toBeCloseTo(2)
    expect(wide.x).toBeCloseTo(0)
    expect(wide.y).toBeCloseTo((A4.w - wide.h) / 2)
    const tall = fitImage(200, 400)
    expect(tall.page).toEqual({ w: A4.w, h: A4.h })
    expect(tall.h).toBeCloseTo(A4.h)
    expect(tall.x).toBeCloseTo((A4.w - tall.w) / 2)
    // รูปเล็กกว่าหน้าก็ขยายให้พอดี
    expect(fitImage(10, 10).w).toBeCloseTo(A4.w)
  })

  it('ผสม JPEG + PDF 2 หน้า + PNG + PDF 1 หน้า: หน้าเรียงตามลำดับไฟล์ ทุกหน้าครบ', async () => {
    const result = await mergeToPdf([
      jpg(),
      await pdf('ก.pdf', [
        [300, 400],
        [300, 400],
      ]),
      png(),
      await pdf('ข.pdf', [[111, 222]]),
    ])
    expect(result.failed).toEqual([])
    expect(result.pages).toBe(5)
    expect(await sizesOf(result.bytes)).toEqual([
      [A4.h, A4.w],
      [300, 400],
      [300, 400],
      [A4.w, A4.h],
      [111, 222],
    ])
  })

  it('ลำดับตามที่ส่งมา ไม่เรียงตามชนิด (PDF ก่อนรูป)', async () => {
    const result = await mergeToPdf([await pdf('หน้าปก.pdf', [[500, 500]]), png()])
    expect(await sizesOf(result.bytes)).toEqual([
      [500, 500],
      [A4.w, A4.h],
    ])
  })

  it('PDF ที่คัดลอกมามีข้อมูลหน้าจริง (ไม่ใช่หน้าว่างขนาดเดียวกัน)', async () => {
    const src = await PDFDocument.load(fixture('plain-image.pdf'))
    const result = await mergeToPdf([
      { name: 'ภาพ.pdf', contentType: 'application/pdf', bytes: fixture('plain-image.pdf') },
    ])
    const merged = await PDFDocument.load(result.bytes)
    expect(merged.getPageCount()).toBe(src.getPageCount())
    expect(result.bytes.length).toBeGreaterThan(10_000)
  })

  it('ไฟล์ที่เปิดไม่ได้ถูกข้าม บันทึกชื่อไว้ และไม่ทิ้งหน้าครึ่งเดียว', async () => {
    const broken: MergeInput = {
      name: 'เสีย.pdf',
      contentType: 'application/pdf',
      bytes: new TextEncoder().encode('ไม่ใช่ pdf'),
    }
    const weird: MergeInput = {
      name: 'แปลก.gif',
      contentType: 'image/gif',
      bytes: new Uint8Array([1, 2, 3]),
    }
    const badJpeg: MergeInput = {
      name: 'เสีย.jpg',
      contentType: 'image/jpeg',
      bytes: new Uint8Array([1, 2, 3]),
    }
    const progress: [number, number][] = []
    const result = await mergeToPdf([jpg(), broken, weird, badJpeg, png()], (d, t) =>
      progress.push([d, t]),
    )
    expect(result.failed).toEqual(['เสีย.pdf', 'แปลก.gif', 'เสีย.jpg'])
    expect(result.pages).toBe(2)
    expect(await sizesOf(result.bytes)).toEqual([
      [A4.h, A4.w],
      [A4.w, A4.h],
    ])
    expect(progress).toEqual([
      [1, 5],
      [2, 5],
      [3, 5],
      [4, 5],
      [5, 5],
    ])
  })

  it('ไม่มีไฟล์ไหนรวมได้เลย → 0 หน้า และไม่มีไบต์ให้บันทึก', async () => {
    const result = await mergeToPdf([
      { name: 'เสีย.pdf', contentType: 'application/pdf', bytes: new Uint8Array([0]) },
    ])
    expect(result.pages).toBe(0)
    expect(result.bytes.length).toBe(0)
    expect(result.failed).toEqual(['เสีย.pdf'])
  })
})

describe('ชื่อไฟล์ PDF', () => {
  it('{เลขที่}_{ชื่อ}_{นามสกุล}.pdf', () => {
    expect(pdfFileName(12, 'ธนภัทร ใจดี')).toBe('12_ธนภัทร_ใจดี.pdf')
  })
  it('ตัดอักขระที่ใช้เป็นชื่อไฟล์ไม่ได้ / \\ : * ? " < > |', () => {
    expect(pdfFileName(3, 'สม/ชาย ใจ\\ดี')).toBe('3_สมชาย_ใจดี.pdf')
    expect(pdfFileName(3, 'a:b*c?d "e" <f> |g|')).toBe('3_abcd_e_f_g.pdf')
  })
  it('ช่องว่างซ้ำ/แท็บ/ขึ้นบรรทัดใหม่รวมเป็นตัวคั่นเดียว; ชื่อมีหลายคำ (ชื่อกลาง) คงทุกคำ', () => {
    expect(pdfFileName(6, '  อนุชา \t อิ  นทร์แก้ว ')).toBe('6_อนุชา_อิ_นทร์แก้ว.pdf')
    expect(pdfFileName(1, 'ก\u0000ข ค')).toBe('1_กข_ค.pdf')
  })
  it('คงสระ/วรรณยุกต์ไทยครบ (อักขระผสม U+0E31 U+0E34–U+0E3A U+0E47–U+0E4E) — ชื่อเหมือนเดิมทุกตัว', () => {
    expect(pdfFileName(7, 'ภัสสรา อินทร์แก้ว')).toBe('7_ภัสสรา_อินทร์แก้ว.pdf')
    expect(pdfFileName(8, 'ณัฐพงษ์ กิ่งแก้ว')).toBe('8_ณัฐพงษ์_กิ่งแก้ว.pdf')
    expect(pdfFileName(9, 'ศุภกฤต สุขสวัสดิ์')).toBe('9_ศุภกฤต_สุขสวัสดิ์.pdf')
    // ทุกตัวอักขระผสมในนามสกุลเดียว: ิ ี ึ ื ุ ู ั ็ ่ ้ ๊ ๋ ์
    const marks = 'กิ กี กึ กื กุ กู กั ก็ ก่ ก้ ก๊ ก๋ ก์'.split(' ').join('')
    expect(marks).toHaveLength(26)
    expect(pdfFileName(1, `ชื่อ ${marks}`)).toBe(`1_ชื่อ_${marks}.pdf`)
    // รหัสอักขระต้องไม่ถูกแตะ: เทียบทีละ code point
    const name = 'อินทร์แก้ว'
    const out = pdfFileName(null, name).slice(0, -'.pdf'.length)
    expect([...out].map((c) => c.codePointAt(0))).toEqual([...name].map((c) => c.codePointAt(0)))
  })
  it('NFC: ชื่อที่ใส่ในรูป NFD/ลำดับอักขระผสมต่างกัน ได้ชื่อมาตรฐานเดียวกัน (ไม่ทำให้อักขระหาย)', () => {
    const nfd = 'é' // é แบบแยก → รวมเป็นตัวเดียว
    expect(pdfFileName(2, `${nfd} ก`)).toBe('2_é_ก.pdf')
    expect(pdfFileName(3, 'ก้ิ')).toBe(`3_ก้ิ.pdf`) // ลำดับเดิมที่ผู้ใช้ป้อนไม่ถูกจัดใหม่
  })
  it('ช่องว่างที่ผู้ใช้พิมพ์ไว้ในชื่อคงเป็นตัวคั่น (ข้อมูล “อิ นทร์” จะได้ “อิ_นทร์” ตามข้อมูล — แก้ที่รายชื่อ ไม่ใช่ที่ตัวตัดชื่อ)', () => {
    expect(pdfFileName(6, 'อนุชา อิ นทร์แก้ว')).toBe('6_อนุชา_อิ_นทร์แก้ว.pdf')
  })
  it('ไม่มีเลขที่ → ไม่ใส่ส่วนหน้า; ไม่เหลือชื่อ → งานส่ง; ไม่ลงท้ายด้วยจุด', () => {
    expect(pdfFileName(null, 'ธนภัทร ใจดี')).toBe('ธนภัทร_ใจดี.pdf')
    expect(pdfFileName(null, '***')).toBe('งานส่ง.pdf')
    expect(pdfFileName(5, 'นาย ก.')).toBe('5_นาย_ก.pdf')
  })
})
