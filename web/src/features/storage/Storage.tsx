import { useQuery } from '@tanstack/react-query'
import { HardDrive, Info, OctagonAlert, TriangleAlert } from 'lucide-react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import {
  adminB2UsageQuery,
  adminStorageReconcileQuery,
  adminTermAlertQuery,
  formatSize,
  storageStatusQuery,
  type StorageStatus,
} from './api'
import { adminStorageAlerts } from './adminAlerts'
import styles from './storage.module.css'

// พื้นที่เก็บไฟล์ (P3-10; UX 12 J10, J10.1–J10.3; แบบ v2 storePanel / store-bar / blocked-up)
// - StoragePanel: D01 ผู้ดูแล — แถบซ้อนตามชนิดไฟล์เทียบเพดานที่ใช้ได้ พร้อมเส้นเกณฑ์ + ตัวนับ B2 วันนี้ + งานเบื้องหลัง
// - TeacherStorageBar: หน้าครูทุกหน้า เมื่อถึงเกณฑ์ครู (เหลือง) หรือเต็ม (แดง)
// - UploadBlocked: S03 แทนกล่องเลือกไฟล์เมื่อเต็ม
// ไม่มีปุ่มหรือข้อความชวนอัปเกรดแพ็กเกจ (J10.4–J10.5)

const pct = (n: number | undefined) =>
  (n ?? 0).toLocaleString('th-TH', { maximumFractionDigits: 1 })

export function StoragePanel() {
  const storage = useQuery(storageStatusQuery)
  const usage = useQuery(adminB2UsageQuery)
  const copy = th.storage
  return (
    <section className={styles.panel} aria-labelledby="storageTitle">
      <h2 id="storageTitle">{copy.title}</h2>
      {storage.isPending ? (
        <p className={styles.hint}>{th.common.loading}</p>
      ) : storage.isError ? (
        <p className={styles.note} data-tone="red" role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.loadFailed} {appErrorOf(storage.error).message}
          </span>
        </p>
      ) : (
        <Meter s={storage.data} />
      )}
      <h3>{copy.b2Title}</h3>
      {usage.isPending ? (
        <p className={styles.hint}>{th.common.loading}</p>
      ) : usage.isError ? (
        <p className={styles.note} data-tone="red" role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.loadFailed} {appErrorOf(usage.error).message}
          </span>
        </p>
      ) : (
        <>
          <table className={styles.table}>
            <thead>
              <tr>
                <th scope="col">{copy.cols.source}</th>
                <th scope="col">{copy.cols.requests}</th>
                <th scope="col">{copy.cols.bytes}</th>
                <th scope="col">{copy.cols.copy}</th>
              </tr>
            </thead>
            <tbody>
              {(['view', 'complete', 'backup'] as const).map((k) => {
                const row = usage.data.sources[k]
                return (
                  <tr key={k}>
                    <th scope="row">{copy.sources[k]}</th>
                    <td>{(row?.class_b_requests ?? 0).toLocaleString('th-TH')}</td>
                    <td>{formatSize(row?.download_bytes ?? 0)}</td>
                    <td>{formatSize(row?.copy_bytes ?? 0)}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          <p className={styles.hint}>
            {copy.viewBudget(
              usage.data.sources.view?.class_b_requests ?? 0,
              usage.data.view_budget_requests,
              formatSize(usage.data.sources.view?.download_bytes ?? 0),
              formatSize(usage.data.view_budget_bytes),
            )}
          </p>
          <p className={styles.hint}>{copy.b2Hint}</p>
          {usage.data.reconcile_budget_requests != null && (
            <p className={styles.hint}>
              {copy.reconcileBudget(
                usage.data.sources.reconcile?.class_c_requests ?? 0,
                usage.data.reconcile_budget_requests,
                usage.data.reconcile_run_max_requests ?? 0,
              )}
            </p>
          )}
          <p className={styles.hint}>
            {copy.jobs(usage.data.jobs.pending + usage.data.jobs.running, usage.data.jobs.failed)}
          </p>
        </>
      )}
    </section>
  )
}

function Meter({ s }: { s: StorageStatus }) {
  const copy = th.storage
  const limit = s.limit_bytes ?? 1
  const parts = [
    ['submission', s.by_purpose?.submission ?? 0],
    ['post', s.by_purpose?.post ?? 0],
    ['solution', s.by_purpose?.solution ?? 0],
    ['charm', s.by_purpose?.charm ?? 0],
    ['deleting', s.deleting_bytes ?? 0],
    ['reserved', Math.max(0, s.reserved_bytes ?? 0)],
  ] as const
  const used = s.used_bytes ?? 0
  const width = (v: number) => `${Math.min(100, (v / limit) * 100)}%`
  const tone = s.level === 'full' ? 'red' : s.level === 'ok' ? 'plain' : 'amber'
  const Icon = s.level === 'full' ? OctagonAlert : s.level === 'ok' ? Info : TriangleAlert
  const note =
    s.level === 'ok'
      ? copy.levelNote.ok
      : s.level === 'full'
        ? copy.levelNote.full
        : copy.levelNote[s.level](pct(s.percent))
  return (
    <div className={styles.meterBox}>
      <b className={styles.big}>
        {copy.usedOf(formatSize(used), formatSize(limit), pct(s.percent))}
      </b>
      <div className={styles.meter} role="img" aria-label={copy.meterAria(pct(s.percent))}>
        {parts.map(([k, v]) =>
          v > 0 ? <i key={k} data-part={k} style={{ width: width(v) }} /> : null,
        )}
        <span className={styles.mark} style={{ left: `${s.admin_warn_pct ?? 80}%` }} />
        <span
          className={styles.mark}
          data-teacher
          style={{ left: `${s.teacher_warn_pct ?? 90}%` }}
        />
      </div>
      <ul className={styles.legend}>
        {parts.map(([k, v]) => (
          <li key={k}>
            <i data-part={k} aria-hidden="true" />
            <span>{copy.parts[k]}</span>
            <b>{formatSize(v)}</b>
          </li>
        ))}
        <li>
          <i data-part="free" aria-hidden="true" />
          <span>{copy.parts.free}</span>
          <b>{formatSize(Math.max(0, limit - used))}</b>
        </li>
      </ul>
      <p className={styles.note} data-tone={tone}>
        <Icon aria-hidden="true" />
        <span>{note}</span>
      </p>
      <p className={styles.hint}>
        {copy.thresholds(s.admin_warn_pct ?? 80, s.teacher_warn_pct ?? 90)}
      </p>
      <p className={styles.hint}>
        {copy.limitHint(formatSize(s.quota_bytes ?? 0), formatSize((s.quota_bytes ?? 0) - limit))}
      </p>
    </div>
  )
}

/** D01: แถบเตือนบนสุด — พื้นที่ถึงเกณฑ์ผู้ดูแลขึ้นไป ธงยอด B2 ต่างเกินเกณฑ์ และภาคเรียนเปิดเกิน 6 เดือน (adminAlerts) */
export function AdminStorageAlerts() {
  const storage = useQuery(storageStatusQuery)
  const reconcile = useQuery(adminStorageReconcileQuery)
  const term = useQuery(adminTermAlertQuery)
  const alerts = adminStorageAlerts(storage.data, reconcile.data, new Date(), term.data)
  if (alerts.length === 0) return null
  return (
    <div className={styles.alerts} aria-label={th.storage.adminAlert.aria}>
      {alerts.map((a) => (
        <div key={a.key} className={styles.bar} data-tone={a.tone} role="status">
          {a.tone === 'red' ? (
            <OctagonAlert aria-hidden="true" />
          ) : (
            <TriangleAlert aria-hidden="true" />
          )}
          <span>
            <b>{a.title}</b> {a.body}
          </span>
        </div>
      ))}
    </div>
  )
}

/** แถบเตือนบนหน้าครูทุกหน้า (J10.1, J10.3) — ไม่แสดงเมื่อยังไม่ถึงเกณฑ์ครู */
export function TeacherStorageBar() {
  const storage = useQuery(storageStatusQuery)
  const s = storage.data
  if (!s || (s.level !== 'teacher_warn' && s.level !== 'full')) return null
  const copy = th.storage
  const full = s.level === 'full'
  return (
    <div className={styles.bar} data-tone={full ? 'red' : 'amber'} role="status">
      <HardDrive aria-hidden="true" />
      <span>
        <b>{full ? copy.teacherFull : copy.teacherWarn(pct(s.percent))}</b>{' '}
        {full ? copy.teacherFullBody : copy.teacherWarnBody}
      </span>
    </div>
  )
}

/** S03: กล่องแทนช่องเลือกไฟล์เมื่อพื้นที่เต็ม (J10.3) */
export function UploadBlocked() {
  const copy = th.storage
  return (
    <div className={styles.blocked} role="status">
      <HardDrive aria-hidden="true" />
      <b>{copy.blockedTitle}</b>
      <span>{copy.blockedBody}</span>
      <small>{copy.blockedSub}</small>
    </div>
  )
}
