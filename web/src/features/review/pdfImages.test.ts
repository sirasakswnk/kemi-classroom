/// <reference types="node" />
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { hasUnsupportedImages } from './pdfImages'

// PDF สมมติแบบย่อ: พจนานุกรมภาพ + ไบต์ไบนารีปน (ไม่ต้องเปิดได้จริง — ฟังก์ชันค้นจากไบต์ดิบ)
function pdf(filter: string): Uint8Array {
  const head = new TextEncoder().encode(
    `%PDF-1.5\n6 0 obj\n<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /Filter ${filter} /Length 4 >>\nstream\n`,
  )
  const binary = new Uint8Array([0xff, 0x4f, 0xff, 0x51, 0x00, 0xe2, 0xe3])
  const tail = new TextEncoder().encode('\nendstream\nendobj\n%%EOF\n')
  return new Uint8Array([...head, ...binary, ...tail])
}

describe('hasUnsupportedImages', () => {
  it('พบภาพ JPEG 2000', () => {
    expect(hasUnsupportedImages(pdf('/JPXDecode'))).toBe(true)
  })

  it('พบภาพ JBIG2 (รวมแบบหลายตัวกรอง)', () => {
    expect(hasUnsupportedImages(pdf('[/FlateDecode /JBIG2Decode]'))).toBe(true)
  })

  it('ภาพ JPEG/Flate ธรรมดาไม่เตือน', () => {
    expect(hasUnsupportedImages(pdf('/DCTDecode'))).toBe(false)
    expect(hasUnsupportedImages(pdf('/FlateDecode'))).toBe(false)
  })

  // PDF สมมติที่เปิดได้จริง (สร้างด้วย Pillow 18 ต.ค. 2026: ข้อความ + ภาพลายทางสังเคราะห์ 2 ภาพ ไม่มีข้อมูลจริง)
  // jpx-image.pdf = ภาพบน JPEG 2000 + ภาพล่าง JPEG; plain-image.pdf = JPEG ทั้งสองภาพ
  it('ไฟล์ PDF จริง: มี JPX เตือน / JPEG อย่างเดียวไม่เตือน', () => {
    const fixture = (name: string) =>
      new Uint8Array(readFileSync(resolve(process.cwd(), 'src/features/review/fixtures', name)))
    expect(hasUnsupportedImages(fixture('jpx-image.pdf'))).toBe(true)
    expect(hasUnsupportedImages(fixture('plain-image.pdf'))).toBe(false)
  })
})
