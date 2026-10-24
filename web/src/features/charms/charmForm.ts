import type { AdminCharm, CharmInput, Rarity } from './api'

// ตรรกะฟอร์ม T06 ที่ไม่พึ่ง React — กติกาจริงอยู่ใน RPC (หน้าเว็บตรวจก่อนเพื่อบอกผู้ใช้เร็ว)

export const NAME_MAX = 40
export const DESC_MAX = 120
/** ด้านของรูปเครื่องรางหลังตัดเป็นสี่เหลี่ยมจัตุรัส (px) */
export const CHARM_IMAGE_EDGE = 512

/** อัตราที่กรอก: ช่องว่าง/ไม่ใช่ตัวเลข = 0 */
export const weightOf = (text: string) => {
  const n = Number.parseInt(text, 10)
  return Number.isFinite(n) ? n : 0
}

export function ratesState(rarities: Rarity[], draft: Record<number, string>) {
  const weights = rarities.map((r) => ({ rarity_id: r.id, weight: weightOf(draft[r.id] ?? '') }))
  const sum = weights.reduce((a, w) => a + w.weight, 0)
  const valid = weights.every((w) => w.weight >= 0 && w.weight <= 100)
  const changed = rarities.some((r) => weightOf(draft[r.id] ?? '') !== r.weight)
  return { weights, sum, valid, changed, canSave: valid && changed && sum === 100 }
}

export type ImageChoice =
  { kind: 'keep' } | { kind: 'new'; assetId: string; previewUrl: string } | { kind: 'remove' }

export interface CharmDraft {
  id: string | null
  version: number
  name: string
  description: string
  rarityId: number
  image: ImageChoice
}

export const newDraft = (rarityId = 1): CharmDraft => ({
  id: null,
  version: 0,
  name: '',
  description: '',
  rarityId,
  image: { kind: 'keep' },
})

export const draftOf = (c: AdminCharm): CharmDraft => ({
  id: c.id,
  version: c.version,
  name: c.name,
  description: c.description,
  rarityId: c.rarity_id,
  image: { kind: 'keep' },
})

export function canSaveDraft(d: CharmDraft): boolean {
  const name = d.name.trim()
  return name.length > 0 && name.length <= NAME_MAX && d.description.trim().length <= DESC_MAX
}

/** ข้อมูลที่ส่ง save_charm — ไม่ส่ง image_asset_id เมื่อคงรูปเดิม */
export function toInput(d: CharmDraft): CharmInput {
  const input: CharmInput = {
    name: d.name.trim(),
    description: d.description.trim(),
    rarity_id: d.rarityId,
  }
  if (d.id) input.id = d.id
  if (d.image.kind === 'new') input.image_asset_id = d.image.assetId
  if (d.image.kind === 'remove') input.image_asset_id = null
  return input
}

/** สัญลักษณ์บนรูปวาดของตัวอย่างสด (เซิร์ฟเวอร์ใช้ตัวแรกของชื่อเมื่อเพิ่มใหม่) */
export const previewSymbol = (d: CharmDraft, current: AdminCharm | undefined) =>
  current?.symbol ?? (d.name.trim().slice(0, 1) || '★')

/** ส่วนสี่เหลี่ยมจัตุรัสตรงกลางของรูป (ตัดขอบด้านยาวเท่ากันสองข้าง) */
export function centerSquare(width: number, height: number) {
  const size = Math.min(width, height)
  return { sx: Math.floor((width - size) / 2), sy: Math.floor((height - size) / 2), size }
}
