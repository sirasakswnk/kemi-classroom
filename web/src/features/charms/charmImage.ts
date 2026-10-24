import { th } from '../../copy/th'
import { CHARM_IMAGE_EDGE, centerSquare } from './charmForm'

// เตรียมรูปเครื่องราง: PNG/JPG เท่านั้น → ตัดเป็นสี่เหลี่ยมจัตุรัสตรงกลาง → ย่อ 512×512 → PNG (คงพื้นโปร่งใส,
// วาดใหม่บน canvas จึงไม่มีข้อมูล EXIF ติดไป)

export class CharmImageError extends Error {}

const ACCEPT = ['image/png', 'image/jpeg']
/** รูปต้นฉบับไม่เกิน 20 MB (J5) */
const MAX_ORIGINAL = 20 * 1024 * 1024

export async function prepareCharmImage(file: File): Promise<Blob> {
  if (!ACCEPT.includes(file.type)) throw new CharmImageError(th.charms.imageType)
  if (file.size > MAX_ORIGINAL) throw new CharmImageError(th.uploads.imageUnreadable)
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  } catch {
    throw new CharmImageError(th.uploads.imageUnreadable)
  }
  try {
    const { sx, sy, size } = centerSquare(bitmap.width, bitmap.height)
    const edge = Math.min(CHARM_IMAGE_EDGE, size)
    const canvas = document.createElement('canvas')
    canvas.width = edge
    canvas.height = edge
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new CharmImageError(th.uploads.imageUnreadable)
    ctx.imageSmoothingQuality = 'high'
    ctx.drawImage(bitmap, sx, sy, size, size, 0, 0, edge, edge)
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
    if (!blob) throw new CharmImageError(th.uploads.imageUnreadable)
    return blob
  } finally {
    bitmap.close()
  }
}
