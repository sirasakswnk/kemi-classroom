import { th } from '../../copy/th'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import type { FailedJob } from './api'

// แถวงานที่ล้มเหลวใน D01 (P6-04c): ชนิดงานเป็นภาษาไทย เวลาที่ล้มล่าสุด จำนวนครั้ง และ error ย่อ (ไม่มี payload)
export interface FailedJobRow {
  id: number
  kind: string
  meta: string
  error: string
}

export function failedJobRow(job: FailedJob, now: Date = new Date()): FailedJobRow {
  const copy = th.admin.jobs
  const kinds: Record<string, string> = copy.kinds
  return {
    id: job.id,
    kind: kinds[job.kind] ?? copy.otherKind(job.kind),
    meta: copy.meta(`${thaiDate(job.failed_at, now)} ${thaiTime(job.failed_at)} น.`, job.attempts),
    error: job.error ?? copy.noError,
  }
}
