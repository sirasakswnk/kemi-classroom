import { z } from '../../lib/zod'

// ผลของ preview_roster_import / commit_roster_import (supabase/migrations/0003_roster.sql)
export const PlanRowSchema = z.object({
  index: z.number().int(),
  status: z.enum(['new', 'added', 'moved', 'updated', 'unchanged', 'error']),
  errors: z.array(z.string()),
  changes: z.array(z.string()),
  from_group: z.string().nullable(),
  bound: z.boolean(),
})

export const PlanSchema = z.object({
  ok: z.boolean(),
  errors: z.array(z.string()),
  group_name: z.string(),
  term: z.object({ id: z.uuid(), name: z.string() }).optional(),
  counts: z
    .object({
      rows: z.number(),
      new: z.number(),
      added: z.number(),
      moved: z.number(),
      updated: z.number(),
      unchanged: z.number(),
      errors: z.number(),
      missing: z.number(),
    })
    .optional(),
  rows: z.array(PlanRowSchema),
  missing: z.array(
    z.object({
      student_code: z.string(),
      display_name: z.string(),
      roll_number: z.number(),
      bound: z.boolean(),
    }),
  ),
  committed: z.boolean().optional(),
})

export type Plan = z.infer<typeof PlanSchema>
export type PlanRow = z.infer<typeof PlanRowSchema>
