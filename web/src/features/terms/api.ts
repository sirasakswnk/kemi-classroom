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
