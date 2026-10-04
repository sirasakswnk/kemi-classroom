import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// D01 บัญชีครู (supabase/migrations/0009_teacher_admin.sql) — เฉพาะ role admin

const AllowlistRowSchema = z.object({
  id: z.uuid(),
  teacher_id: z.uuid(),
  teacher_name: z.string(),
  /** อีเมลปิดบางส่วน */
  email: z.string().nullable(),
  signed_in: z.boolean(),
  created_at: z.string(),
})
export type AllowlistRow = z.infer<typeof AllowlistRowSchema>

const AdminTeachersSchema = z.object({
  admin_email: z.string().nullable(),
  teachers: z.array(z.object({ id: z.uuid(), display_name: z.string() })),
  allowlist: z.array(AllowlistRowSchema),
})
export type AdminTeachers = z.infer<typeof AdminTeachersSchema>

export const adminTeachersQuery = queryOptions({
  queryKey: ['admin-teachers'],
  queryFn: () => run(supabase.rpc('admin_teachers'), AdminTeachersSchema),
})

export function addTeacher(input: { email: string; teacherId: string | null; newName: string }) {
  return run(
    supabase.rpc('admin_add_teacher', {
      p_email: input.email,
      ...(input.teacherId
        ? { p_teacher_id: input.teacherId }
        : { p_new_teacher_name: input.newName }),
    }),
    AllowlistRowSchema.omit({ created_at: true }),
  )
}

export function removeTeacher(allowlistId: string) {
  return run(
    supabase.rpc('admin_remove_teacher', { p_allowlist_id: allowlistId }),
    z.object({ id: z.uuid(), removed: z.boolean(), demoted_accounts: z.number().int() }),
  )
}
