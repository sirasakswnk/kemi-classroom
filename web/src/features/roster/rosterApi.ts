import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// T05 รายชื่อ + แก้การผูกบัญชี (supabase/migrations/0008_rebind.sql) + ปรับโทเคน (0036_wallet_ops)
// — ครู หรือผู้ดูแลในโหมดผู้ดูแล

const RosterRowSchema = z.object({
  student_id: z.uuid(),
  display_name: z.string(),
  student_code: z.string(),
  group_name: z.string(),
  roll_number: z.number().int(),
  bound: z.boolean(),
  /** อีเมลปิดบางส่วน */
  account_email: z.string().nullable(),
  classrooms: z.array(z.string()),
  /** ยอดเทอมกระเป๋าปัจจุบัน (ยังไม่มีแถว = 0) และรุ่นยอดที่ส่งกลับตอนปรับ (ยังไม่มีแถว = 0) */
  wallet_balance: z.number().int(),
  wallet_version: z.number().int(),
})
export type RosterRow = z.infer<typeof RosterRowSchema>

export const rosterOverviewQuery = (adminMode: boolean) =>
  queryOptions({
    queryKey: ['roster-overview', adminMode],
    queryFn: () =>
      run(supabase.rpc('roster_overview', { p_admin_mode: adminMode }), z.array(RosterRowSchema)),
  })

const PreviewSchema = z.object({
  student_id: z.uuid(),
  display_name: z.string(),
  old_email: z.string().nullable(),
  new_email: z.string(),
})
export type RebindPreview = z.infer<typeof PreviewSchema>

export function rebindPreview(studentId: string, email: string, adminMode: boolean) {
  return run(
    supabase.rpc('rebind_preview', {
      p_student_id: studentId,
      p_email: email,
      p_admin_mode: adminMode,
    }),
    PreviewSchema,
  )
}

const ChangedSchema = z.object({
  student_id: z.uuid(),
  display_name: z.string(),
  old_email: z.string().nullable(),
  revoked_sessions: z.number().int(),
  changed: z.boolean(),
})

export function rebindStudent(studentId: string, email: string, adminMode: boolean) {
  return run(
    supabase.rpc('rebind_student', {
      p_student_id: studentId,
      p_email: email,
      p_admin_mode: adminMode,
    }),
    ChangedSchema.extend({ new_email: z.string() }),
  )
}

export function unbindStudent(studentId: string, adminMode: boolean) {
  return run(
    supabase.rpc('unbind_student', { p_student_id: studentId, p_admin_mode: adminMode }),
    ChangedSchema,
  )
}

const WalletSchema = z.object({
  student_id: z.uuid(),
  term_id: z.uuid(),
  balance: z.number().int(),
  version: z.number().int(),
})

/** ปรับยอดมือ: รุ่นยอดไม่ตรง → stale_revision, ผลติดลบ → insufficient_balance */
export function walletAdjust(input: {
  studentId: string
  delta: number
  expectedVersion: number
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('wallet_adjust', {
      p_student_id: input.studentId,
      p_delta: input.delta,
      p_expected_version: input.expectedVersion,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    WalletSchema,
  )
}

export type RosterFilter = 'all' | 'unbound' | 'notjoined'

export function filterRoster(rows: RosterRow[], group: string, filter: RosterFilter): RosterRow[] {
  return rows.filter(
    (r) =>
      (!group || r.group_name === group) &&
      (filter === 'all' ||
        (filter === 'unbound' && !r.bound) ||
        (filter === 'notjoined' && r.classrooms.length === 0)),
  )
}
