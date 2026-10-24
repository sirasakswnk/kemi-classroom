import { queryOptions } from '@tanstack/react-query'
import { run } from '../../lib/request'
import { supabase } from '../../lib/supabase'
import { z } from '../../lib/zod'

// รางวัลของนักเรียน (S04 / เอฟเฟกต์ได้รับโทเคน) — RPC ของ 0036_wallet_ops และ 0037_draw
// อัตราที่แสดงคืออัตราจริงจากเซิร์ฟเวอร์ (K6) — หน้าเว็บไม่คำนวณอัตราเอง

const LevelSchema = z.object({
  rarity_id: z.number().int(),
  name: z.string(),
  weight: z.number().int(),
  total: z.number().int(),
  owned: z.number().int(),
  remaining: z.number().int(),
  /** โอกาสออกระดับนี้ (%) ปัด 2 ตำแหน่ง */
  pct: z.number(),
  /** โอกาสต่อชิ้นที่ยังไม่มี (%) */
  pct_each: z.number(),
})
export type DrawLevel = z.infer<typeof LevelSchema>

export const DRAW_STATUSES = ['ok', 'insufficient', 'completed', 'unavailable'] as const
export type DrawStatus = (typeof DRAW_STATUSES)[number]

const OptionsSchema = z.object({
  status: z.enum(DRAW_STATUSES),
  balance: z.number().int(),
  owned: z.number().int(),
  total: z.number().int(),
  /** ต้องส่งกลับใน draw_charm — อัตราเปลี่ยนแล้ว = stale_revision (ไม่สุ่มด้วยอัตราที่ไม่ได้แสดง) */
  rates_key: z.string(),
  levels: z.array(LevelSchema),
})
export type DrawOptions = z.infer<typeof OptionsSchema>

/** S04 + ยอดบนหัวเว็บ: ยอดโทเคนเทอมปัจจุบันและอัตราที่ใช้กับฉันตอนนี้ */
export const drawOptionsQuery = queryOptions({
  queryKey: ['draw-options'],
  queryFn: () => run(supabase.rpc('get_draw_options'), OptionsSchema),
  staleTime: 0,
  retry: false,
})

const CharmSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string(),
  symbol: z.string(),
  rarity_id: z.number().int(),
  rarity_name: z.string(),
  position: z.number().int(),
})
export type DrawnCharm = z.infer<typeof CharmSchema>

const DrawResultSchema = z.object({
  charm: CharmSchema,
  obtained_at: z.string(),
  balance: z.number().int(),
  version: z.number().int(),
})
export type DrawResult = z.infer<typeof DrawResultSchema>

/** สุ่ม 1 ครั้ง — request key เดิมเมื่อกดซ้ำหลังเน็ตหลุด (ได้ผลเดิม ไม่หักซ้ำ) */
export const drawCharm = (ratesKey: string, requestKey: string) =>
  run(
    supabase.rpc('draw_charm', { p_rates_key: ratesKey, p_request_key: requestKey }),
    DrawResultSchema,
  )

/** แสดงเครื่องรางชิ้นนี้ข้างชื่อ — null = ไม่แสดง (type ที่สร้างจาก CLI ไม่รู้ว่า null ได้ จึง cast) */
export const setEquipment = (charmId: string | null) =>
  run(
    supabase.rpc('set_equipment', { p_charm_id: charmId as string }),
    z.object({ charm_id: z.uuid().nullable() }),
  )

const EffectsSchema = z.object({
  tokens: z.number().int(),
  works: z.number().int(),
  submission_ids: z.array(z.uuid()),
})
export type RewardEffects = z.infer<typeof EffectsSchema>

/** โทเคนจากงานที่ได้รับแล้วแต่ยังไม่ได้ดูเอฟเฟกต์ (เฉพาะเทอมปัจจุบัน) */
export const rewardEffectsQuery = queryOptions({
  queryKey: ['reward-effects'],
  queryFn: () => run(supabase.rpc('reward_effects'), EffectsSchema),
  staleTime: 0,
  retry: false,
})

/** ตั้งว่าดูแล้วเฉพาะงานที่เอฟเฟกต์แสดงไป — รางวัลที่ได้ระหว่างแสดงยังค้างไว้แสดงครั้งหน้า */
export const markRewardEffectSeen = (submissionIds: string[]) =>
  run(
    supabase.rpc('mark_reward_effect_seen', { p_submission_ids: submissionIds }),
    z.object({ marked: z.number().int() }),
  )

const SlotSchema = z.discriminatedUnion('owned', [
  z.object({
    owned: z.literal(false),
    position: z.number().int(),
    rarity_id: z.number().int(),
    rarity_name: z.string(),
  }),
  z.object({
    owned: z.literal(true),
    position: z.number().int(),
    rarity_id: z.number().int(),
    rarity_name: z.string(),
    charm_id: z.uuid(),
    name: z.string(),
    description: z.string(),
    symbol: z.string(),
    obtained_at: z.string(),
    /** รูปที่ครูอัปโหลด (null = เหรียญวาด) — 0040 */
    image_asset_id: z.uuid().nullable(),
  }),
])
export type CollectionSlot = z.infer<typeof SlotSchema>
export type OwnedSlot = Extract<CollectionSlot, { owned: true }>

const CollectionSchema = z.object({
  total: z.number().int(),
  owned: z.number().int(),
  equipped_charm_id: z.uuid().nullable(),
  /** ช่องที่ยังไม่ได้รับมีแค่ลำดับและระดับ — เซิร์ฟเวอร์ไม่ส่งชื่อ/รูป/คำอธิบาย */
  items: z.array(SlotSchema),
})
export type Collection = z.infer<typeof CollectionSchema>

/** S05 ตู้สะสมส่วนตัว (0038) */
export const collectionQuery = queryOptions({
  queryKey: ['collection'],
  queryFn: () => run(supabase.rpc('my_collection'), CollectionSchema),
  staleTime: 0,
  retry: false,
})
