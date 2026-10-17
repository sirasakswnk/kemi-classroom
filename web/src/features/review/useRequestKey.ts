import { useRef } from 'react'

// request key ต่อเนื้อคำขอ (BUILD_PLAN 4.1 ข้อ 6): ส่งซ้ำเพราะเน็ตหลุดใช้ key เดิม (ได้ผลเดิม) — แก้ข้อมูลแล้วได้ key ใหม่
export function useRequestKey() {
  const current = useRef<{ fingerprint: string; key: string } | null>(null)
  return {
    keyFor(fingerprint: string) {
      if (current.current?.fingerprint !== fingerprint)
        current.current = { fingerprint, key: crypto.randomUUID() }
      return current.current.key
    },
    reset() {
      current.current = null
    },
  }
}
