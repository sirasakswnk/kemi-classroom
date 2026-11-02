import { th } from '../../copy/th'
import { thaiDate, thaiTime } from '../../lib/thaiTime'

// D01 แผงสำรองข้อมูล (P7-03): สรุปจาก backup_runs ที่ผู้ดูแลอ่านได้ (RLS 0012)
// ไม่แสดงชื่อ remote / path ใน Drive / key ไฟล์ / URL ping — dump_name แสดงเป็นเวลาของจุดกู้คืนเท่านั้น
// และ detail ของรอบที่ล้มแสดงเฉพาะชื่อขั้นที่สคริปต์เขียน (“ล้มที่ขั้น <ชื่อ>”)

/** สำรองวันละ 2 รอบ (ห่าง 12 ชม.) + grace 6 ชม. ตาม Healthchecks */
export const BACKUP_STALE_HOURS = 18
/** check kemi-restore-test รอบ 35 วัน */
export const RESTORE_STALE_DAYS = 35

export interface BackupRun {
  kind: string
  status: string
  started_at: string
  finished_at: string | null
  dump_name: string | null
  file_count: number | null
  detail: string | null
}

export interface BackupStatusInput {
  lastSuccess: BackupRun | null
  lastFailure: BackupRun | null
  lastRestoreTest: BackupRun | null
}

export interface BackupStatus {
  success: { when: string; age: string; files: string | null } | null
  backupStale: boolean
  failure: { when: string; step: string | null; afterSuccess: boolean } | null
  restore: { passed: boolean; point: string | null; files: number; when: string } | null
  restoreStale: boolean
}

const HOUR = 3_600_000

/** ชื่อรอบ YYYYMMDDTHHMMSSZ → เวลา (ค่ารูปแบบอื่นไม่แสดง) */
export function stampTime(stamp: string | null): Date | null {
  const m = stamp?.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/)
  if (!m) return null
  const t = new Date(`${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}Z`)
  return Number.isNaN(t.getTime()) ? null : t
}

/** ชื่อขั้นจาก detail ของรอบที่ล้ม — ข้อความอื่นไม่แสดง */
export function failedStep(detail: string | null): string | null {
  return detail?.match(/^ล้มที่ขั้น ([a-z_]+)/)?.[1] ?? null
}

const at = (when: string | Date, now: Date) => `${thaiDate(when, now)} ${thaiTime(when)} น.`
const endOf = (run: BackupRun) => run.finished_at ?? run.started_at

export function backupStatus(input: BackupStatusInput, now: Date = new Date()): BackupStatus {
  const copy = th.admin.backup
  const { lastSuccess, lastFailure, lastRestoreTest } = input

  const successEnd = lastSuccess ? new Date(endOf(lastSuccess)) : null
  const ageHours = successEnd ? Math.max(0, now.getTime() - successEnd.getTime()) / HOUR : null

  const restoreEnd = lastRestoreTest ? new Date(endOf(lastRestoreTest)) : null
  const restoreAgeDays = restoreEnd ? (now.getTime() - restoreEnd.getTime()) / (24 * HOUR) : null
  const point = stampTime(lastRestoreTest?.dump_name ?? null)

  return {
    success:
      lastSuccess && successEnd && ageHours !== null
        ? {
            when: at(successEnd, now),
            age: copy.age(Math.floor(ageHours)),
            files: lastSuccess.file_count === null ? null : copy.files(lastSuccess.file_count),
          }
        : null,
    backupStale: ageHours === null || ageHours > BACKUP_STALE_HOURS,
    failure: lastFailure
      ? {
          when: at(endOf(lastFailure), now),
          step: failedStep(lastFailure.detail),
          afterSuccess: !successEnd || new Date(lastFailure.started_at) > successEnd,
        }
      : null,
    restore: lastRestoreTest
      ? {
          passed: lastRestoreTest.status === 'succeeded',
          point: point ? at(point, now) : null,
          files: lastRestoreTest.file_count ?? 0,
          when: at(endOf(lastRestoreTest), now),
        }
      : null,
    restoreStale: restoreAgeDays === null || restoreAgeDays > RESTORE_STALE_DAYS,
  }
}
