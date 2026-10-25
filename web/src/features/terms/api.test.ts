import { FunctionsHttpError } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { th } from '../../copy/th'
import { RequestError } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { exportFilesPage, type ExportPage } from './api'

const TERM = '7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f'
const A1 = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'
const PAGE: ExportPage = {
  term_id: TERM,
  fingerprint: 'f'.repeat(32),
  total_count: 1,
  total_bytes: 40000,
  next_after: null,
  expires_at: '2026-10-25T03:14:05.678Z',
  files: [
    {
      asset_id: A1,
      url: `https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/files/${A1}.pdf?versionId=v1`,
      file_name: 'ใบงาน.pdf',
      content_type: 'application/pdf',
      size_bytes: 40000,
      purpose: 'post',
      position: 1,
      classroom_id: '3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a',
      classroom_name: 'เคมี 5/4',
      post_id: '4e5f6a7b-8c9d-4e0f-9a1b-2c3d4e5f6a7b',
      post_kind: 'assignment',
      post_title: 'สมดุลเคมี',
      student: null,
    },
  ],
}

// supabase.functions สร้าง FunctionsClient ใหม่ทุกครั้งที่อ่าน จึง spy ที่ prototype
const functionsClient = Object.getPrototypeOf(supabase.functions) as typeof supabase.functions

afterEach(() => vi.restoreAllMocks())

const httpError = (message: string, status: number) => {
  const res = new Response(JSON.stringify({ code: 'P0001', message }), { status })
  return { data: null, error: new FunctionsHttpError(res), response: res }
}

describe('exportFilesPage', () => {
  it('เรียก files/exports ด้วยภาคเรียน + ตำแหน่งต่อ แล้วคืนหน้า', async () => {
    const invoke = vi
      .spyOn(functionsClient, 'invoke')
      .mockResolvedValue({ data: PAGE, error: null, response: undefined })
    await expect(exportFilesPage(TERM, A1, true)).resolves.toEqual(PAGE)
    expect(invoke).toHaveBeenCalledWith('files/exports', {
      body: { term_id: TERM, after: A1, admin_mode: true },
    })
    await exportFilesPage(TERM, null, false, 5)
    expect(invoke).toHaveBeenLastCalledWith('files/exports', {
      body: { term_id: TERM, after: null, admin_mode: false, limit: 5 },
    })
  })

  it('งบวันนี้ไม่พอ (503) → export_budget_reached ให้ต่อจากที่ค้างหลัง 07:00 น.', async () => {
    vi.spyOn(functionsClient, 'invoke').mockResolvedValue(httpError('export_budget_reached', 503))
    const error = await exportFilesPage(TERM, A1, false).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(RequestError)
    expect((error as RequestError).appError).toEqual({
      code: 'export_budget_reached',
      message: th.errors.export_budget_reached,
      action: 'retry_later',
      ref: null,
    })
  })

  it('ชุดไฟล์เปลี่ยนระหว่างทาง (409) → export_mismatch · ผลผิดรูปแบบ → unknown', async () => {
    vi.spyOn(functionsClient, 'invoke').mockResolvedValueOnce(httpError('export_mismatch', 409))
    await expect(exportFilesPage(TERM, null, false)).rejects.toMatchObject({
      appError: { code: 'export_mismatch' },
    })
    vi.spyOn(functionsClient, 'invoke').mockResolvedValueOnce({
      data: { ...PAGE, files: [{ ...PAGE.files[0], url: 'ไม่ใช่ลิงก์' }] },
      error: null,
      response: undefined,
    })
    await expect(exportFilesPage(TERM, null, false)).rejects.toMatchObject({
      appError: { code: 'unknown', ref: 'InvalidResponse' },
    })
  })
})
