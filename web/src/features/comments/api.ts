import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ความคิดเห็นส่วนตัวของ (งาน, นักเรียน) — อ่านผ่าน comment_thread (0031) เขียน/ยกเลิกผ่าน post_comment/retract_comment (0027)

const CommentSchema = z.object({
  comment_id: z.uuid(),
  author_role: z.enum(['student', 'teacher', 'admin']),
  author_name: z.string().nullable(),
  mine: z.boolean(),
  body: z.string().nullable(),
  created_at: z.string(),
  retracted_at: z.string().nullable(),
})
export type Comment = z.infer<typeof CommentSchema>

const ThreadSchema = z.object({
  assignment_id: z.uuid(),
  student_id: z.uuid(),
  can_write: z.boolean(),
  comments: z.array(CommentSchema),
})
export type Thread = z.infer<typeof ThreadSchema>

export const threadKey = (assignmentId: string, studentId: string | null) =>
  ['comment-thread', assignmentId, studentId ?? 'me'] as const

/** studentId = null สำหรับนักเรียน (ช่องของตัวเอง) */
export const threadQuery = (assignmentId: string, studentId: string | null) =>
  queryOptions({
    queryKey: threadKey(assignmentId, studentId),
    queryFn: () =>
      run(
        supabase.rpc('comment_thread', {
          p_assignment_id: assignmentId,
          // null = ช่องของผู้เรียก (นักเรียน) — type ที่สร้างอัตโนมัติไม่รู้ว่ารับ null ได้
          p_student_id: studentId as string,
        }),
        ThreadSchema,
      ),
  })

const WrittenSchema = z.object({ comment_id: z.uuid() })

export function postComment(input: {
  assignmentId: string
  studentId: string | null
  body: string
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('post_comment', {
      p_assignment_id: input.assignmentId,
      p_student_id: input.studentId as string,
      p_body: input.body,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    WrittenSchema,
  )
}

export function retractComment(commentId: string, adminMode: boolean) {
  return run(
    supabase.rpc('retract_comment', { p_comment_id: commentId, p_admin_mode: adminMode }),
    WrittenSchema,
  )
}
