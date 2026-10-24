import { describe, expect, it } from 'vitest'
import type { SignedFile } from '../../lib/files'
import { loadCharmImages, SIGN_CHUNK, type CharmImageDeps } from './charmImages'

// ที่เก็บจำลอง: Cache Storage เป็น Map, ขอลิงก์/โหลด B2 นับจำนวนครั้ง
function fakeDeps(opts: { signFails?: boolean; fetchFails?: string[] } = {}) {
  const cache = new Map<string, Blob>()
  const signed: string[][] = []
  const fetched: string[] = []
  const deps: CharmImageDeps = {
    cacheGet: async (id) => cache.get(id) ?? null,
    cachePut: async (id, blob) => void cache.set(id, blob),
    sign: async (ids) => {
      signed.push(ids)
      if (opts.signFails) throw new Error('download_budget_reached')
      return ids.map((id): SignedFile => ({
        assetId: id,
        url: `https://b2.example/${id}`,
        fileName: 'charm.png',
        contentType: 'image/png',
        sizeBytes: 10,
        expiresAt: 0,
      }))
    },
    fetchBlob: async (file) => {
      fetched.push(file.assetId)
      if (opts.fetchFails?.includes(file.assetId)) throw new Error('b2_403')
      return new Blob([file.assetId], { type: 'image/png' })
    },
  }
  return { deps, cache, signed, fetched }
}

describe('รูปเครื่องราง (TECHNICAL_DESIGN 9.3 ข้อ 4.1)', () => {
  it('ครั้งแรกขอลิงก์รวมครั้งเดียวสำหรับทุกรูปในหน้าจอ แล้วเก็บลงแคช', async () => {
    const f = fakeDeps()
    const got = await loadCharmImages(['a', 'b', 'a', ''], f.deps)
    expect([...got.keys()].sort()).toEqual(['a', 'b'])
    expect(f.signed).toEqual([['a', 'b']])
    expect(f.fetched.sort()).toEqual(['a', 'b'])
    expect([...f.cache.keys()].sort()).toEqual(['a', 'b'])
  })

  it('ครั้งที่สองใช้แคช: ไม่ขอลิงก์และไม่โหลดจาก B2 ซ้ำ', async () => {
    const f = fakeDeps()
    await loadCharmImages(['a', 'b'], f.deps)
    f.signed.length = 0
    f.fetched.length = 0
    const got = await loadCharmImages(['b', 'a'], f.deps)
    expect(got.size).toBe(2)
    expect(f.signed).toEqual([])
    expect(f.fetched).toEqual([])
  })

  it('เปลี่ยนรูปแล้วได้ id ใหม่ → โหลดเฉพาะรูปใหม่', async () => {
    const f = fakeDeps()
    await loadCharmImages(['old', 'b'], f.deps)
    f.signed.length = 0
    f.fetched.length = 0
    const got = await loadCharmImages(['new', 'b'], f.deps)
    expect(got.has('new')).toBe(true)
    expect(f.signed).toEqual([['new']])
    expect(f.fetched).toEqual(['new'])
  })

  it('ขอลิงก์ล้ม (เช่นเกินงบ) → ไม่มีรูป ใช้เหรียญวาด และไม่โยนข้อผิดพลาด', async () => {
    const f = fakeDeps({ signFails: true })
    const got = await loadCharmImages(['a', 'b'], f.deps)
    expect(got.size).toBe(0)
    expect(f.fetched).toEqual([])
    expect(f.cache.size).toBe(0)
  })

  it('โหลดบางรูปไม่สำเร็จ → รูปอื่นยังแสดง รูปที่ล้มไม่ลงแคช (ครั้งหน้าลองใหม่)', async () => {
    const f = fakeDeps({ fetchFails: ['b'] })
    const got = await loadCharmImages(['a', 'b'], f.deps)
    expect([...got.keys()]).toEqual(['a'])
    expect(f.cache.has('b')).toBe(false)
  })

  it('เกิน 20 id → แบ่งขอลิงก์เป็นชุดละไม่เกิน 20', async () => {
    const f = fakeDeps()
    const ids = Array.from({ length: SIGN_CHUNK + 3 }, (_, i) => `id${i}`)
    const got = await loadCharmImages(ids, f.deps)
    expect(got.size).toBe(ids.length)
    expect(f.signed.map((s) => s.length)).toEqual([SIGN_CHUNK, 3])
  })
})
