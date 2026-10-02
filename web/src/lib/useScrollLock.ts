import { useEffect } from 'react'

// ล็อกการเลื่อนหน้าด้านหลังขณะเปิด Sheet/Modal
// ใช้ body { position: fixed } แทน overflow: hidden อย่างเดียว เพราะ iOS Safari ยังเลื่อนหน้าด้วยนิ้วได้
// นับจำนวนผู้ล็อก เพื่อให้เปิดซ้อนกันได้และปลดเมื่อปิดตัวสุดท้าย
let lockCount = 0
let saved: { scrollY: number; cssText: string } | null = null

function lock() {
  if (lockCount++ > 0) return
  const { style } = document.body
  saved = { scrollY: window.scrollY, cssText: style.cssText }
  Object.assign(style, {
    position: 'fixed',
    top: `-${saved.scrollY}px`,
    left: '0',
    right: '0',
    overflow: 'hidden',
  })
}

function unlock() {
  if (--lockCount > 0 || !saved) return
  document.body.style.cssText = saved.cssText
  window.scrollTo(0, saved.scrollY)
  saved = null
}

export function useScrollLock(active: boolean) {
  useEffect(() => {
    if (!active) return
    lock()
    return unlock
  }, [active])
}
