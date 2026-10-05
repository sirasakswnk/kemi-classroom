import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'
import type { AttachmentRef } from '../uploads/AttachmentList'
import type { EditablePost, PostPayload, UpdatePayload } from './postForm'

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

// ไฟล์โจทย์/ไฟล์แนบ (0019_post_files) — RLS: attachments ตามสิทธิ์อ่านโพสต์, assets เปิดเฉพาะชื่อ/ชนิด/ขนาด
const AttachmentRowSchema = z.object({
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
const ATTACHMENTS_SELECT = 'attachments(position, assets(id, file_name, content_type, size_bytes))'

function filesOf(rows: z.infer<typeof AttachmentRowSchema>[]): AttachmentRef[] {
  return [...rows]
    .sort((a, b) => a.position - b.position)
    .flatMap((r) =>
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
}

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
    attachments: z.array(AttachmentRowSchema),
  })
  .transform(({ assignments, attachments, ...post }) => ({
    ...post,
    assignment: assignments,
    files: filesOf(attachments),
  }))

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
            `id, kind, title, body, published_at, content_updated_at, assignments(full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution), ${ATTACHMENTS_SELECT}`,
          )
          .eq('classroom_id', classroomId)
          .order('published_at', { ascending: false })
          .order('position', { referencedTable: 'attachments' }),
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

// ---------- โหมดแก้ไข (N2) ----------
const EditableRowSchema = z
  .object({
    id: z.uuid(),
    classroom_id: z.uuid(),
    kind: z.enum(['homework', 'announcement']),
    title: z.string(),
    body: z.string().nullable(),
    version: z.number().int(),
    published_at: z.string(),
    content_updated_at: z.string().nullable(),
    assignments: AssignmentSchema.extend({
      reward_locked_at: z.string().nullable(),
      full_score_locked_at: z.string().nullable(),
      // solutions.assignment_id เป็นทั้ง PK และ FK → วัตถุเดียวหรือ null (RLS: ครูเห็นเฉลยทุกสถานะ)
      solutions: z.object({ published_at: z.string().nullable() }).nullable(),
    }).nullable(),
    attachments: z.array(AttachmentRowSchema),
  })
  .transform(({ assignments, attachments, ...post }): EditablePost => ({
    ...post,
    files: filesOf(attachments),
    assignment: assignments && {
      full_score: assignments.full_score,
      late_penalty_pct: assignments.late_penalty_pct,
      reward_tokens: assignments.reward_tokens,
      due_at: assignments.due_at,
      close_at: assignments.close_at,
      accept_after_solution: assignments.accept_after_solution,
      reward_locked_at: assignments.reward_locked_at,
      full_score_locked_at: assignments.full_score_locked_at,
      solution_published: !!assignments.solutions?.published_at,
    },
  }))

/** โพสต์สำหรับ T02 โหมดแก้ไข พร้อมสถานะล็อก — null = ไม่มี หรือไม่มีสิทธิ์เห็น (RLS) */
export const editablePostQuery = (postId: string) =>
  queryOptions({
    queryKey: ['post-edit', postId],
    queryFn: () =>
      run(
        supabase
          .from('posts')
          .select(
            `id, classroom_id, kind, title, body, version, published_at, content_updated_at, assignments(full_score, late_penalty_pct, reward_tokens, due_at, close_at, accept_after_solution, reward_locked_at, full_score_locked_at, solutions(published_at)), ${ATTACHMENTS_SELECT}`,
          )
          .eq('id', postId)
          .maybeSingle(),
        EditableRowSchema.nullable(),
      ),
  })

const UpdatedPostSchema = z.object({
  post_id: z.uuid(),
  classroom_id: z.uuid(),
  kind: z.enum(['homework', 'announcement']),
  title: z.string(),
  version: z.number().int(),
  changed: z.boolean(),
})

export function updatePost(input: {
  postId: string
  payload: UpdatePayload
  expectedVersion: number
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('update_post', {
      p_post_id: input.postId,
      p_post: input.payload,
      p_expected_version: input.expectedVersion,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    UpdatedPostSchema,
  )
}
