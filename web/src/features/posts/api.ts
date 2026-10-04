import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'
import type { PostPayload } from './postForm'

// โพสต์ของห้อง (T08/S02) อ่านตาราง posts + assignments ผ่าน RLS (0010_posts): ครูเจ้าของห้อง/ผู้ดูแล หรือสมาชิกขณะนี้
// สร้างผ่าน RPC create_post (0014_post_rpcs) เท่านั้น

const AssignmentSchema = z.object({
  full_score: z.number().int(),
  late_penalty_pct: z.number().int(),
  reward_tokens: z.number().int(),
  due_at: z.string(),
  close_at: z.string().nullable(),
  accept_after_solution: z.boolean(),
})

export type Assignment = z.infer<typeof AssignmentSchema>

const PostRowSchema = z
  .object({
    id: z.uuid(),
    kind: z.enum(['homework', 'announcement']),
    title: z.string(),
    body: z.string().nullable(),
    published_at: z.string(),
    content_updated_at: z.string().nullable(),
    // assignments.post_id เป็นทั้ง PK และ FK → PostgREST คืนเป็นวัตถุเดียว (หรือ null สำหรับประกาศ)
    assignments: AssignmentSchema.nullable(),
  })
  .transform(({ assignments, ...post }) => ({ ...post, assignment: assignments }))

export type Post = z.infer<typeof PostRowSchema>

/** โพสต์ทั้งหมดของห้อง เรียงจากโพสต์ล่าสุด (RLS ไม่คืนแถวถ้าไม่ใช่สมาชิก/ครูของห้อง) */
export const postsQuery = (classroomId: string) =>
  queryOptions({
    queryKey: ['posts', classroomId],
    queryFn: () =>
      run(
        supabase
          .from('posts')
          .select(
            'id, kind, title, body, published_at, content_updated_at, assignments(full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution)',
          )
          .eq('classroom_id', classroomId)
          .order('published_at', { ascending: false }),
        z.array(PostRowSchema),
      ),
  })

const CreatedPostSchema = z.object({
  post_id: z.uuid(),
  classroom_id: z.uuid(),
  kind: z.enum(['homework', 'announcement']),
  title: z.string(),
})

export function createPost(input: {
  classroomId: string
  payload: PostPayload
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('create_post', {
      p_classroom_id: input.classroomId,
      p_post: input.payload,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    CreatedPostSchema,
  )
}
