import { QueryClient } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import { fileBlobKey, signedFileKey, type SignedFile } from '../../lib/files'
import { RequestError } from '../../lib/request'
import { toAppError } from '../../lib/supabase'
import { collectFileBlobs, type CollectDeps } from './collectFileBlobs'

const NOW = Date.parse('2026-10-18T10:00:00Z')
const file = (id: string) => ({
  asset_id: id,
  file_name: `${id}.pdf`,
  content_type: 'application/pdf',
  size_bytes: 10,
})
const link = (id: string, expiresInMs: number): SignedFile => ({
  assetId: id,
  url: `https://b2.example/${id}`,
  fileName: `${id}.pdf`,
  contentType: 'application/pdf',
  sizeBytes: 10,
  expiresAt: NOW + expiresInMs,
})
const blob = (text: string) => new Blob([text])

function deps(over: Partial<CollectDeps> = {}) {
  const sign = vi.fn(async (ids: string[]) => ids.map((id) => link(id, 600_000)))
  const load = vi.fn(async (f: SignedFile) => blob(`ไฟล์ ${f.assetId}`))
  return { sign, load, ...over } as CollectDeps & { sign: typeof sign; load: typeof load }
}

describe('รวบรวมเนื้อไฟล์ตามงบเปิดดู (TECHNICAL_DESIGN 9.3)', () => {
  it('ใช้ Blob ในแคชก่อน → ลิงก์ที่ยังไม่หมดอายุ → ที่เหลือขอลิงก์รวดเดียวแล้วโหลดไฟล์ละครั้ง', async () => {
    const qc = new QueryClient()
    const a = blob('a-cached')
    qc.setQueryData(fileBlobKey('a'), a)
    qc.setQueryData(signedFileKey('b', 'view'), link('b', 300_000))
    // c, d ไม่มีอะไรในแคช; e มีลิงก์แต่ใกล้หมดอายุ (เหลือ 30 วินาที < 60 วินาทีที่เผื่อไว้) → นับเป็นไม่มีลิงก์
    qc.setQueryData(signedFileKey('e', 'view'), link('e', 30_000))
    const d = deps()
    const progress: [number, number][] = []
    const out = await collectFileBlobs(
      qc,
      ['a', 'b', 'c', 'd', 'e'].map(file),
      (done, total) => progress.push([done, total]),
      d,
      NOW,
    )
    expect(out[0]).toBe(a)
    expect(d.sign).toHaveBeenCalledTimes(1)
    expect(d.sign).toHaveBeenCalledWith(['c', 'd', 'e'], 'view')
    // โหลดจาก B2 ไฟล์ละครั้ง เฉพาะที่ไม่มี Blob: b c d e (ไม่โหลด a)
    expect(d.load.mock.calls.map(([f]) => f.assetId)).toEqual(['b', 'c', 'd', 'e'])
    // เก็บเข้าแคชเดียวกับตัวดู — เปิดไฟล์ในตัวดูหรือรวมซ้ำไม่โหลดอีก
    expect(qc.getQueryData(fileBlobKey('c'))).toBeInstanceOf(Blob)
    expect(await out[2].text()).toBe('ไฟล์ c')
    expect(progress[0]).toEqual([1, 5]) // a มีอยู่แล้ว
    expect(progress.at(-1)).toEqual([5, 5])
  })

  it('ทุกไฟล์อยู่ในแคชแล้ว → ไม่ขอลิงก์และไม่โหลดอะไรเลย (ไม่นับงบ)', async () => {
    const qc = new QueryClient()
    qc.setQueryData(fileBlobKey('a'), blob('a'))
    qc.setQueryData(fileBlobKey('b'), blob('b'))
    const d = deps()
    const out = await collectFileBlobs(qc, [file('a'), file('b')], undefined, d, NOW)
    expect(out).toHaveLength(2)
    expect(d.sign).not.toHaveBeenCalled()
    expect(d.load).not.toHaveBeenCalled()
  })

  it('คืนไฟล์ตามลำดับที่ส่งมา แม้บางไฟล์อยู่ในแคชและบางไฟล์ต้องโหลด', async () => {
    const qc = new QueryClient()
    qc.setQueryData(fileBlobKey('z'), blob('z'))
    const out = await collectFileBlobs(
      qc,
      [file('y'), file('z'), file('x')],
      undefined,
      deps(),
      NOW,
    )
    expect(await Promise.all(out.map((b) => b.text()))).toEqual(['ไฟล์ y', 'z', 'ไฟล์ x'])
  })

  it('โหลดไฟล์ใดไม่ได้ (เช่นครบงบ) → ล้มทั้งชุดด้วยข้อผิดพลาดเดิม ไม่คืนครึ่งเดียว และล้างลิงก์ของไฟล์นั้น', async () => {
    const qc = new QueryClient()
    const budget = new RequestError(
      toAppError({ code: 'P0001', message: 'download_budget_reached' }),
    )
    const d = deps({
      load: vi.fn(async (f: SignedFile) => {
        if (f.assetId === 'b') throw budget
        return blob(f.assetId)
      }),
    })
    await expect(
      collectFileBlobs(qc, [file('a'), file('b'), file('c')], undefined, d, NOW),
    ).rejects.toBe(budget)
    expect(qc.getQueryData(signedFileKey('b', 'view'))).toBeUndefined()
    // c ไม่ถูกโหลดต่อหลังล้ม
    expect(d.load).toHaveBeenCalledTimes(2)
  })

  it('เซิร์ฟเวอร์ไม่ส่งลิงก์ของไฟล์ที่ขอ → forbidden', async () => {
    const qc = new QueryClient()
    const d = deps({ sign: vi.fn(async () => []) })
    await expect(collectFileBlobs(qc, [file('a')], undefined, d, NOW)).rejects.toMatchObject({
      appError: { code: 'forbidden' },
    })
  })
})
