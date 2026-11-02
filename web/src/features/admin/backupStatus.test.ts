import { describe, expect, it } from 'vitest'
import { backupStatus, failedStep, stampTime, type BackupRun } from './backupStatus'

const NOW = new Date('2026-11-02T16:00:00Z') // 23:00 น.
const run = (over: Partial<BackupRun>): BackupRun => ({
  kind: 'backup',
  status: 'succeeded',
  started_at: '2026-11-02T07:30:00Z',
  finished_at: '2026-11-02T07:32:00Z',
  dump_name: '20261102T073005Z',
  file_count: 31,
  detail: null,
  ...over,
})
const none = { lastSuccess: null, lastFailure: null, lastRestoreTest: null }

describe('D01 แผงสำรองข้อมูล (P7-03)', () => {
  it('สำรองสำเร็จล่าสุด: เวลาไทย อายุเป็นชั่วโมง จำนวนไฟล์', () => {
    const s = backupStatus({ ...none, lastSuccess: run({}) }, NOW)
    expect(s.success).toEqual({
      when: '2 พ.ย. 14:32 น.',
      age: '8 ชม. ที่แล้ว',
      files: 'ไฟล์ครบ 31 ไฟล์',
    })
    expect(s.backupStale).toBe(false)
  })

  it('เตือนเมื่อเก่ากว่า 18 ชม. (ไม่รวม 18 พอดี) หรือยังไม่เคยสำเร็จ', () => {
    const at18 = run({ finished_at: '2026-11-01T22:00:00Z' })
    expect(backupStatus({ ...none, lastSuccess: at18 }, NOW).backupStale).toBe(false)
    const over = run({ finished_at: '2026-11-01T21:59:00Z' })
    expect(backupStatus({ ...none, lastSuccess: over }, NOW).backupStale).toBe(true)
    expect(backupStatus(none, NOW).backupStale).toBe(true)
    expect(backupStatus(none, NOW).success).toBeNull()
  })

  it('อายุน้อยกว่า 1 ชม.', () => {
    const fresh = run({ finished_at: '2026-11-02T15:30:00Z' })
    expect(backupStatus({ ...none, lastSuccess: fresh }, NOW).success?.age).toBe('ไม่ถึง 1 ชม.')
  })

  it('รอบที่ล้มล่าสุด: ชื่อขั้นจาก detail และบอกว่าล้มหลังรอบสำเร็จหรือไม่', () => {
    const failure = run({
      status: 'failed',
      started_at: '2026-11-02T12:00:00Z',
      finished_at: '2026-11-02T12:03:00Z',
      detail: 'ล้มที่ขั้น repair',
    })
    const s = backupStatus({ ...none, lastSuccess: run({}), lastFailure: failure }, NOW)
    expect(s.failure).toEqual({ when: '2 พ.ย. 19:03 น.', step: 'repair', afterSuccess: true })
    const old = run({
      status: 'failed',
      started_at: '2026-10-30T00:00:00Z',
      finished_at: '2026-10-30T00:32:00Z',
      detail: null,
    })
    expect(backupStatus({ ...none, lastSuccess: run({}), lastFailure: old }, NOW).failure).toEqual({
      when: '30 ต.ค. 07:32 น.',
      step: null,
      afterSuccess: false,
    })
  })

  it('ทดสอบกู้คืนล่าสุด: ผ่าน/ไม่ผ่าน จุดกู้คืนเป็นเวลา จำนวนไฟล์', () => {
    const test = run({
      kind: 'restore_test',
      started_at: '2026-10-20T03:00:00Z',
      finished_at: '2026-10-20T03:00:00Z',
      dump_name: '20261019T193012Z',
      file_count: 50,
    })
    const s = backupStatus({ ...none, lastRestoreTest: test }, NOW)
    expect(s.restore).toEqual({
      passed: true,
      point: '20 ต.ค. 02:30 น.',
      files: 50,
      when: '20 ต.ค. 10:00 น.',
    })
    expect(s.restoreStale).toBe(false)
    const failed = backupStatus(
      { ...none, lastRestoreTest: { ...test, status: 'failed', dump_name: null, file_count: 0 } },
      NOW,
    )
    expect(failed.restore).toMatchObject({ passed: false, point: null, files: 0 })
  })

  it('เตือนทดสอบกู้คืนเมื่อเก่ากว่า 35 วันหรือยังไม่เคย', () => {
    const at = (iso: string) =>
      backupStatus(
        { ...none, lastRestoreTest: run({ kind: 'restore_test', finished_at: iso }) },
        NOW,
      )
    expect(at('2026-09-28T16:00:00Z').restoreStale).toBe(false) // 35 วันพอดี
    expect(at('2026-09-28T15:00:00Z').restoreStale).toBe(true)
    expect(backupStatus(none, NOW).restoreStale).toBe(true)
  })

  it('ไม่แสดงค่าที่ไม่ใช่รูปแบบของสคริปต์ (path, remote, ข้อความอื่น)', () => {
    expect(stampTime('runs/20261019T193012Z')).toBeNull()
    expect(stampTime('gdrive:kemi-backup-prod')).toBeNull()
    expect(stampTime(null)).toBeNull()
    expect(failedStep('ไฟล์ files/abc.pdf ไม่ครบ')).toBeNull()
    expect(failedStep('ล้มที่ขั้น copy_new (exit 1)')).toBe('copy_new')
  })
})
