import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ข้อมูลหน้านักเรียน (S01, S02, S06, ลิงก์เชิญ) — ห้องและเพื่อนในห้องผ่าน RPC ของ 0007 (ไม่เห็นเลขประจำตัวคนอื่น)
// แถวของตัวเองอ่านผ่าน RLS; การหา/เข้าห้องผ่าน RPC ของ 0005

const MyClassroomSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().nullable(),
  teacher_name: z.string(),
  member_count: z.number().int(),
  joined_at: z.string(),
})
export type MyClassroom = z.infer<typeof MyClassroomSchema>

export const myClassroomsQuery = queryOptions({
  queryKey: ['my-classrooms'],
  queryFn: () => run(supabase.rpc('my_classrooms'), z.array(MyClassroomSchema)),
})

const ClassroomViewSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().nullable(),
  teacher_name: z.string(),
  term_name: z.string(),
  member_count: z.number().int(),
  members: z.array(
    z.object({
      display_name: z.string(),
      roll_number: z.number().int().nullable(),
      is_me: z.boolean(),
    }),
  ),
})
export type ClassroomView = z.infer<typeof ClassroomViewSchema>

/** หัวห้อง + สมาชิก (S02): อ่านสดเมื่อกลับมาที่แท็บและทุก 1 นาที — ถูกเอาออกแล้วเห็น not_member (UX 7.1) */
export const classroomViewQuery = (classId: string) =>
  queryOptions({
    queryKey: ['classroom-view', classId],
    queryFn: () =>
      run(supabase.rpc('classroom_view', { p_classroom_id: classId }), ClassroomViewSchema),
    staleTime: 0,
    refetchInterval: 60_000,
    retry: false,
  })

const MyProfileSchema = z
  .object({
    display_name: z.string(),
    student_code: z.string(),
    roster_entries: z.array(
      z.object({ group_name: z.string(), roll_number: z.number().int(), term_id: z.uuid() }),
    ),
  })
  .nullable()
export type MyProfile = NonNullable<z.infer<typeof MyProfileSchema>>

/** S06: ชื่อ เลขประจำตัว และห้อง/เลขที่ตามรายชื่อ — RLS ให้เห็นเฉพาะแถวของตัวเอง */
export const myProfileQuery = queryOptions({
  queryKey: ['my-profile'],
  queryFn: () =>
    run(
      supabase
        .from('students')
        .select('display_name, student_code, roster_entries(group_name, roll_number, term_id)')
        .maybeSingle(),
      MyProfileSchema,
    ),
})

// ---------- หา/เข้าห้องด้วยรหัส (0005) ----------
const CardSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  teacher_name: z.string(),
  member_count: z.number().int(),
})
export type ClassCard = z.infer<typeof CardSchema>

const FindSchema = z.discriminatedUnion('status', [
  z.object({ status: z.literal('found'), classroom: CardSchema }),
  z.object({ status: z.literal('member'), classroom: CardSchema }),
  z.object({ status: z.literal('joined'), classroom: CardSchema }),
  z.object({ status: z.literal('closed') }),
  z.object({ status: z.literal('not_found'), remaining: z.number().int() }),
])
export type FindResult = z.infer<typeof FindSchema>

export function lookupClassroom(code: string) {
  return run(supabase.rpc('lookup_classroom', { p_code: code }), FindSchema)
}

export function joinClassroom(code: string) {
  return run(supabase.rpc('join_classroom', { p_code: code }), FindSchema)
}

/** รหัสที่พิมพ์: ตัวพิมพ์ใหญ่ ตัดช่องว่างและขีด (เซิร์ฟเวอร์ทำแบบเดียวกันอีกครั้ง) */
export function normalizeCode(value: string): string {
  return value.toUpperCase().replace(/[\s\u00a0\u200b-]/g, '')
}
