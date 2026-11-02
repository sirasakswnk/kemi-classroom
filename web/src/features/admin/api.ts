import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// D01 บัญชีครู (supabase/migrations/0009_teacher_admin.sql) — เฉพาะ role admin

const AllowlistRowSchema = z.object({
  id: z.uuid(),
  teacher_id: z.uuid(),
  teacher_name: z.string(),
  /** อีเมลปิดบางส่วน */
  email: z.string().nullable(),
  signed_in: z.boolean(),
  created_at: z.string(),
})
export type AllowlistRow = z.infer<typeof AllowlistRowSchema>

const AdminTeachersSchema = z.object({
  admin_email: z.string().nullable(),
  teachers: z.array(z.object({ id: z.uuid(), display_name: z.string() })),
  allowlist: z.array(AllowlistRowSchema),
})
export type AdminTeachers = z.infer<typeof AdminTeachersSchema>

export const adminTeachersQuery = queryOptions({
  queryKey: ['admin-teachers'],
  queryFn: () => run(supabase.rpc('admin_teachers'), AdminTeachersSchema),
})

export function addTeacher(input: { email: string; teacherId: string | null; newName: string }) {
  return run(
    supabase.rpc('admin_add_teacher', {
      p_email: input.email,
      ...(input.teacherId
        ? { p_teacher_id: input.teacherId }
        : { p_new_teacher_name: input.newName }),
    }),
    AllowlistRowSchema.omit({ created_at: true }),
  )
}

export function removeTeacher(allowlistId: string) {
  return run(
    supabase.rpc('admin_remove_teacher', { p_allowlist_id: allowlistId }),
    z.object({ id: z.uuid(), removed: z.boolean(), demoted_accounts: z.number().int() }),
  )
}

// D01 แผงสำรองข้อมูล (P7-03): อ่าน backup_runs ตรง (RLS ให้เฉพาะผู้ดูแล — 0012) เลือกเฉพาะคอลัมน์ที่แผงใช้
const BACKUP_COLUMNS = 'kind, status, started_at, finished_at, dump_name, file_count, detail'
const BackupRunSchema = z.object({
  kind: z.string(),
  status: z.string(),
  started_at: z.string(),
  finished_at: z.string().nullable(),
  dump_name: z.string().nullable(),
  file_count: z.number().int().nullable(),
  detail: z.string().nullable(),
})
const latestRun = (kind: 'backup' | 'restore_test', status?: 'succeeded' | 'failed') => {
  let q = supabase.from('backup_runs').select(BACKUP_COLUMNS).eq('kind', kind)
  q = status ? q.eq('status', status) : q.neq('status', 'running')
  return run(q.order('started_at', { ascending: false }).limit(1), z.array(BackupRunSchema)).then(
    (rows) => rows[0] ?? null,
  )
}

export const adminBackupRunsQuery = queryOptions({
  queryKey: ['admin-backup-runs'],
  queryFn: async () => {
    const [lastSuccess, lastFailure, lastRestoreTest] = await Promise.all([
      latestRun('backup', 'succeeded'),
      latestRun('backup', 'failed'),
      latestRun('restore_test'),
    ])
    return { lastSuccess, lastFailure, lastRestoreTest }
  },
  staleTime: 60_000,
})

// D01 งานเบื้องหลังที่ล้มเหลว + ลองใหม่ (0051_admin_jobs) — ไม่มี payload, error เป็นรหัสย่อ
const FailedJobSchema = z.object({
  id: z.number().int(),
  kind: z.string(),
  attempts: z.number().int(),
  error: z.string().nullable(),
  created_at: z.string(),
  failed_at: z.string(),
})
export type FailedJob = z.infer<typeof FailedJobSchema>

const FailedJobsSchema = z.object({
  failed_total: z.number().int(),
  items: z.array(FailedJobSchema),
})
export type FailedJobs = z.infer<typeof FailedJobsSchema>

export const adminFailedJobsQuery = queryOptions({
  queryKey: ['admin-failed-jobs'],
  queryFn: () => run(supabase.rpc('admin_failed_jobs'), FailedJobsSchema),
  staleTime: 30_000,
})

export const RetryResult = z.enum(['queued', 'not_failed', 'superseded'])
export type RetryResult = z.infer<typeof RetryResult>

/** ลองใหม่: ปลอดภัยเมื่อกดซ้ำ/พร้อมกัน — งานที่ไม่ใช่ failed แล้วได้ not_failed */
export function retryJob(jobId: number) {
  return run(
    supabase.rpc('admin_retry_job', { p_job_id: jobId }),
    z.object({ result: RetryResult, status: z.string().nullable() }),
  )
}
