import { beforeEach, describe, expect, it } from 'vitest'
import {
  hasNewAnnouncement,
  latestAnnouncement,
  markSeen,
  readSeen,
  resetSeenMemory,
  seenKey,
  type StorageLike,
} from './seenAnnouncements'

const now = Date.parse('2026-10-10T05:00:00Z')
const ann = (published_at: string) => ({ kind: 'announcement', published_at })
const hw = (published_at: string) => ({ kind: 'homework', published_at })

function memoryStorage(): StorageLike & { data: Map<string, string> } {
  const data = new Map<string, string>()
  return {
    data,
    getItem: (k) => data.get(k) ?? null,
    setItem: (k, v) => void data.set(k, v),
  }
}
const broken: StorageLike = {
  getItem: () => {
    throw new Error('SecurityError')
  },
  setItem: () => {
    throw new Error('QuotaExceededError')
  },
}

beforeEach(() => resetSeenMemory())

describe('ป้าย “ใหม่” ของประกาศ (UX 5)', () => {
  const posts = [
    ann('2026-10-08T01:00:00Z'),
    ann('2026-10-05T01:00:00Z'),
    hw('2026-10-09T01:00:00Z'),
  ]

  it('ยังไม่เคยเห็น + ประกาศภายใน 7 วัน → ขึ้นป้าย', () => {
    expect(hasNewAnnouncement(posts, null, now)).toBe(true)
  })
  it('เห็นแล้วถึงประกาศล่าสุด → ไม่ขึ้น', () => {
    expect(hasNewAnnouncement(posts, '2026-10-08T01:00:00Z', now)).toBe(false)
  })
  it('มีประกาศใหม่หลังเห็น → ขึ้นอีก', () => {
    expect(
      hasNewAnnouncement([...posts, ann('2026-10-09T08:00:00Z')], '2026-10-08T01:00:00Z', now),
    ).toBe(true)
  })
  it('ครูแก้ไขประกาศเดิม (content_updated_at) ไม่ทำให้ขึ้นใหม่ — ใช้ published_at อย่างเดียว', () => {
    const edited = [{ ...ann('2026-10-08T01:00:00Z'), content_updated_at: '2026-10-10T04:00:00Z' }]
    expect(hasNewAnnouncement(edited, '2026-10-08T01:00:00Z', now)).toBe(false)
  })
  it('ประกาศเกิน 7 วัน → ไม่ขึ้นแม้ยังไม่เคยเห็น; การบ้านไม่นับ', () => {
    expect(hasNewAnnouncement([ann('2026-10-03T04:59:59Z')], null, now)).toBe(false)
    expect(hasNewAnnouncement([ann('2026-10-03T05:00:00Z')], null, now)).toBe(true)
    expect(hasNewAnnouncement([hw('2026-10-09T01:00:00Z')], null, now)).toBe(false)
  })
  it('published_at ล่าสุดของประกาศ', () => {
    expect(latestAnnouncement(posts)).toBe('2026-10-08T01:00:00Z')
    expect(latestAnnouncement([hw('2026-10-09T01:00:00Z')])).toBeNull()
  })
})

describe('จำว่าเห็นแล้ว (localStorage)', () => {
  it('คีย์แยกตามบัญชี + ห้อง', () => {
    expect(seenKey('acc-1', 'room-1')).toBe('kemi:seenAnnouncements:acc-1:room-1')
  })
  it('จดเวลาของประกาศ ไม่ถอยหลัง', () => {
    const s = memoryStorage()
    const key = seenKey('acc-1', 'room-1')
    markSeen(key, '2026-10-08T01:00:00Z', s)
    markSeen(key, '2026-10-05T01:00:00Z', s)
    expect(s.data.get(key)).toBe('2026-10-08T01:00:00Z')
    expect(readSeen(key, s)).toBe('2026-10-08T01:00:00Z')
  })
  it('คนละบัญชีบนเครื่องเดียวกันไม่ใช้สถานะร่วมกัน', () => {
    const s = memoryStorage()
    markSeen(seenKey('acc-1', 'room-1'), '2026-10-08T01:00:00Z', s)
    expect(readSeen(seenKey('acc-2', 'room-1'), s)).toBeNull()
    expect(readSeen(seenKey('acc-1', 'room-2'), s)).toBeNull()
  })
  it('localStorage ใช้ไม่ได้: ไม่ throw อ่านได้เหมือนยังไม่เคยเห็น แต่จำได้ในหน้าที่เปิดอยู่', () => {
    const key = seenKey('acc-1', 'room-1')
    expect(readSeen(key, broken)).toBeNull()
    expect(() => markSeen(key, '2026-10-08T01:00:00Z', broken)).not.toThrow()
    expect(readSeen(key, broken)).toBe('2026-10-08T01:00:00Z')
    resetSeenMemory() // โหลดหน้าใหม่
    expect(readSeen(key, broken)).toBeNull()
    expect(readSeen(key, null)).toBeNull()
  })
  it('ค่าที่เสียใน storage ถือว่ายังไม่เคยเห็น', () => {
    const s = memoryStorage()
    const key = seenKey('acc-1', 'room-1')
    s.data.set(key, 'ไม่ใช่เวลา')
    expect(readSeen(key, s)).toBeNull()
  })
})
