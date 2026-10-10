// เรียกตัวถอด HEIC ใน worker แยกไฟล์ (chunk ของตัวเอง ไม่อยู่ใน bundle หลัก) — สร้าง worker ต่อไฟล์แล้วปิดทันที
// worker โหลดจาก origin เดียวกัน จึงผ่าน CSP default-src 'self' (ตัวถอดสำเร็จรูปที่สร้าง worker จาก blob: ถูก CSP บล็อก)

/** รูป HEIC ขนาดใหญ่ถอดด้วย JavaScript บนมือถือรุ่นเก่าอาจใช้หลายวินาที — เกินนี้ถือว่าแปลงไม่ได้ */
export const HEIC_TIMEOUT_MS = 90_000

export function decodeHeic(file: Blob, timeoutMs = HEIC_TIMEOUT_MS): Promise<ImageBitmap> {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./heic.worker.ts', import.meta.url), { type: 'module' })
    const done = (fn: () => void) => {
      clearTimeout(timer)
      worker.terminate()
      fn()
    }
    const timer = setTimeout(() => done(() => reject(new Error('heic_timeout'))), timeoutMs)
    worker.onmessage = (
      event: MessageEvent<{ ok: true; bitmap: ImageBitmap } | { ok: false; error: string }>,
    ) => {
      const reply = event.data
      done(() => (reply.ok ? resolve(reply.bitmap) : reject(new Error(reply.error))))
    }
    worker.onerror = () => done(() => reject(new Error('heic_worker_failed')))
    file.arrayBuffer().then(
      (buffer) => worker.postMessage(buffer, [buffer]),
      (error: unknown) => done(() => reject(error)),
    )
  })
}
