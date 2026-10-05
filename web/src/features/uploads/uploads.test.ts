import { afterEach, describe, expect, it, vi } from 'vitest'
import { th } from '../../copy/th'
import { RequestError } from '../../lib/request'
import { supabase, toAppError } from '../../lib/supabase'
import { completeUpload, PutError, requestBatch, type Batch, type BatchRequest } from './api'
import { downscaleSteps, encodeAttempts, fitWithin, JPEG_QUALITIES, MAX_EDGES } from './image'
import {
  checkOriginal,
  checkPrepared,
  checkSet,
  formatBytes,
  kindOf,
  UPLOAD_LIMITS,
  uploadName,
} from './rules'
import {
  IN_PROGRESS_TRIES,
  IN_PROGRESS_WAIT_MS,
  NETWORK_RETRY_WAIT_MS,
  uploadSet,
  type UploadDeps,
  type UploadEntry,
  type UploadEvent,
} from './uploader'

const MIB = 1024 * 1024
const CLASSROOM = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d'
const BATCH = '0b6d3c1e-6c55-4f4e-9d8b-2f1a3c4d5e6f'
const KEY = '1d2c3b4a-5f6e-4d7c-9b8a-0f1e2d3c4b5a'

describe('ชนิดไฟล์ (J4)', () => {
  it('ใช้ MIME ก่อน แล้วจึงนามสกุล (HEIC จาก Android/Windows มักไม่มี type)', () => {
    expect(kindOf({ name: 'a.jpg', type: 'image/jpeg' })).toBe('jpeg')
    expect(kindOf({ name: 'scan', type: 'application/pdf' })).toBe('pdf')
    expect(kindOf({ name: 'IMG_0001.HEIC', type: '' })).toBe('heic')
    expect(kindOf({ name: 'IMG_0002.heif', type: 'application/octet-stream' })).toBe('heic')
    expect(kindOf({ name: 'photo.png', type: 'image/heic' })).toBe('heic')
    expect(kindOf({ name: 'ภาพ.JPEG', type: '' })).toBe('jpeg')
    expect(kindOf({ name: 'notes.docx', type: 'application/vnd.ms-word' })).toBeNull()
    expect(kindOf({ name: 'anim.gif', type: 'image/gif' })).toBeNull()
  })
})

describe('ตรวจก่อนเริ่มย่อ (J4–J6)', () => {
  const f = (name: string, type: string, size: number) => ({ name, type, size })
  it('รูปต้นฉบับไม่เกิน 20 MB (รวม HEIC) · PDF ไม่เกิน 10 MB', () => {
    expect(checkOriginal(f('a.jpg', 'image/jpeg', 20 * MIB))).toBeNull()
    expect(checkOriginal(f('a.jpg', 'image/jpeg', 20 * MIB + 1))).toBe('file_too_large')
    expect(checkOriginal(f('a.heic', '', 20 * MIB))).toBeNull()
    expect(checkOriginal(f('a.png', 'image/png', 20 * MIB + 1))).toBe('file_too_large')
    expect(checkOriginal(f('a.pdf', 'application/pdf', 10 * MIB))).toBeNull()
    expect(checkOriginal(f('a.pdf', 'application/pdf', 10 * MIB + 1))).toBe('file_too_large')
  })
  it('ชนิดอื่นหรือไฟล์ว่าง → file_type_not_allowed', () => {
    expect(checkOriginal(f('a.gif', 'image/gif', 10))).toBe('file_type_not_allowed')
    expect(checkOriginal(f('a.pdf', 'application/pdf', 0))).toBe('file_type_not_allowed')
  })
  it('หลังเตรียม: รูป ≤ 2 MB · PDF ≤ 10 MB', () => {
    expect(checkPrepared('image/jpeg', 2 * MIB)).toBeNull()
    expect(checkPrepared('image/png', 2 * MIB + 1)).toBe('file_too_large')
    expect(checkPrepared('application/pdf', 10 * MIB)).toBeNull()
  })
  it('ทั้งชุด: ไม่เกิน 10 ไฟล์และรวมไม่เกิน 20 MB', () => {
    expect(checkSet(10, 20 * MIB)).toBeNull()
    expect(checkSet(11, 1)).toBe('too_many_files')
    expect(checkSet(3, 20 * MIB + 1)).toBe('batch_too_large')
  })
  it('ค่าเพดานตรงกับ private.upload_limits() ใน 0016', () => {
    expect(UPLOAD_LIMITS).toMatchObject({
      maxFiles: 10,
      maxImageBytes: 2097152,
      maxPdfBytes: 10485760,
      maxBatchBytes: 20971520,
    })
  })
  it('ข้อความของรหัสตรวจไฟล์มีใน th.errors', () => {
    for (const code of [
      'too_many_files',
      'file_too_large',
      'file_type_not_allowed',
      'batch_too_large',
    ] as const)
      expect(th.errors[code]).toBeTruthy()
  })
})

describe('ชื่อไฟล์ที่ส่ง', () => {
  it('เปลี่ยนนามสกุลตามชนิดหลังแปลง', () => {
    expect(uploadName('IMG_0001.HEIC', 'image/jpeg')).toBe('IMG_0001.jpg')
    expect(uploadName('สแกน.png', 'image/jpeg')).toBe('สแกน.jpg')
    expect(uploadName('ภาพหน้าจอ.png', 'image/png')).toBe('ภาพหน้าจอ.png')
    expect(uploadName('ใบงาน เคมี.pdf', 'application/pdf')).toBe('ใบงาน เคมี.pdf')
    expect(uploadName('photo', 'image/jpeg')).toBe('photo.jpg')
  })
  it('ตัดอักขระควบคุมและ / \\ (0016 ปฏิเสธชื่อแบบนั้น)', () => {
    expect(uploadName('a/b\\c\u0001d\u007f.jpg', 'image/jpeg')).toBe('a b c d.jpg')
    expect(uploadName('  .jpg', 'image/jpeg')).toBe('file.jpg')
  })
  it('ยาวไม่เกิน 255 ตัวรวมนามสกุล (นับตาม code point)', () => {
    const name = uploadName(`${'ก'.repeat(300)}.heic`, 'image/jpeg')
    expect(Array.from(name)).toHaveLength(255)
    expect(name.endsWith('.jpg')).toBe(true)
  })
  it('ขนาดอ่านง่าย', () => {
    expect(formatBytes(500)).toBe('1 KB')
    expect(formatBytes(940 * 1024)).toBe('940 KB')
    expect(formatBytes(1.44 * MIB)).toBe('1.4 MB')
    expect(formatBytes(12.6 * MIB)).toBe('13 MB')
  })
})

describe('วางแผนย่อรูป', () => {
  it('ด้านยาวไม่เกินเป้าหมาย คงสัดส่วน ไม่ขยายรูปเล็ก', () => {
    expect(fitWithin({ width: 4032, height: 3024 }, 2560)).toEqual({ width: 2560, height: 1920 })
    expect(fitWithin({ width: 3024, height: 4032 }, 2560)).toEqual({ width: 1920, height: 2560 })
    expect(fitWithin({ width: 800, height: 600 }, 2560)).toEqual({ width: 800, height: 600 })
  })
  it('ย่อทีละครึ่งจนเหลือไม่เกินสองเท่าของเป้าหมาย แล้วจบที่เป้าหมาย (ไม่สร้าง canvas ขนาดเต็ม)', () => {
    expect(downscaleSteps({ width: 4032, height: 3024 }, { width: 2560, height: 1920 })).toEqual([
      { width: 2560, height: 1920 },
    ])
    expect(downscaleSteps({ width: 8064, height: 6048 }, { width: 1280, height: 960 })).toEqual([
      { width: 4032, height: 3024 },
      { width: 1280, height: 960 },
    ])
    const steps = downscaleSteps({ width: 12000, height: 9000 }, { width: 1024, height: 768 })
    expect(steps.at(-1)).toEqual({ width: 1024, height: 768 })
    expect(steps.every((s) => s.width < 12000)).toBe(true)
  })
  it('ลองทุกคุณภาพของขนาดใหญ่ก่อน แล้วจึงลดขนาด', () => {
    const attempts = encodeAttempts()
    expect(attempts).toHaveLength(MAX_EDGES.length * JPEG_QUALITIES.length)
    expect(attempts[0]).toEqual({ maxEdge: 2560, quality: 0.85 })
    expect(attempts[JPEG_QUALITIES.length]).toEqual({ maxEdge: 2048, quality: 0.85 })
    expect(attempts.at(-1)).toEqual({ maxEdge: 1024, quality: 0.65 })
  })
})

// ---------------------------------------------------------------------------
// ลำดับการอัปโหลด (B2/ฟังก์ชันจำลอง)
// ---------------------------------------------------------------------------
const P0001 = (code: string) => new RequestError(toAppError({ code: 'P0001', message: code }))

function batchFor(req: BatchRequest, version = 1): Batch {
  return {
    batch_id: BATCH,
    expires_at: '2026-10-05T05:00:00Z',
    files: req.files.map((f, i) => ({
      file_name: f.name,
      content_type: f.type,
      size_bytes: f.size,
      upload_url: `https://b2.example/staging/${i + 1}?v=${version}`,
    })),
  }
}

function entry(n: number, extra: Partial<UploadEntry> = {}): UploadEntry {
  return {
    id: `f${n}`,
    blob: new Blob([new Uint8Array(100 * n)]),
    name: `ไฟล์${n}.jpg`,
    type: 'image/jpeg',
    ...extra,
  }
}

function fakeDeps(over: Partial<UploadDeps> = {}) {
  const calls = {
    batch: [] as BatchRequest[],
    put: [] as string[],
    complete: [] as number[],
    sleep: [] as number[],
  }
  let active = 0
  let maxActive = 0
  let version = 0
  const deps: UploadDeps = {
    requestBatch: async (req) => {
      calls.batch.push(req)
      return batchFor(req, ++version)
    },
    put: async (url, blob, _type, onProgress) => {
      calls.put.push(url)
      active++
      maxActive = Math.max(maxActive, active)
      await new Promise((r) => setTimeout(r, 5))
      onProgress(blob.size, blob.size)
      active--
    },
    complete: async (_batchId, item) => {
      calls.complete.push(item)
      return { asset_id: `asset-${item}`, file_name: '', content_type: 'image/jpeg', size_bytes: 1 }
    },
    sleep: async (ms) => {
      calls.sleep.push(ms)
    },
    ...over,
  }
  return { deps, calls, maxActive: () => maxActive }
}

const TARGET = { purpose: 'post' as const, classroomId: CLASSROOM, postId: null, adminMode: false }

async function run(entries: UploadEntry[], deps: UploadDeps, signal?: AbortSignal) {
  const events: UploadEvent[] = []
  await uploadSet(entries, TARGET, KEY, deps, (e) => events.push(e), signal)
  const final = (id: string) => events.filter((e) => e.id === id).at(-1)
  return { events, final }
}

describe('uploadSet', () => {
  afterEach(() => vi.restoreAllMocks())

  it('ขอ batch ครั้งเดียว → PUT ทีละไม่เกิน 2 ไฟล์ → complete ตามลำดับไฟล์ได้ asset_id', async () => {
    const { deps, calls, maxActive } = fakeDeps()
    const { events, final } = await run([entry(1), entry(2), entry(3)], deps)
    expect(calls.batch).toEqual([
      {
        ...TARGET,
        requestKey: KEY,
        files: [
          { name: 'ไฟล์1.jpg', type: 'image/jpeg', size: 100 },
          { name: 'ไฟล์2.jpg', type: 'image/jpeg', size: 200 },
          { name: 'ไฟล์3.jpg', type: 'image/jpeg', size: 300 },
        ],
      },
    ])
    expect(maxActive()).toBe(2)
    expect(calls.complete.sort()).toEqual([1, 2, 3])
    expect(final('f1')).toEqual({ id: 'f1', phase: 'done', assetId: 'asset-1' })
    expect(final('f3')).toEqual({ id: 'f3', phase: 'done', assetId: 'asset-3' })
    // ลำดับเหตุการณ์ของไฟล์หนึ่ง: uploading (0 → เต็ม) → completing → done
    expect(events.filter((e) => e.id === 'f2').map((e) => e.phase)).toEqual([
      'uploading',
      'uploading',
      'completing',
      'done',
    ])
  })

  it('ลิงก์หมดอายุ (403) → ขอ batch ซ้ำด้วย request key เดิมครั้งเดียว แล้ว PUT ด้วยลิงก์ใหม่', async () => {
    const { deps, calls } = fakeDeps()
    const put = deps.put
    // ลิงก์ชุดแรก (v=1) หมดอายุทั้งคู่ — สองไฟล์ได้ 403 พร้อมกัน ต้องขอ batch ใหม่ครั้งเดียว
    deps.put = async (url, ...rest) => {
      if (url.endsWith('v=1')) {
        calls.put.push(url)
        throw new PutError('expired', 403)
      }
      return put(url, ...rest)
    }
    const { final } = await run([entry(1), entry(2)], deps)
    expect(calls.batch).toHaveLength(2)
    expect(calls.batch[1].requestKey).toBe(KEY)
    expect(calls.put.filter((u) => u.endsWith('v=2'))).toHaveLength(2)
    expect(final('f1')).toMatchObject({ phase: 'done' })
    expect(final('f2')).toMatchObject({ phase: 'done' })
  })

  it('ลิงก์ใหม่ก็ยังได้ 403 → ไฟล์นั้นล้มเหลว (ไม่วนขอซ้ำ)', async () => {
    const { deps, calls } = fakeDeps({
      put: async () => {
        throw new PutError('expired', 403)
      },
    })
    const { final } = await run([entry(1)], deps)
    expect(calls.batch).toHaveLength(2)
    expect(final('f1')).toMatchObject({ phase: 'failed', error: { code: 'upload_failed' } })
  })

  it('เน็ตหลุดระหว่าง PUT → รอแล้วลองใหม่ 1 ครั้ง', async () => {
    let fails = 1
    const { deps, calls } = fakeDeps()
    const put = deps.put
    deps.put = async (...args) => {
      if (fails-- > 0) throw new PutError('network')
      return put(...args)
    }
    const { final } = await run([entry(1)], deps)
    expect(calls.sleep).toEqual([NETWORK_RETRY_WAIT_MS])
    expect(final('f1')).toMatchObject({ phase: 'done' })
  })

  it('เน็ตหลุดสองครั้ง → ล้มเหลวพร้อมข้อความสำรอง (กดลองใหม่ได้)', async () => {
    const { deps } = fakeDeps({
      put: async () => {
        throw new PutError('network')
      },
    })
    const { final } = await run([entry(1)], deps)
    expect(final('f1')).toMatchObject({
      phase: 'failed',
      error: { code: 'unknown', ref: 'network' },
    })
  })

  it('B2 ปฏิเสธเพราะเกินเพดาน → download_budget_reached', async () => {
    const { deps } = fakeDeps({
      put: async () => {
        throw new PutError('cap', 403)
      },
    })
    const { final } = await run([entry(1)], deps)
    expect(final('f1')).toMatchObject({
      phase: 'failed',
      error: { code: 'download_budget_reached' },
    })
  })

  it('complete ได้ upload_in_progress → รอ 20 วินาทีแล้วเรียกซ้ำ', async () => {
    let busy = 2
    const { deps, calls } = fakeDeps()
    const complete = deps.complete
    deps.complete = async (batchId, item) => {
      if (busy-- > 0) {
        calls.complete.push(item)
        throw P0001('upload_in_progress')
      }
      return complete(batchId, item)
    }
    const { final } = await run([entry(1)], deps)
    expect(calls.sleep).toEqual([IN_PROGRESS_WAIT_MS, IN_PROGRESS_WAIT_MS])
    expect(calls.complete).toEqual([1, 1, 1])
    expect(final('f1')).toMatchObject({ phase: 'done', assetId: 'asset-1' })
  })

  it(`upload_in_progress ครบ ${IN_PROGRESS_TRIES} ครั้ง → แสดง upload_in_progress ที่แถวไฟล์`, async () => {
    const { deps } = fakeDeps({
      complete: async () => {
        throw P0001('upload_in_progress')
      },
    })
    const { final } = await run([entry(1)], deps)
    expect(final('f1')).toMatchObject({ phase: 'failed', error: { code: 'upload_in_progress' } })
  })

  it('complete ล้มเหลวไฟล์เดียว ไฟล์อื่นในชุดยังสำเร็จ', async () => {
    const { deps } = fakeDeps()
    const complete = deps.complete
    deps.complete = async (batchId, item) => {
      if (item === 2) throw P0001('upload_type_mismatch')
      return complete(batchId, item)
    }
    const { final } = await run([entry(1), entry(2), entry(3)], deps)
    expect(final('f1')).toMatchObject({ phase: 'done' })
    expect(final('f2')).toMatchObject({
      phase: 'failed',
      error: { code: 'upload_type_mismatch', message: th.errors.upload_type_mismatch },
    })
    expect(final('f3')).toMatchObject({ phase: 'done' })
  })

  it('ขอ batch ไม่ได้ (เช่นพื้นที่เต็ม) → ทุกไฟล์ล้มเหลวด้วยรหัสนั้น ไม่ PUT', async () => {
    const { deps, calls } = fakeDeps({
      requestBatch: async () => {
        throw P0001('storage_full')
      },
    })
    const { final } = await run([entry(1), entry(2)], deps)
    expect(calls.put).toHaveLength(0)
    expect(final('f1')).toMatchObject({ phase: 'failed', error: { code: 'storage_full' } })
    expect(final('f2')).toMatchObject({ phase: 'failed', error: { code: 'storage_full' } })
  })

  it('นำไฟล์ออกระหว่างรอคิว → cancelled ไม่ PUT ไม่ complete ไฟล์นั้น', async () => {
    const controller = new AbortController()
    controller.abort()
    const { deps, calls } = fakeDeps()
    const put = deps.put
    deps.put = async (url, blob, type, onProgress, signal) => {
      if (signal?.aborted) throw new PutError('aborted')
      return put(url, blob, type, onProgress, signal)
    }
    const { final } = await run([entry(1), entry(2, { signal: controller.signal })], deps)
    expect(final('f2')).toEqual({ id: 'f2', phase: 'cancelled' })
    expect(calls.complete).toEqual([1])
  })
})

describe('เรียก Edge Function uploads', () => {
  const client = Object.getPrototypeOf(supabase.functions) as typeof supabase.functions
  afterEach(() => vi.restoreAllMocks())

  it('ขอ batch: ส่งชื่อ/ชนิด/ขนาด + request key + admin mode', async () => {
    const req: BatchRequest = {
      ...TARGET,
      files: [{ name: 'โจทย์.jpg', type: 'image/jpeg', size: 900000 }],
      requestKey: KEY,
    }
    const invoke = vi
      .spyOn(client, 'invoke')
      .mockResolvedValue({ data: batchFor(req), error: null, response: undefined })
    await expect(requestBatch(req)).resolves.toMatchObject({ batch_id: BATCH })
    expect(invoke).toHaveBeenCalledWith('uploads', {
      body: {
        purpose: 'post',
        classroom_id: CLASSROOM,
        post_id: null,
        files: [{ file_name: 'โจทย์.jpg', content_type: 'image/jpeg', size_bytes: 900000 }],
        request_key: KEY,
        admin_mode: false,
      },
    })
  })

  it('complete: เส้นทาง uploads/:batch/complete ด้วย { item }', async () => {
    const invoke = vi.spyOn(client, 'invoke').mockResolvedValue({
      data: {
        asset_id: 'a1',
        file_name: 'x.jpg',
        content_type: 'image/jpeg',
        size_bytes: 10,
        status: 'ready',
      },
      error: null,
      response: undefined,
    })
    await expect(completeUpload(BATCH, 2)).resolves.toMatchObject({ asset_id: 'a1' })
    expect(invoke).toHaveBeenCalledWith(`uploads/${BATCH}/complete`, { body: { item: 2 } })
  })
})
