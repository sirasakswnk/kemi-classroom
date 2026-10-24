import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import type { FailedJob } from './api'
import { failedJobRow } from './failedJobs'

const NOW = new Date('2026-10-25T08:00:00Z')
const job = (over: Partial<FailedJob>): FailedJob => ({
  id: 7,
  kind: 'delete_asset',
  attempts: 6,
  error: 'b2_500',
  created_at: '2026-10-24T01:00:00Z',
  failed_at: '2026-10-25T02:30:00Z',
  ...over,
})

describe('D01 งานเบื้องหลังที่ล้มเหลว (P6-04c)', () => {
  it('ชนิดงานเป็นภาษาไทย + เวลาที่ล้มล่าสุด (เวลาไทย) + จำนวนครั้ง + error ย่อ', () => {
    expect(failedJobRow(job({}), NOW)).toEqual({
      id: 7,
      kind: th.admin.jobs.kinds.delete_asset,
      meta: th.admin.jobs.meta('25 ต.ค. 09:30 น.', 6),
      error: 'b2_500',
    })
    expect(failedJobRow(job({ kind: 'due_reminder' }), NOW).kind).toBe('เตือนใกล้กำหนดส่ง')
    expect(failedJobRow(job({ kind: 'storage_reconcile' }), NOW).kind).toBe('เทียบยอดพื้นที่ B2')
  })

  it('ชนิดที่ไม่รู้จักแสดงรหัส · ไม่มี error → ข้อความแทน', () => {
    const row = failedJobRow(job({ kind: 'mystery', error: null }), NOW)
    expect(row.kind).toBe(th.admin.jobs.otherKind('mystery'))
    expect(row.error).toBe(th.admin.jobs.noError)
  })
})
