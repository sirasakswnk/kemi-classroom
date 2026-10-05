// libheif-js (ตัวถอด HEIC แบบ JavaScript ล้วน — ไม่ใช้ WASM/eval จึงรันใต้ CSP script-src 'self' ได้)
// ประกาศเฉพาะส่วนที่ heic.worker.ts ใช้ (แพ็กเกจไม่มี type ระดับนี้)
declare module 'libheif-js' {
  interface HeifImage {
    get_width(): number
    get_height(): number
    display(
      target: { data: Uint8ClampedArray; width: number; height: number },
      callback: (result: { data: Uint8ClampedArray; width: number; height: number } | null) => void,
    ): void
    free(): void
  }
  interface LibHeif {
    HeifDecoder: new () => { decode(data: ArrayBuffer | Uint8Array): HeifImage[] }
  }
  const libheif: LibHeif
  export default libheif
}
