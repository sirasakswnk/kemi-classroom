import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'
import type { AttachmentRef } from '../uploads/AttachmentList'

// ฝั่งครู: ยอดงานส่ง (T08) รายชื่อสถานะ (T03) และไฟล์ของงานส่ง (ตัวดูเบื้องต้น) — 0022_teacher_work + RLS ของ 0020
// อ่านอย่างเดียว: ครูเจ้าของห้อง/ผู้ดูแล (ไม่ต้องโหมดผู้ดูแล)

const IntakeSchema = z.enum(['open', 'closed', 'after_solution'])
export type Intake = z.infer<typeof IntakeSchema>

const SummaryRowSchema = z.object({
  post_id: z.uuid(),
  due_at: z.string(),
  close_at: z.string().nullable(),
  intake: IntakeSchema,
  solution_published: z.boolean(),
  total: z.number().int(),
  submitted: z.number().int(),
  not_submitted: z.number().int(),
  waiting: z.number().int(),
  late: z.number().int(),
})
export type WorkSummary = z.infer<typeof SummaryRowSchema>

/** T08: ยอดต่องานของห้อง */
export const workSummaryQuery = (classroomId: string) =>
  queryOptions({
    queryKey: ['work-summary', classroomId],
    queryFn: () =>
      run(
        supabase.rpc('teacher_work_summary', { p_classroom_id: classroomId }),
        z.array(SummaryRowSchema),
      ),
  })

const StatusRowSchema = z.object({
  student_id: z.uuid(),
  roll_number: z.number().int().nullable(),
  display_name: z.string(),
  member: z.boolean(),
  submission_id: z.uuid().nullable(),
  first_submitted_at: z.string().nullable(),
  last_submitted_at: z.string().nullable(),
  content_revision: z.number().int().nullable(),
  timing: z.enum(['on_time', 'late']).nullable(),
  graded: z.boolean(),
  /** ได้โทเคนของงานนี้แล้ว (0036) */
  reward_granted: z.boolean(),
  file_count: z.number().int(),
})
export type StatusRow = z.infer<typeof StatusRowSchema>

const SubmissionListSchema = z.object({
  assignment_id: z.uuid(),
  classroom_id: z.uuid(),
  server_now: z.string(),
  intake: IntakeSchema,
  solution_published: z.boolean(),
  /** โทเคนของงาน และห้องอยู่ในเทอมกระเป๋าปัจจุบัน (0036) */
  reward_tokens: z.number().int(),
  current_term: z.boolean(),
  rows: z.array(StatusRowSchema),
})
export type SubmissionList = z.infer<typeof SubmissionListSchema>

/** T03: รายชื่อสถานะของงาน เรียงเลขที่ (รวมนักเรียนที่ถูกเอาออกแต่เคยส่ง) */
export const submissionListQuery = (postId: string) =>
  queryOptions({
    queryKey: ['submission-list', postId],
    queryFn: () =>
      run(
        supabase.rpc('teacher_submission_list', { p_assignment_id: postId }),
        SubmissionListSchema,
      ),
    staleTime: 15_000,
  })

const FileRowSchema = z.object({
  position: z.number().int(),
  assets: z
    .object({
      id: z.uuid(),
      file_name: z.string(),
      content_type: z.string(),
      size_bytes: z.number().int(),
    })
    .nullable(),
})

/** ไฟล์ของงานส่ง (RLS: นักเรียนเจ้าของ + ครูเจ้าของห้อง/ผู้ดูแล) ตามลำดับที่นักเรียนแนบ */
export const submissionFilesQuery = (submissionId: string) =>
  queryOptions({
    queryKey: ['submission-files', submissionId],
    queryFn: async (): Promise<AttachmentRef[]> => {
      const rows = await run(
        supabase
          .from('attachments')
          .select('position, assets(id, file_name, content_type, size_bytes)')
          .eq('submission_id', submissionId)
          .order('position'),
        z.array(FileRowSchema),
      )
      return rows.flatMap((r) =>
        r.assets
          ? [
              {
                asset_id: r.assets.id,
                file_name: r.assets.file_name,
                content_type: r.assets.content_type,
                size_bytes: r.assets.size_bytes,
              },
            ]
          : [],
      )
    },
  })
