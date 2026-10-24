import { th } from '../../copy/th'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { formatSize, type StorageReconcile, type StorageStatus } from './api'

// แถบเตือนบนสุดของ D01 (P6-04b, J10.1): ตามสถานะปัจจุบัน ไม่ใช่ประวัติ
// - พื้นที่ถึง admin_warn_pct ขึ้นไป (80% / 90% / เต็ม) — ผู้ดูแลไม่มีกระดิ่ง จึงเห็นที่หน้านี้เท่านั้น
// - ผลเทียบ B2 ล่าสุดมีธงยอดต่างเกินเกณฑ์ (0049: ≥ 5% หรือ ≥ 200 MB)

export interface AdminAlert {
  key: 'storage' | 'reconcile'
  tone: 'amber' | 'red'
  title: string
  body: string
}

const pct = (n: number | undefined) =>
  (n ?? 0).toLocaleString('th-TH', { maximumFractionDigits: 1 })

export function adminStorageAlerts(
  status: StorageStatus | undefined,
  reconcile: StorageReconcile | undefined,
  now: Date = new Date(),
): AdminAlert[] {
  const copy = th.storage.adminAlert
  const out: AdminAlert[] = []
  if (status && status.level !== 'ok') {
    const a = status.admin_warn_pct ?? 80
    const t = status.teacher_warn_pct ?? 90
    out.push(
      status.level === 'full'
        ? { key: 'storage', tone: 'red', title: copy.full, body: copy.fullBody }
        : {
            key: 'storage',
            tone: 'amber',
            title: copy.used(pct(status.percent)),
            body: status.level === 'admin_warn' ? copy.adminWarnBody(a, t) : copy.teacherWarnBody,
          },
    )
  }
  if (reconcile?.exceeds_threshold) {
    const when = `${thaiDate(reconcile.finished_at, now)} ${thaiTime(reconcile.finished_at)} น.`
    out.push({
      key: 'reconcile',
      tone: 'amber',
      title: copy.diff(formatSize(Math.abs(reconcile.diff_bytes))),
      body: reconcile.diff_bytes > 0 ? copy.diffMore(when) : copy.diffLess(when),
    })
  }
  return out
}
