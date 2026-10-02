import { z } from '../../lib/zod'

// ผลของ ensure_account() (supabase/migrations/0002_accounts.sql)
export const AccountSchema = z.object({
  account_id: z.uuid(),
  role: z.enum(['student', 'teacher', 'admin']),
  email: z.string().nullable(),
  teacher_id: z.uuid().nullable(),
})

export type Account = z.infer<typeof AccountSchema>
export type Role = Account['role']

// หน้าแรกของแต่ละบทบาท (TECHNICAL_BUILD_PLAN ส่วน 6)
const HOME: Record<Role, string> = {
  student: '/',
  teacher: '/t',
  admin: '/admin',
}

export function homeFor(role: Role): string {
  return HOME[role]
}
