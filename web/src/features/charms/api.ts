import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// T06 จัดการเครื่องราง — RPC ของ 0040_charm_admin (ครู/ผู้ดูแลในโหมดผู้ดูแล)

const AdminCharmSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string(),
  symbol: z.string(),
  rarity_id: z.number().int(),
  position: z.number().int(),
  version: z.number().int(),
  /** null = รูปวาดชั่วคราว */
  image_asset_id: z.uuid().nullable(),
  /** จำนวนนักเรียนที่มีชิ้นนี้ */
  owners: z.number().int(),
})
export type AdminCharm = z.infer<typeof AdminCharmSchema>

const RaritySchema = z.object({
  id: z.number().int(),
  name: z.string(),
  weight: z.number().int(),
  count: z.number().int(),
})
export type Rarity = z.infer<typeof RaritySchema>

const RatesSchema = z.object({ weights_key: z.string(), rarities: z.array(RaritySchema) })
const CatalogSchema = RatesSchema.extend({ charms: z.array(AdminCharmSchema) })
export type Catalog = z.infer<typeof CatalogSchema>

export const catalogQuery = (adminMode: boolean) =>
  queryOptions({
    queryKey: ['charm-catalog', adminMode],
    queryFn: () => run(supabase.rpc('charm_catalog', { p_admin_mode: adminMode }), CatalogSchema),
    staleTime: 0,
  })

/** บันทึกอัตราทั้ง 4 ระดับ — รุ่นอัตราไม่ตรง = stale_revision, รวมไม่ใช่ 100 = rates_must_total_100 */
export const saveRarityWeights = (
  weights: { rarity_id: number; weight: number }[],
  expectedKey: string,
  adminMode: boolean,
) =>
  run(
    supabase.rpc('save_rarity_weights', {
      p_weights: weights,
      p_expected_key: expectedKey,
      p_admin_mode: adminMode,
    }),
    RatesSchema,
  )

export interface CharmInput {
  /** ไม่มี = เพิ่มใหม่ */
  id?: string
  name: string
  description: string
  rarity_id: number
  /** ไม่ส่ง = คงรูปเดิม · null = กลับไปใช้รูปวาด · uuid = รูปที่อัปโหลดเสร็จแล้ว */
  image_asset_id?: string | null
}

/** เพิ่ม (expectedVersion 0) หรือแก้ (version ที่โหลดมา) — request key เดิมเมื่อกดซ้ำ */
export const saveCharm = (
  charm: CharmInput,
  expectedVersion: number,
  requestKey: string,
  adminMode: boolean,
) =>
  run(
    supabase.rpc('save_charm', {
      p_charm: { ...charm },
      p_expected_version: expectedVersion,
      p_request_key: requestKey,
      p_admin_mode: adminMode,
    }),
    AdminCharmSchema,
  )
