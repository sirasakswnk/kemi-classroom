import { infiniteQueryOptions, queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// กระดิ่ง (C01/T11) — RPC ของ 0043_notifications + 0048_notification_relevance
// ผลอ่านสถานะปัจจุบันของเป้าหมาย (relevant, comment_retracted, submitted) และไม่มีเนื้อความคิดเห็น (TECHNICAL_DESIGN 11)

export const NOTIFICATION_KINDS = [
  'post_published',
  'due_reminder',
  'teacher_comment',
  'revision_opened',
  'due_changed',
  'intake_closed',
  'solution_published',
  'pending_review',
  'student_comment',
  'storage_threshold',
] as const
export type NotificationKind = (typeof NOTIFICATION_KINDS)[number]

const ItemSchema = z.object({
  id: z.uuid(),
  kind: z.enum(NOTIFICATION_KINDS),
  /** เวลาเหตุการณ์ล่าสุด (เรียงตามค่านี้) */
  at: z.string(),
  read: z.boolean(),
  /** ยังเกี่ยวข้องตอนนี้ — false = แสดงจาง ไม่นับยังไม่อ่าน */
  relevant: z.boolean(),
  /** due_reminder: ส่งแล้วหรือยัง (ชนิดอื่น null) */
  submitted: z.boolean().nullable(),
  post_id: z.uuid().nullable(),
  post_kind: z.enum(['homework', 'announcement']).nullable(),
  title: z.string().nullable(),
  classroom_id: z.uuid().nullable(),
  classroom_name: z.string().nullable(),
  due_at: z.string().nullable(),
  comment_id: z.uuid().nullable(),
  comment_retracted: z.boolean().nullable(),
  student_id: z.uuid().nullable(),
  student_name: z.string().nullable(),
  pending_count: z.number().int().nullable(),
  level: z.number().int().nullable(),
})
export type NotificationItem = z.infer<typeof ItemSchema>

const PageSchema = z.object({
  unread_count: z.number().int(),
  items: z.array(ItemSchema),
})
export type NotificationPage = z.infer<typeof PageSchema>

export const PAGE_SIZE = 30
// ตัวเลขบนกระดิ่งดึงซ้ำทุก 2 นาทีระหว่างเปิดหน้าอยู่ (+ ตอนกลับมาที่แท็บ) — ไม่มี realtime
const UNREAD_REFRESH_MS = 120_000

export const unreadCountQuery = queryOptions({
  queryKey: ['notifications', 'unread'],
  queryFn: () => run(supabase.rpc('unread_notification_count'), z.number().int()),
  refetchInterval: UNREAD_REFRESH_MS,
  retry: false,
})

/** รายการเป็นหน้า ๆ — หน้าถัดไปเริ่มก่อนเวลา at ของรายการสุดท้าย */
export const notificationsQuery = infiniteQueryOptions({
  queryKey: ['notifications', 'list'],
  queryFn: ({ pageParam }) =>
    run(
      supabase.rpc('my_notifications', {
        ...(pageParam ? { p_before: pageParam } : {}),
        p_limit: PAGE_SIZE,
      }),
      PageSchema,
    ),
  initialPageParam: null as string | null,
  getNextPageParam: (last) =>
    last.items.length < PAGE_SIZE ? null : (last.items[last.items.length - 1]?.at ?? null),
  staleTime: 0,
})

/** ทำเครื่องหมายอ่าน — ids = null คือ “อ่านทั้งหมด” · ผล: จำนวนที่ยังไม่อ่านหลังทำ */
export const markNotificationsRead = (ids: string[] | null) =>
  run(supabase.rpc('mark_notifications_read', ids ? { p_ids: ids } : {}), z.number().int())
