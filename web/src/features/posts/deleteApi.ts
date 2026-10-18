import { queryOptions, type QueryClient } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ลบการบ้าน/ประกาศ (N4, 0033_delete_post): ยอดที่จะถูกลบจาก post_delete_preview แล้วส่งยอดเดิมไปกับ delete_post
// เซิร์ฟเวอร์ตรวจซ้ำหลังล็อก — ไม่ตรง → preview_changed (หน้าต่างโหลดยอดใหม่ ครูยืนยันอีกครั้ง)

const CountsSchema = z.object({
  submissions: z.number().int(),
  grades: z.number().int(),
  comments: z.number().int(),
  files: z.number().int(),
})
export type DeleteCounts = z.infer<typeof CountsSchema>

const PreviewSchema = CountsSchema.extend({
  post_id: z.uuid(),
  classroom_id: z.uuid(),
  kind: z.enum(['homework', 'announcement']),
  title: z.string(),
})
export type DeletePreview = z.infer<typeof PreviewSchema>

/** ยอดที่จะถูกลบ — โหลดใหม่ทุกครั้งที่เปิดหน้าต่าง (ไม่เก็บแคช) */
export const postDeletePreviewQuery = (postId: string) =>
  queryOptions({
    queryKey: ['post-delete-preview', postId],
    queryFn: () => run(supabase.rpc('post_delete_preview', { p_post_id: postId }), PreviewSchema),
    staleTime: 0,
    gcTime: 0,
    retry: false,
  })

const DeletedSchema = z.object({
  post_id: z.uuid(),
  classroom_id: z.uuid(),
  kind: z.enum(['homework', 'announcement']),
  title: z.string(),
  deleted: z.object({
    submissions: z.number().int(),
    grades: z.number().int(),
    comments: z.number().int(),
    revision_permissions: z.number().int(),
    files: z.number().int(),
  }),
  queued_files: z.number().int(),
})
export type DeletedPost = z.infer<typeof DeletedSchema>

export function deletePost(input: {
  postId: string
  expected: DeleteCounts
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('delete_post', {
      p_post_id: input.postId,
      p_expected: {
        submissions: input.expected.submissions,
        grades: input.expected.grades,
        comments: input.expected.comments,
        files: input.expected.files,
      },
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    DeletedSchema,
  )
}

/** หลังลบ: เอาแคชของโพสต์ที่หายออก (ไม่ให้ขอซ้ำแล้วเจอ forbidden) และโหลดรายการที่เกี่ยวข้องใหม่ */
export async function refreshAfterDelete(queryClient: QueryClient, postId: string) {
  for (const key of ['post', 'post-edit', 'submission-list', 'solution', 'post-delete-preview']) {
    queryClient.removeQueries({ queryKey: [key, postId] })
  }
  await Promise.all(
    ['posts', 'work-summary', 'grade-table', 'my-work'].map((key) =>
      queryClient.invalidateQueries({ queryKey: [key] }),
    ),
  )
}
