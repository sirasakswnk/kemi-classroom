import { describe, expect, it, vi } from 'vitest'
import { pushDialog, removeDialog, subscribeDialogs, topDialog } from './dialogStack'

// ใช้วัตถุแทน <dialog> (สภาพแวดล้อม node ไม่มี DOM) — store สนใจแค่ตัวตนของวัตถุ
const fake = (name: string) => ({ name }) as unknown as HTMLDialogElement

describe('dialogStack', () => {
  it('กล่องบนสุดคือกล่องที่เปิดล่าสุด และแจ้งผู้ติดตามทุกครั้งที่เปลี่ยน', () => {
    const listener = vi.fn()
    const unsubscribe = subscribeDialogs(listener)
    const a = fake('a')
    const b = fake('b')

    expect(topDialog()).toBeNull()
    pushDialog(a)
    pushDialog(b)
    expect(topDialog()).toBe(b)
    removeDialog(b)
    expect(topDialog()).toBe(a)
    removeDialog(a)
    expect(topDialog()).toBeNull()
    expect(listener).toHaveBeenCalledTimes(4)

    unsubscribe()
    pushDialog(a)
    expect(listener).toHaveBeenCalledTimes(4)
    removeDialog(a)
  })

  it('ปิดกล่องที่ไม่ใช่บนสุดได้โดยกล่องบนสุดไม่เปลี่ยน', () => {
    const a = fake('a')
    const b = fake('b')
    pushDialog(a)
    pushDialog(b)
    removeDialog(a)
    expect(topDialog()).toBe(b)
    removeDialog(b)
    expect(topDialog()).toBeNull()
  })
})
