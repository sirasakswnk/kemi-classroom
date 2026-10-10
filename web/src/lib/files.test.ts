import { FunctionsFetchError, FunctionsHttpError } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { th } from '../copy/th'
import {
  functionError,
  isCapExceeded,
  linkFreshMs,
  loadSignedFile,
  parseSignResponse,
  signedFileKey,
  signFiles,
  type SignedFile,
} from './files'
import { RequestError } from './request'
import { supabase } from './supabase'

const A1 = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
const URL1 = `https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/files/${A1}.pdf?versionId=v1&X-Amz-Signature=abc`
const RESPONSE = {
  mode: 'view',
  expires_at: '2026-10-05T03:14:05.678Z',
  files: [
    {
      asset_id: A1,
      url: URL1,
      file_name: 'ใบงาน.pdf',
      content_type: 'application/pdf',
      size_bytes: 40000,
    },
  ],
}
const FILE: SignedFile = {
  assetId: A1,
  url: URL1,
  fileName: 'ใบงาน.pdf',
  contentType: 'application/pdf',
  sizeBytes: 40000,
  expiresAt: Date.parse('2026-10-05T03:14:05.678Z'),
}
// ข้อความ 403 ของ B2 เมื่อเกินเพดาน (S3 API ตอบ XML ข้อความเดียวกับ Native API)
const CAP_BODY =
  '<?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code><Message>Cannot download file, download bandwidth or transaction (Class B) cap exceeded.</Message></Error>'

const budgetError = expect.objectContaining({
  appError: {
    code: 'download_budget_reached',
    message: th.errors.download_budget_reached,
    action: 'retry_later',
    ref: null,
  },
})

// supabase.functions สร้าง FunctionsClient ใหม่ทุกครั้งที่อ่าน จึง spy ที่ prototype
const functionsClient = Object.getPrototypeOf(supabase.functions) as typeof supabase.functions

afterEach(() => vi.restoreAllMocks())

describe('parseSignResponse', () => {
  it('แปลงผลเป็น SignedFile พร้อมเวลาหมดอายุ', () => {
    expect(parseSignResponse(RESPONSE)).toEqual([FILE])
  })
  it('รูปแบบไม่ตรงคืน null', () => {
    expect(parseSignResponse({ ...RESPONSE, expires_at: 'ไม่ใช่เวลา' })).toBeNull()
    expect(parseSignResponse({ ...RESPONSE, files: [{ asset_id: A1 }] })).toBeNull()
    expect(parseSignResponse(null)).toBeNull()
  })
})

describe('อายุลิงก์ในแคช', () => {
  it('ใช้ลิงก์เดิมจนเหลือ 60 วินาทีก่อนหมดอายุ แล้วจึงขอใหม่', () => {
    const issued = FILE.expiresAt - 600_000
    expect(linkFreshMs(FILE, issued)).toBe(540_000)
    expect(linkFreshMs(FILE, FILE.expiresAt - 60_000)).toBe(0)
    expect(linkFreshMs(FILE, FILE.expiresAt + 1)).toBe(0)
    expect(linkFreshMs(undefined, issued)).toBe(0)
  })
  it('แยกแคชตามคู่ asset + mode', () => {
    expect(signedFileKey(A1, 'view')).toEqual(['signed-file', A1, 'view'])
    expect(signedFileKey(A1, 'view')).not.toEqual(signedFileKey(A1, 'download'))
  })
})

describe('signFiles', () => {
  it('เรียก files/sign ด้วยรายการ id + โหมด แล้วคืนลิงก์', async () => {
    const invoke = vi
      .spyOn(functionsClient, 'invoke')
      .mockResolvedValue({ data: RESPONSE, error: null, response: undefined })
    await expect(signFiles([A1], 'view')).resolves.toEqual([FILE])
    expect(invoke).toHaveBeenCalledWith('files/sign', { body: { asset_ids: [A1], mode: 'view' } })
  })
  it('ครบงบ (503) → RequestError download_budget_reached', async () => {
    const res = new Response(
      JSON.stringify({ code: 'P0001', message: 'download_budget_reached' }),
      {
        status: 503,
      },
    )
    vi.spyOn(functionsClient, 'invoke').mockResolvedValue({
      data: null,
      error: new FunctionsHttpError(res),
      response: res,
    })
    await expect(signFiles([A1], 'download')).rejects.toEqual(budgetError)
  })
  it('ไม่มีสิทธิ์ (403) → forbidden', async () => {
    const res = new Response(JSON.stringify({ code: 'P0001', message: 'forbidden' }), {
      status: 403,
    })
    vi.spyOn(functionsClient, 'invoke').mockResolvedValue({
      data: null,
      error: new FunctionsHttpError(res),
      response: res,
    })
    const error = await signFiles([A1], 'view').catch((e: unknown) => e)
    expect(error).toBeInstanceOf(RequestError)
    expect((error as RequestError).appError.code).toBe('forbidden')
  })
  it('ผลผิดรูปแบบ → ข้อความสำรอง', async () => {
    vi.spyOn(functionsClient, 'invoke').mockResolvedValue({
      data: { files: [] },
      error: null,
      response: undefined,
    })
    const error = await signFiles([A1], 'view').catch((e: unknown) => e)
    expect((error as RequestError).appError).toMatchObject({
      code: 'unknown',
      ref: 'InvalidResponse',
    })
  })
})

describe('functionError', () => {
  it('เนื้อคำตอบไม่ใช่ JSON → ข้อความสำรอง + รหัสอ้างอิงสถานะ HTTP', async () => {
    const err = new FunctionsHttpError(new Response('Bad Gateway', { status: 502 }))
    expect(await functionError(err)).toMatchObject({ code: 'unknown', ref: 'http_502' })
  })
  it('เน็ตหลุด (FunctionsFetchError) → ข้อความสำรอง', async () => {
    const err = new FunctionsFetchError(new TypeError('Failed to fetch'))
    expect(await functionError(err)).toMatchObject({ code: 'unknown', action: 'fallback' })
  })
})

describe('isCapExceeded', () => {
  it('จับ 403 ที่มีข้อความ/รหัส cap exceeded เท่านั้น', () => {
    expect(isCapExceeded(403, CAP_BODY)).toBe(true)
    expect(isCapExceeded(403, '{"code":"download_cap_exceeded"}')).toBe(true)
    expect(isCapExceeded(403, '{"code":"transaction_cap_exceeded"}')).toBe(true)
    expect(
      isCapExceeded(
        403,
        '<Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>',
      ),
    ).toBe(false)
    expect(isCapExceeded(503, CAP_BODY)).toBe(false)
  })
})

describe('loadSignedFile', () => {
  it('โหลดด้วยลิงก์เดิมแล้วคืน Blob', async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response('PDFDATA', { status: 200 }))
    const blob = await loadSignedFile(FILE, fetchImpl)
    expect(await blob.text()).toBe('PDFDATA')
    expect(fetchImpl).toHaveBeenCalledWith(URL1)
  })
  it('B2 ตอบ 403 เกินเพดานรายวัน → download_budget_reached', async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response(CAP_BODY, { status: 403 }))
    await expect(loadSignedFile(FILE, fetchImpl)).rejects.toEqual(budgetError)
  })
  it('403 อื่น (ลิงก์หมดอายุ) → ข้อความสำรอง b2_403', async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response('<Error><Code>AccessDenied</Code></Error>', { status: 403 }))
    const error = await loadSignedFile(FILE, fetchImpl).catch((e: unknown) => e)
    expect((error as RequestError).appError).toMatchObject({ code: 'unknown', ref: 'b2_403' })
  })
  it('เน็ตหลุด → ข้อความสำรอง network', async () => {
    const fetchImpl = vi.fn<typeof fetch>().mockRejectedValue(new TypeError('Failed to fetch'))
    const error = await loadSignedFile(FILE, fetchImpl).catch((e: unknown) => e)
    expect((error as RequestError).appError).toMatchObject({ code: 'unknown', ref: 'network' })
  })
})
