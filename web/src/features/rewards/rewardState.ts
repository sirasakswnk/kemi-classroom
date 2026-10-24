import { th } from '../../copy/th'
import type { DrawOptions } from './api'

// สถานะที่ S04 แสดง — คิดจากผลของเซิร์ฟเวอร์ (status) เท่านั้น ไม่คิดกติกาการสุ่มเอง

const copy = th.rewards

/** เปอร์เซ็นต์ตามแบบ v2: ทศนิยม 1 ตำแหน่ง ตัด .0 เช่น 60% · 33.3% */
export const fmtPct = (v: number) => `${(Math.round(v * 10) / 10).toString().replace(/\.0$/, '')}%`

/** ปุ่มสุ่มและเหตุผลใต้ปุ่ม (UX 11): ครบแล้ว / ของที่เหลือน้ำหนัก 0 / ยอดไม่พอ / สุ่มได้ */
export function drawButton(
  options: Pick<DrawOptions, 'status'>,
  drawing: boolean,
): { label: string; disabled: boolean; why: string | null } {
  if (drawing) return { label: copy.drawing, disabled: true, why: null }
  switch (options.status) {
    case 'completed':
      return { label: copy.completed, disabled: true, why: copy.whyCompleted }
    case 'unavailable':
      return { label: copy.unavailableBtn, disabled: true, why: copy.whyUnavailable }
    case 'insufficient':
      return { label: copy.draw, disabled: true, why: copy.whyInsufficient }
    default:
      return { label: copy.draw, disabled: false, why: null }
  }
}

/** สัดส่วนที่ครูตั้ง เช่น “60 / 25 / 10 / 5” */
export const weightsText = (options: Pick<DrawOptions, 'levels'>) =>
  options.levels.map((l) => l.weight).join(' / ')

/** สีของระดับ 0–3 (ทั่วไป · หายาก · พิเศษ · ตำนาน) จาก rarities.id 1–4 */
export const tierOf = (rarityId: number) => Math.min(3, Math.max(0, rarityId - 1))

/** ข้อความผิดพลาดตอนสุ่ม — stale_revision ของ S04 ใช้ข้อความเฉพาะ; ยอดไม่พอต่อท้ายยอดล่าสุดเมื่อโหลดแล้ว */
export function drawErrorText(code: string | null, message: string, latest: number | null): string {
  if (code === 'stale_revision') return copy.staleRates
  if (code === 'insufficient_balance' && latest !== null)
    return `${message} ${th.rosterList.wallet.latest(latest)}`
  return message
}

/** รหัสที่ทำให้ต้องโหลดตัวเลือกสุ่มใหม่ (สถานะ/อัตรา/ยอดเปลี่ยน) — อย่างอื่น (เน็ตหลุด) กดลองใหม่ด้วย key เดิม */
export const reloadsOptions = (code: string | null) =>
  code === 'stale_revision' ||
  code === 'insufficient_balance' ||
  code === 'draw_completed' ||
  code === 'draw_unavailable'
