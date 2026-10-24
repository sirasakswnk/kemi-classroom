import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// พื้นที่เก็บไฟล์ (J10) และตัวนับ B2 รายวัน (TECHNICAL_DESIGN 9.3) — RPC ของ 0023_jobs
// storage_status: ครู/ผู้ดูแลได้ยอดละเอียด · นักเรียนได้แค่ระดับ (full/ok) · admin_b2_usage: ผู้ดูแลเท่านั้น

const LevelSchema = z.enum(['ok', 'admin_warn', 'teacher_warn', 'full'])
export type StorageLevel = z.infer<typeof LevelSchema>

const StorageSchema = z.object({
  level: LevelSchema,
  used_bytes: z.number().optional(),
  limit_bytes: z.number().optional(),
  quota_bytes: z.number().optional(),
  percent: z.number().optional(),
  admin_warn_pct: z.number().optional(),
  teacher_warn_pct: z.number().optional(),
  reserved_bytes: z.number().optional(),
  deleting_bytes: z.number().optional(),
  /** ส่วนที่ B2 มากกว่าที่ระบบนับ ณ การเทียบล่าสุด (0049) — รวมอยู่ใน used_bytes แล้ว */
  offset_bytes: z.number().optional(),
  reconciled_at: z.string().nullable().optional(),
  by_purpose: z
    .object({ submission: z.number(), post: z.number(), solution: z.number(), charm: z.number() })
    .optional(),
})
export type StorageStatus = z.infer<typeof StorageSchema>

/** ระดับพื้นที่ (โหลดใหม่ทุก 5 นาที — แถบเตือนครู/กล่องเต็มของนักเรียน) */
export const storageStatusQuery = queryOptions({
  queryKey: ['storage-status'],
  queryFn: () => run(supabase.rpc('storage_status'), StorageSchema),
  staleTime: 60_000,
  refetchInterval: 5 * 60_000,
})

const UsageRow = z.object({
  class_b_requests: z.number(),
  /** คำขอ List (Class C) — ใช้โดยการเทียบยอดพื้นที่ (0049/0052) */
  class_c_requests: z.number().optional(),
  download_bytes: z.number(),
  copy_bytes: z.number(),
})
const B2UsageSchema = z.object({
  day: z.string(),
  sources: z.record(z.string(), UsageRow),
  view_budget_requests: z.number(),
  view_budget_bytes: z.number(),
  reconcile_budget_requests: z.number().optional(),
  reconcile_run_max_requests: z.number().optional(),
  jobs: z.object({ pending: z.number(), running: z.number(), failed: z.number() }),
})
export type B2Usage = z.infer<typeof B2UsageSchema>

export const adminB2UsageQuery = queryOptions({
  queryKey: ['admin-b2-usage'],
  queryFn: () => run(supabase.rpc('admin_b2_usage'), B2UsageSchema),
  staleTime: 30_000,
})

// ผลเทียบยอดพื้นที่ B2 ล่าสุด (0049/0050) — ผู้ดูแลเท่านั้น · ยังไม่เคยเทียบ = null
const ReconcileSchema = z
  .object({
    finished_at: z.string(),
    b2_bytes: z.number(),
    db_bytes: z.number(),
    diff_bytes: z.number(),
    offset_bytes: z.number(),
    exceeds_threshold: z.boolean(),
  })
  .nullable()
export type StorageReconcile = z.infer<typeof ReconcileSchema>

export const adminStorageReconcileQuery = queryOptions({
  queryKey: ['admin-storage-reconcile'],
  queryFn: () => run(supabase.rpc('admin_storage_reconcile'), ReconcileSchema),
  staleTime: 5 * 60_000,
})

// ภาคเรียนเปิดค้างเกิน 6 เดือน (0053, J9.2 เสริม) — ผู้ดูแลเท่านั้น · ไม่ต้องเตือน = null
const TermAlertSchema = z
  .object({
    term_id: z.uuid(),
    name: z.string(),
    started_at: z.string(),
    due_at: z.string(),
    days_open: z.number().int(),
  })
  .nullable()
export type TermAlert = z.infer<typeof TermAlertSchema>

export const adminTermAlertQuery = queryOptions({
  queryKey: ['admin-term-alert'],
  queryFn: () => run(supabase.rpc('admin_term_alert'), TermAlertSchema),
  staleTime: 5 * 60_000,
})

/** ขนาดแบบที่ B2 คิด (1 GB = 1,000,000,000 ไบต์) */
export function formatSize(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`
  if (bytes >= 1e3) return `${Math.round(bytes / 1e3)} KB`
  return `${bytes} ไบต์`
}
