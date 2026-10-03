import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

export { appErrorOf, RequestError } from '../../lib/request'

// ข้อมูลหน้าครู (T01, T08, T09) — อ่านตารางผ่าน RLS (0005_classrooms, 0006_teachers_read) เขียนผ่าน RPC เท่านั้น

// ---------- ภาคเรียนปัจจุบัน ----------
const TermSchema = z
  .object({
    term_id: z.uuid(),
    status: z.enum(['active', 'ended']),
    terms: z.object({ name: z.string() }),
  })
  .nullable()
  .transform((t) => (t ? { id: t.term_id, status: t.status, name: t.terms.name } : null))

export type Term = NonNullable<z.infer<typeof TermSchema>>

export const termQuery = queryOptions({
  queryKey: ['term'],
  queryFn: () =>
    run(
      supabase.from('term_control').select('term_id, status, terms(name)').maybeSingle(),
      TermSchema,
    ),
})

// ---------- ชั้นเรียน ----------
const CLASSROOM_COLUMNS =
  'id, name, description, join_code, join_enabled, teacher_id, term_id, created_at, memberships(count)'

const ClassroomRowSchema = z
  .object({
    id: z.uuid(),
    name: z.string(),
    description: z.string().nullable(),
    join_code: z.string(),
    join_enabled: z.boolean(),
    teacher_id: z.uuid(),
    term_id: z.uuid(),
    created_at: z.string(),
    memberships: z.array(z.object({ count: z.number().int() })),
  })
  .transform(({ memberships, ...c }) => ({ ...c, member_count: memberships[0]?.count ?? 0 }))

export type Classroom = z.infer<typeof ClassroomRowSchema>

/** ชั้นเรียนของภาคเรียนนี้ที่ผู้เรียกเห็น (ครู = ห้องของตัวเอง, ผู้ดูแล = ทุกห้อง) เรียงตามวันที่สร้าง */
export const classroomsQuery = (termId: string | undefined) =>
  queryOptions({
    queryKey: ['classrooms', termId],
    enabled: !!termId,
    queryFn: () =>
      run(
        supabase
          .from('classrooms')
          .select(CLASSROOM_COLUMNS)
          .eq('term_id', termId ?? '')
          .order('created_at'),
        z.array(ClassroomRowSchema),
      ),
  })

/** null = ไม่มีห้องนี้ หรือไม่มีสิทธิ์เห็น (RLS) */
export const classroomQuery = (id: string) =>
  queryOptions({
    queryKey: ['classroom', id],
    queryFn: () =>
      run(
        supabase.from('classrooms').select(CLASSROOM_COLUMNS).eq('id', id).maybeSingle(),
        ClassroomRowSchema.nullable(),
      ),
  })

// ---------- สมาชิก ----------
const MemberRowSchema = z
  .object({
    student_id: z.uuid(),
    joined_at: z.string(),
    students: z.object({
      display_name: z.string(),
      roster_entries: z.array(
        z.object({ group_name: z.string(), roll_number: z.number().int(), term_id: z.uuid() }),
      ),
    }),
  })
  .transform((m) => ({ student_id: m.student_id, joined_at: m.joined_at, ...m.students }))

export interface Member {
  student_id: string
  joined_at: string
  display_name: string
  /** ห้องและเลขที่ตามรายชื่อของภาคเรียนนี้ (ไม่มีถ้าไม่อยู่ในรายชื่อเทอมนี้) */
  group_name: string | null
  roll_number: number | null
}

export const membersQuery = (classroomId: string, termId: string | undefined) =>
  queryOptions({
    queryKey: ['members', classroomId, termId],
    enabled: !!termId,
    queryFn: async (): Promise<Member[]> => {
      const rows = await run(
        supabase
          .from('memberships')
          .select(
            'student_id, joined_at, students(display_name, roster_entries(group_name, roll_number, term_id))',
          )
          .eq('classroom_id', classroomId),
        z.array(MemberRowSchema),
      )
      return rows
        .map((m) => {
          const entry = m.roster_entries.find((e) => e.term_id === termId)
          return {
            student_id: m.student_id,
            joined_at: m.joined_at,
            display_name: m.display_name,
            group_name: entry?.group_name ?? null,
            roll_number: entry?.roll_number ?? null,
          }
        })
        .sort(compareMembers)
    },
  })

/** เรียงตามห้องในรายชื่อ เลขที่ แล้วชื่อ — คนที่ไม่มีในรายชื่อเทอมนี้อยู่ท้าย */
export function compareMembers(a: Member, b: Member): number {
  if ((a.group_name === null) !== (b.group_name === null)) return a.group_name === null ? 1 : -1
  const byGroup = (a.group_name ?? '').localeCompare(b.group_name ?? '', 'th', { numeric: true })
  if (byGroup) return byGroup
  const byRoll = (a.roll_number ?? 0) - (b.roll_number ?? 0)
  return byRoll || a.display_name.localeCompare(b.display_name, 'th')
}

// ---------- ครู ----------
const TeacherSchema = z.object({ id: z.uuid(), display_name: z.string() })
export type Teacher = z.infer<typeof TeacherSchema>

export const teachersQuery = queryOptions({
  queryKey: ['teachers'],
  queryFn: () =>
    run(
      supabase.from('teachers').select('id, display_name').order('display_name'),
      z.array(TeacherSchema),
    ),
})

// ---------- RPC ----------
const CreatedSchema = z.object({
  classroom_id: z.uuid(),
  name: z.string(),
  join_code: z.string(),
  join_enabled: z.boolean(),
})

export function createClassroom(input: {
  name: string
  description: string
  requestKey: string
  teacherId: string | null
  adminMode: boolean
}) {
  return run(
    supabase.rpc('create_classroom', {
      p_name: input.name,
      p_description: input.description,
      p_request_key: input.requestKey,
      ...(input.adminMode
        ? { p_teacher_id: input.teacherId ?? undefined, p_admin_mode: true }
        : {}),
    }),
    CreatedSchema,
  )
}

export function setJoinEnabled(classroomId: string, enabled: boolean, adminMode: boolean) {
  return run(
    supabase.rpc('set_join_enabled', {
      p_classroom_id: classroomId,
      p_enabled: enabled,
      p_admin_mode: adminMode,
    }),
    z.object({ classroom_id: z.uuid(), join_enabled: z.boolean(), join_code: z.string() }),
  )
}

export function removeMember(classroomId: string, studentId: string, adminMode: boolean) {
  return run(
    supabase.rpc('remove_member', {
      p_classroom_id: classroomId,
      p_student_id: studentId,
      p_admin_mode: adminMode,
    }),
    z.object({ classroom_id: z.uuid(), student_id: z.uuid(), removed: z.boolean() }),
  )
}

/** ลิงก์เชิญใช้รหัสเดียวกับที่พิมพ์ (TECHNICAL_DESIGN 4) */
export function inviteLink(code: string, origin = window.location.origin): string {
  return `${origin}/join/${code}`
}
