import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// งานส่งของนักเรียน (S03/S02/S01) — RPC ของ 0020_submissions/0021_submission_status
// สถานะ "ส่งได้ไหม/ผลถ้าส่งตอนนี้" มาจากฟังก์ชันตัดสินตัวเดียวกับ submit_assignment ฝั่งเซิร์ฟเวอร์ (หน้าเว็บไม่คิดกติกาเอง)

const FileRefSchema = z.object({
  asset_id: z.uuid(),
  file_name: z.string(),
  content_type: z.string(),
  size_bytes: z.number().int(),
})

export const OUTCOMES = [
  'first_on_time',
  'first_late',
  'first_after_solution',
  'resubmit',
  'resubmit_permission',
] as const
export type Outcome = (typeof OUTCOMES)[number]
const OutcomeSchema = z.enum(OUTCOMES)
const TimingSchema = z.enum(['on_time', 'late'])
export type Timing = z.infer<typeof TimingSchema>

const StatusSchema = z.object({
  assignment_id: z.uuid(),
  classroom_id: z.uuid(),
  server_now: z.string(),
  due_at: z.string(),
  close_at: z.string().nullable(),
  intake: z.enum(['open', 'closed', 'after_solution']),
  solution_published: z.boolean(),
  permission_open: z.boolean(),
  outcome: OutcomeSchema.nullable(),
  /** รหัส UX 7.1 ที่ทำให้ส่งไม่ได้ตอนนี้ (term_ended, submission_closed, resubmit_not_allowed …) */
  blocked: z.string().nullable(),
  /** รางวัลของงาน (0036): จำนวนโทเคนของงาน, ได้รับแล้วหรือยัง, ห้องอยู่ในเทอมกระเป๋าปัจจุบัน (false = งานภาคเรียนก่อน) */
  reward_tokens: z.number().int(),
  reward_granted: z.boolean(),
  current_term: z.boolean(),
  submission: z
    .object({
      submission_id: z.uuid(),
      content_revision: z.number().int(),
      first_submitted_at: z.string(),
      last_submitted_at: z.string(),
      first_after_solution: z.boolean(),
      timing: TimingSchema,
      files: z.array(FileRefSchema),
    })
    .nullable(),
})
export type SubmissionStatus = z.infer<typeof StatusSchema>

/** S03: สถานะงานของฉัน — โหลดใหม่ทุกครั้งที่กลับมาที่หน้า (กำหนดส่ง/สิทธิ์แก้เปลี่ยนได้จากฝั่งครู) */
export const submissionStatusQuery = (postId: string) =>
  queryOptions({
    queryKey: ['submission-status', postId],
    queryFn: () =>
      run(supabase.rpc('submission_status', { p_assignment_id: postId }), StatusSchema),
    staleTime: 0,
    retry: false,
  })

const WorkRowSchema = z.object({
  post_id: z.uuid(),
  classroom_id: z.uuid(),
  classroom_name: z.string(),
  title: z.string(),
  due_at: z.string(),
  close_at: z.string().nullable(),
  reward_tokens: z.number().int(),
  submitted: z.boolean(),
  timing: TimingSchema.nullable(),
  last_submitted_at: z.string().nullable(),
  content_revision: z.number().int().nullable(),
  permission_open: z.boolean(),
  outcome: OutcomeSchema.nullable(),
  blocked: z.string().nullable(),
})
export type WorkRow = z.infer<typeof WorkRowSchema>

/** การบ้านพร้อมสถานะส่วนตัว: ห้องเดียว (S02) หรือทุกห้องที่เป็นสมาชิก (S01, classroomId = null) */
export const myWorkQuery = (classroomId: string | null) =>
  queryOptions({
    queryKey: ['my-work', classroomId ?? 'all'],
    queryFn: () =>
      run(
        supabase.rpc('my_work', classroomId ? { p_classroom_id: classroomId } : {}),
        z.array(WorkRowSchema),
      ),
    staleTime: 30_000,
  })

const SubmitResultSchema = z.object({
  submission_id: z.uuid(),
  outcome: OutcomeSchema,
  submitted_at: z.string(),
  first_submitted_at: z.string(),
  last_submitted_at: z.string(),
  timing: TimingSchema,
  first_after_solution: z.boolean(),
  content_revision: z.number().int(),
  used_permission: z.boolean(),
  files: z.array(FileRefSchema),
})
export type SubmitResult = z.infer<typeof SubmitResultSchema>

/** ส่งงาน/ส่งแก้ — files = asset id ตามลำดับ (ไฟล์เดิมที่เก็บ + ไฟล์ใหม่), expectedRevision = รุ่นที่เห็น (0 = ยังไม่ส่ง) */
export function submitAssignment(input: {
  assignmentId: string
  files: string[]
  expectedRevision: number
  requestKey: string
}) {
  return run(
    supabase.rpc('submit_assignment', {
      p_assignment_id: input.assignmentId,
      p_files: input.files,
      p_expected_revision: input.expectedRevision,
      p_request_key: input.requestKey,
    }),
    SubmitResultSchema,
  )
}
