// ถอด HEIC/HEIF เป็น ImageBitmap ใน worker (ไม่ค้างหน้าเว็บ) — โหลดเมื่อเจอไฟล์ HEIC เท่านั้น (heic.ts)
// libheif ใช้ค่าการหมุน/กลับด้านในไฟล์ (irot/imir) ให้แล้ว รูปที่ได้จึงตั้งตรงเหมือนในแอปรูปภาพ
import libheif from 'libheif-js'

type Reply = { ok: true; bitmap: ImageBitmap } | { ok: false; error: string }

self.onmessage = async (event: MessageEvent<ArrayBuffer>) => {
  let reply: Reply
  let transfer: Transferable[] = []
  try {
    const images = new libheif.HeifDecoder().decode(new Uint8Array(event.data))
    const image = images[0]
    if (!image) throw new Error('no_image')
    const width = image.get_width()
    const height = image.get_height()
    const pixels = { data: new Uint8ClampedArray(width * height * 4), width, height }
    // display() เขียนพิกเซลลงบัฟเฟอร์ที่ส่งไป
    await new Promise<void>((resolve, reject) =>
      image.display(pixels, (result) => (result ? resolve() : reject(new Error('decode_failed')))),
    )
    for (const img of images) img.free()
    const bitmap = await createImageBitmap(new ImageData(pixels.data, width, height))
    reply = { ok: true, bitmap }
    transfer = [bitmap]
  } catch (e) {
    reply = { ok: false, error: e instanceof Error ? e.message : 'decode_failed' }
  }
  self.postMessage(reply, { transfer })
}
