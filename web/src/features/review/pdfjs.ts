import { getDocument, GlobalWorkerOptions } from 'pdfjs-dist'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'

// pdf.js แยกไฟล์ (import แบบ lazy จาก FilePanes) — worker เป็นไฟล์ใน /assets ของเราเอง (CSP: default-src 'self')
// ไม่ใช้ WebAssembly (CSP ไม่มี 'wasm-unsafe-eval') — รูป JPX/JBIG2 ใน PDF ที่ต้องใช้ wasm อาจแสดงไม่ครบ
GlobalWorkerOptions.workerSrc = workerUrl

/** เปิด PDF จากข้อมูลในหน่วยความจำ (ไม่ขอ Range จากเครือข่าย) — ผู้เรียก destroy() task เมื่อเลิกใช้ */
export function openDocument(data: Uint8Array) {
  return getDocument({ data, useWasm: false, useSystemFonts: true })
}
