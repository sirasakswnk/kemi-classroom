import { queryOptions, type QueryClient } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'
import type { AttachmentRef } from '../uploads/AttachmentList'

// คำสั่งของ T03 หน้าต่าง M1–M3 — เปลี่ยนกำหนดส่ง (0028), ปิดรับ/เปิดรับอีกครั้ง (0028/0030), เฉลย (0029)

const PersonSchema = z.object({
  submission_id: z.uuid(),
  student_id: z.uuid(),
  roll_number: z.number().int().nullable(),
  display_name: z.string(),
})
export type AffectedPerson = z.infer<typeof PersonSchema>

const DuePreviewSchema = z.object({
  due_at: z.string(),
  new_due_at: z.string(),
  close_at: z.string().nullable(),
  to_on_time: z.array(PersonSchema),
  to_late: z.array(PersonSchema),
  graded_count: z.number().int(),
})
export type DuePreview = z.infer<typeof DuePreviewSchema>

/** ผลก่อนเปลี่ยนกำหนดส่ง (อ่านอย่างเดียว) — ไม่เก็บแคชนานเพราะต้องตรงกับตอนกดยืนยัน */
export const duePreviewQuery = (postId: string, dueAt: string) =>
  queryOptions({
    queryKey: ['due-preview', postId, dueAt],
    queryFn: () =>
      run(
        supabase.rpc('preview_due_change', { p_assignment_id: postId, p_due_at: dueAt }),
        DuePreviewSchema,
      ),
    staleTime: 0,
    gcTime: 30_000,
    retry: false,
  })

export function changeDue(input: {
  postId: string
  dueAt: string
  preview: DuePreview
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('change_due', {
      p_assignment_id: input.postId,
      p_due_at: input.dueAt,
      p_expected_to_on_time: input.preview.to_on_time.map((p) => p.submission_id),
      p_expected_to_late: input.preview.to_late.map((p) => p.submission_id),
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    z.object({ due_at: z.string() }),
  )
}

const IntakeResultSchema = z.object({
  intake: z.enum(['open', 'closed', 'after_solution']),
  close_at: z.string().nullable(),
  closed_at: z.string().nullable(),
})

/** closeAt = null → ปิดทันที (หรือปิดช่วงรับหลังเฉลย); มีค่า → ตั้งเวลาปิดรับ */
export function closeAssignment(input: {
  postId: string
  closeAt: string | null
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('close_assignment', {
      p_assignment_id: input.postId,
      // null = ปิดทันที — type ที่สร้างอัตโนมัติไม่รู้ว่ารับ null ได้
      p_close_at: input.closeAt as string,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    IntakeResultSchema,
  )
}

/** ก่อนเผยแพร่เฉลย: ล้างสถานะปิด และตั้ง/ยกเลิกเวลาปิด (closeAt = null = ไม่ตั้ง) */
export function reopenAssignment(input: {
  postId: string
  closeAt: string | null
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('reopen_assignment', {
      p_assignment_id: input.postId,
      p_close_at: input.closeAt as string,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    IntakeResultSchema,
  )
}

// ---------- เฉลย ----------
const SolutionRowSchema = z.object({
  body: z.string().nullable(),
  published_at: z.string().nullable(),
  updated_at: z.string(),
  version: z.number().int(),
  attachments: z.array(
    z.object({
      position: z.number().int(),
      assets: z
        .object({
          id: z.uuid(),
          file_name: z.string(),
          content_type: z.string(),
          size_bytes: z.number().int(),
        })
        .nullable(),
    }),
  ),
})

export interface Solution {
  body: string | null
  publishedAt: string | null
  updatedAt: string
  version: number
  files: AttachmentRef[]
}

/** เฉลยของงาน (RLS: ครูเห็นทุกสถานะ) — null = ยังไม่เคยบันทึก */
export const solutionQuery = (postId: string) =>
  queryOptions({
    queryKey: ['solution', postId],
    queryFn: async (): Promise<Solution | null> => {
      const row = await run(
        supabase
          .from('solutions')
          .select(
            'body, published_at, updated_at, version, attachments(position, assets(id, file_name, content_type, size_bytes))',
          )
          .eq('assignment_id', postId)
          .maybeSingle(),
        SolutionRowSchema.nullable(),
      )
      if (!row) return null
      return {
        body: row.body,
        publishedAt: row.published_at,
        updatedAt: row.updated_at,
        version: row.version,
        files: [...row.attachments]
          .sort((a, b) => a.position - b.position)
          .flatMap((t) =>
            t.assets
              ? [
                  {
                    asset_id: t.assets.id,
                    file_name: t.assets.file_name,
                    content_type: t.assets.content_type,
                    size_bytes: t.assets.size_bytes,
                  },
                ]
              : [],
          ),
      }
    },
  })

const SavedSolutionSchema = z.object({
  version: z.number().int(),
  published_at: z.string().nullable(),
})

export function saveSolution(input: {
  postId: string
  body: string
  files: string[]
  expectedVersion: number
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('save_solution', {
      p_assignment_id: input.postId,
      p_body: input.body,
      p_files: input.files,
      p_expected_version: input.expectedVersion,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    SavedSolutionSchema,
  )
}

export function publishSolution(input: {
  postId: string
  expectedVersion: number
  requestKey: string
  adminMode: boolean
}) {
  return run(
    supabase.rpc('publish_solution', {
      p_assignment_id: input.postId,
      p_expected_version: input.expectedVersion,
      p_request_key: input.requestKey,
      p_admin_mode: input.adminMode,
    }),
    SavedSolutionSchema,
  )
}

/** หลังคำสั่งใดของ M1–M3 สำเร็จ: โหลดสถานะงาน รายชื่อ ยอด และเฉลยใหม่ */
export function refreshAssignment(queryClient: QueryClient, postId: string) {
  return Promise.all(
    [
      ['submission-list', postId],
      ['post', postId],
      ['post-edit', postId],
      ['solution', postId],
      ['work-summary'],
    ].map((queryKey) => queryClient.invalidateQueries({ queryKey })),
  )
}
