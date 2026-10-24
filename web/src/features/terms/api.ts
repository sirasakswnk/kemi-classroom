import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// T07 ภาคเรียนและข้อมูลเก่า — RPC ของ 0041_terms (เริ่ม/จบ) และ 0042_term_overview (อ่าน)

const TermStateSchema = z.object({
  term_id: z.uuid(),
  name: z.string(),
  status: z.enum(['active', 'ended']),
  epoch: z.number().int(),
  started_at: z.string(),
  ended_at: z.string().nullable(),
})
export type TermState = z.infer<typeof TermStateSchema>

const OldTermSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  /** end = กดจบภาคเรียน · start = เริ่มภาคเรียนใหม่ทับ */
  how: z.enum(['end', 'start']),
  retention_from: z.string(),
  files_due: z.string(),
  data_due: z.string(),
})
export type OldTerm = z.infer<typeof OldTermSchema>

const OverviewSchema = z.object({
  term: TermStateSchema,
  classrooms: z.number().int(),
  students: z.number().int(),
  tokens: z.number().int(),
  waiting: z.number().int(),
  old_terms: z.array(OldTermSchema),
})
export type TermOverview = z.infer<typeof OverviewSchema>

export const termOverviewQuery = (adminMode: boolean) =>
  queryOptions({
    queryKey: ['term-overview', adminMode],
    queryFn: () => run(supabase.rpc('term_overview', { p_admin_mode: adminMode }), OverviewSchema),
    staleTime: 0,
  })

/** เริ่มภาคเรียนใหม่ — หน้าจอเห็นภาคเรียนอื่น = stale_revision, ชื่อซ้ำ = term_name_taken */
export const termsStart = (
  name: string,
  expectedTermId: string,
  requestKey: string,
  adminMode: boolean,
) =>
  run(
    supabase.rpc('terms_start', {
      p_name: name,
      p_expected_term_id: expectedTermId,
      p_request_key: requestKey,
      p_admin_mode: adminMode,
    }),
    TermStateSchema.extend({ previous_term_id: z.uuid() }),
  )

/** จบภาคเรียนโดยไม่เปิดเทอมใหม่ — จบไปแล้ว = term_ended */
export const termsEnd = (expectedTermId: string, requestKey: string, adminMode: boolean) =>
  run(
    supabase.rpc('terms_end', {
      p_expected_term_id: expectedTermId,
      p_request_key: requestKey,
      p_admin_mode: adminMode,
    }),
    TermStateSchema,
  )

export const TERM_NAME_MAX = 60

// ---------------------------------------------------------------------------
// ข้อมูลภาคเรียนเก่า (0054_retention, 0055_retention_data) — ดาวน์โหลดแล้วบันทึกว่าครบก่อนยืนยันลบ
// ---------------------------------------------------------------------------

const RetentionBase = {
  due_at: z.string(),
  expired: z.boolean(),
  /** ชุดปัจจุบันตรงกับที่ดาวน์โหลดครบล่าสุด */
  downloaded: z.boolean(),
  downloaded_at: z.string().nullable(),
  /** เคยดาวน์โหลดแต่ข้อมูลเปลี่ยนแล้ว → ดาวน์โหลดใหม่ก่อนยืนยัน */
  download_stale: z.boolean(),
  confirmed_at: z.string().nullable(),
  deleted_at: z.string().nullable(),
  can_confirm: z.boolean(),
}
const RetentionStatusSchema = z.object({
  files: z.object({
    ...RetentionBase,
    count: z.number().int(),
    bytes: z.number().int(),
    /** ยังไม่ครบ 60 วัน = ปุ่ม “ลบก่อนครบ 60 วัน” (J10.4) */
    early: z.boolean(),
  }),
  data: z.object({
    ...RetentionBase,
    count: z.number().int(),
    /** ไม่มีไฟล์ของภาคเรียนเหลือ — ลบคะแนนได้หลังลบไฟล์เท่านั้น */
    files_cleared: z.boolean(),
  }),
})
export type RetentionStatus = z.infer<typeof RetentionStatusSchema>

const CommentOutSchema = z.object({
  author: z.enum(['teacher', 'student']),
  created_at: z.string(),
  retracted: z.boolean(),
  /** null เมื่อยกเลิกแล้ว — เซิร์ฟเวอร์ไม่ส่งเนื้อข้อความ */
  body: z.string().nullable(),
})

const TermDataRowSchema = z.object({
  classroom_name: z.string(),
  post_id: z.uuid(),
  post_title: z.string(),
  full_score: z.number().int(),
  due_at: z.string(),
  student_code: z.string(),
  display_name: z.string(),
  group_name: z.string().nullable(),
  roll_number: z.number().int().nullable(),
  member: z.boolean(),
  first_submitted_at: z.string().nullable(),
  last_submitted_at: z.string().nullable(),
  content_revision: z.number().int().nullable(),
  /** null = ยังไม่ส่ง · false = รอตรวจ · true = ตรวจฉบับล่าสุดแล้ว */
  graded_current: z.boolean().nullable(),
  raw_score: z.number().int().nullable(),
  passed: z.boolean().nullable(),
  timing: z.enum(['on_time', 'late']).nullable(),
  applied_penalty_pct: z.number().int().nullable(),
  net_score: z.number().int().nullable(),
  graded_at: z.string().nullable(),
  comments: z.array(CommentOutSchema),
})
export type TermDataRow = z.infer<typeof TermDataRowSchema>

const TermDataSchema = z.object({
  term_id: z.uuid(),
  term_name: z.string(),
  fingerprint: z.string(),
  count: z.number().int(),
  bytes: z.literal(0),
  rows: z.array(TermDataRowSchema),
})
export type TermData = z.infer<typeof TermDataSchema>

/** คะแนน เวลาส่ง และความคิดเห็นทั้งภาคเรียนเก่า สำหรับ CSV — ภาคเรียนที่ยังเปิด = invalid_request */
export const exportTermData = (termId: string, adminMode: boolean) =>
  run(
    supabase.rpc('export_term_data', { p_term_id: termId, p_admin_mode: adminMode }),
    TermDataSchema,
  )

/** บันทึกว่าดาวน์โหลดครบ — จำนวน/ไบต์/fingerprint ไม่ตรงชุดตอนนี้ = export_mismatch */
export const markDownloaded = (
  termId: string,
  scope: 'files' | 'data',
  fingerprint: string,
  count: number,
  bytes: number,
  adminMode: boolean,
) =>
  run(
    supabase.rpc('export_mark_downloaded', {
      p_term_id: termId,
      p_scope: scope,
      p_fingerprint: fingerprint,
      p_count: count,
      p_bytes: bytes,
      p_admin_mode: adminMode,
    }),
    RetentionStatusSchema,
  )
