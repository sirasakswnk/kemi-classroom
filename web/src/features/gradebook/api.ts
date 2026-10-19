import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// ตารางคะแนน T04 (0032_grade_table): แถวนักเรียน/คอลัมน์งาน — อ่านอย่างเดียว ครูเจ้าของห้องหรือผู้ดูแล
// เซลล์ที่ไม่มีคีย์ = ยังไม่ส่ง · waiting = ส่งแล้วรุ่นล่าสุดยังไม่มีผลตรวจ (ผลของรุ่นเก่านับเป็นรอตรวจ)
// graded = มีผลตรวจของรุ่นล่าสุด (net = null เมื่อครูบันทึกเฉพาะความครบถ้วน ไม่ให้คะแนน)

const CellSchema = z.discriminatedUnion('state', [
  z.object({ state: z.literal('waiting') }),
  z.object({
    state: z.literal('graded'),
    raw: z.number().int().nullable(),
    net: z.number().int().nullable(),
    late: z.boolean(),
  }),
])
export type Cell = z.infer<typeof CellSchema>

const GradeTableSchema = z.object({
  classroom_id: z.uuid(),
  term_id: z.uuid(),
  term_name: z.string().nullable(),
  assignments: z.array(
    z.object({
      post_id: z.uuid(),
      title: z.string(),
      due_at: z.string(),
      full_score: z.number().int(),
      published_at: z.string(),
    }),
  ),
  rows: z.array(
    z.object({
      student_id: z.uuid(),
      roll_number: z.number().int().nullable(),
      display_name: z.string(),
      member: z.boolean(),
      cells: z.record(z.string(), CellSchema),
    }),
  ),
})
export type GradeTable = z.infer<typeof GradeTableSchema>
export type GradeTableRow = GradeTable['rows'][number]

export const gradeTableKey = (classroomId: string) => ['grade-table', classroomId] as const

/** โหลดใหม่ทุกครั้งที่เปิดหน้า — ครูตรวจงานจากหน้าอื่นได้ตลอด */
export const gradeTableQuery = (classroomId: string) =>
  queryOptions({
    queryKey: gradeTableKey(classroomId),
    queryFn: () =>
      run(supabase.rpc('teacher_grade_table', { p_classroom_id: classroomId }), GradeTableSchema),
    staleTime: 0,
  })

const RoomOptionSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  term_id: z.uuid(),
  created_at: z.string(),
  terms: z.object({ name: z.string(), started_at: z.string() }),
})
export type RoomOption = z.infer<typeof RoomOptionSchema>

/** ห้องของครูทุกภาคเรียน (RLS: ครู = ห้องของตน, ผู้ดูแล = ทุกห้อง) ใช้เลือกภาคเรียน/ห้องของตาราง */
export const roomOptionsQuery = queryOptions({
  queryKey: ['grade-table-rooms'],
  queryFn: () =>
    run(
      supabase
        .from('classrooms')
        .select('id, name, term_id, created_at, terms(name, started_at)')
        .order('created_at'),
      z.array(RoomOptionSchema),
    ),
})
