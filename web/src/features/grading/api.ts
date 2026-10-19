import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ผลตรวจของงานส่ง (0025_grading/0026): อ่านตาราง grades ผ่าน RLS (นักเรียนเจ้าของ + ครูเจ้าของห้อง/ผู้ดูแล)
// บันทึกผ่าน RPC grade_submission เท่านั้น

const GradeSchema = z.object({
  submission_id: z.uuid(),
  raw_score: z.number().int().nullable(),
  passed: z.boolean(),
  penalty_override_pct: z.number().int().nullable(),
  timing: z.enum(['on_time', 'late']),
  applied_penalty_pct: z.number().int(),
  net_score: z.number().int().nullable(),
  graded_revision: z.number().int(),
  graded_at: z.string(),
  version: z.number().int(),
})
export type Grade = z.infer<typeof GradeSchema>

const GRADE_SELECT =
  'submission_id, raw_score, passed, penalty_override_pct, timing, applied_penalty_pct, net_score, graded_revision, graded_at, version'

export const gradeKey = (submissionId: string) => ['grade', submissionId] as const

/** ผลตรวจล่าสุดของงานส่ง — null = ยังไม่เคยตรวจ */
export const gradeQuery = (submissionId: string) =>
  queryOptions({
    queryKey: gradeKey(submissionId),
    queryFn: () =>
      run(
        supabase
          .from('grades')
          .select(GRADE_SELECT)
          .eq('submission_id', submissionId)
          .maybeSingle(),
        GradeSchema.nullable(),
      ),
  })

const SavedGradeSchema = GradeSchema.extend({ full_score_locked: z.boolean() })

export function gradeSubmission(input: {
  submissionId: string
  raw: number | null
  pass: boolean
  overridePct: number | null
  reason: string | null
  seenRevision: number
  expectedVersion: number
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('grade_submission', {
      p_submission_id: input.submissionId,
      // null = บันทึกเฉพาะผ่าน/ไม่ผ่าน (type ที่สร้างอัตโนมัติไม่รู้ว่ารับ null ได้)
      p_raw: input.raw as number,
      p_pass: input.pass,
      p_override_pct: input.overridePct as number,
      p_reason: input.reason as string,
      p_seen_revision: input.seenRevision,
      p_expected_version: input.expectedVersion,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    SavedGradeSchema,
  )
}
