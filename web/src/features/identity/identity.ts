import { supabase, toAppError, type AppError } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ผลของ search_roster / claim_identity (supabase/migrations/0004_identity.sql)
const MatchSchema = z.object({
  ref: z.uuid(),
  masked_name: z.string(),
  group_name: z.string(),
  roll_number: z.number().int(),
})

export const SearchResultSchema = z.object({
  matches: z.array(MatchSchema),
  bound: z.boolean(),
  remaining: z.number().int(),
})

export const ClaimResultSchema = z.discriminatedUnion('status', [
  z.object({
    status: z.literal('claimed'),
    display_name: z.string(),
    group_name: z.string().nullable(),
    roll_number: z.number().int().nullable(),
  }),
  z.object({ status: z.literal('name_taken') }),
  z.object({ status: z.literal('expired') }),
])

// แถวของตัวเองใน students (RLS ให้นักเรียนเห็นเฉพาะแถวที่ผูกกับบัญชีตัวเอง) — null = ยังไม่ผูกชื่อ
export const MyStudentSchema = z.object({ display_name: z.string() }).nullable()

export type Match = z.infer<typeof MatchSchema>
export type SearchResult = z.infer<typeof SearchResultSchema>
export type ClaimResult = z.infer<typeof ClaimResultSchema>
export type MyStudent = NonNullable<z.infer<typeof MyStudentSchema>>

export type Outcome<T> = { ok: true; data: T } | { ok: false; error: AppError }

/** เหลือจำนวนครั้งค้นเท่านี้หรือน้อยกว่าให้บอกล่วงหน้า (แบบ v2) */
export const REMAINING_WARN_AT = 3

/** ปุ่มค้นหากดได้เมื่อพิมพ์อย่างน้อย 2 ตัวอักษร (ไม่นับช่องว่าง) — ค้นจริงเมื่อกดเท่านั้น */
export function canSearch(query: string): boolean {
  return query.replace(/\s/g, '').length >= 2
}

/** ตัวอักษรแรกของชื่อปิดบางส่วนสำหรับวงกลมรูปแทนตัว */
export function initialOf(maskedName: string): string {
  return Array.from(maskedName.trim())[0] ?? ''
}

async function call<T>(
  request: PromiseLike<{ data: unknown; error: unknown }>,
  schema: z.ZodType<T>,
): Promise<Outcome<T>> {
  try {
    const { data, error } = await request
    if (error) return { ok: false, error: toAppError(error) }
    const parsed = schema.safeParse(data)
    return parsed.success
      ? { ok: true, data: parsed.data }
      : { ok: false, error: toAppError({ name: 'InvalidResponse' }) }
  } catch (error) {
    return { ok: false, error: toAppError(error) }
  }
}

export function searchRoster(query: string): Promise<Outcome<SearchResult>> {
  return call(supabase.rpc('search_roster', { p_query: query }), SearchResultSchema)
}

export function claimIdentity(ref: string): Promise<Outcome<ClaimResult>> {
  return call(supabase.rpc('claim_identity', { p_ref: ref }), ClaimResultSchema)
}

export function fetchMyStudent(): Promise<Outcome<MyStudent | null>> {
  return call(supabase.from('students').select('display_name').maybeSingle(), MyStudentSchema)
}
