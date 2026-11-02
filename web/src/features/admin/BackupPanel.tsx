import { useQuery } from '@tanstack/react-query'
import { CheckCircle2, DatabaseBackup, History, TriangleAlert } from 'lucide-react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Chip } from '../../ui'
import { adminBackupRunsQuery } from './api'
import { backupStatus } from './backupStatus'
import styles from './AdminHome.module.css'

// D01 แผงสำรองข้อมูล (P7-03, แบบ v2 renderAdmin): สำรองสำเร็จล่าสุด รอบที่ล้มล่าสุด และทดสอบกู้คืนล่าสุด
// เตือนบนแผงอย่างเดียว ไม่ส่งกระดิ่ง (Healthchecks ส่งอีเมลผู้พัฒนาอยู่แล้ว)
export function BackupPanel() {
  const copy = th.admin.backup
  const runs = useQuery(adminBackupRunsQuery)

  if (runs.isPending) {
    return (
      <section className={styles.panel} aria-labelledby="backupTitle">
        <h2 id="backupTitle">{copy.title}</h2>
        <p className={styles.hint}>{th.common.loading}</p>
      </section>
    )
  }
  if (runs.isError) {
    return (
      <section className={styles.panel} aria-labelledby="backupTitle">
        <h2 id="backupTitle">{copy.title}</h2>
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.loadFailed} {appErrorOf(runs.error).message}
          </span>
        </p>
      </section>
    )
  }

  const s = backupStatus(runs.data)
  return (
    <section className={styles.panel} aria-labelledby="backupTitle">
      <h2 id="backupTitle">{copy.title}</h2>
      {s.backupStale && (
        <p className={styles.note} data-tone="amber" role="status">
          <TriangleAlert aria-hidden="true" />
          <span>{s.success ? copy.staleBackup : copy.neverBackup}</span>
        </p>
      )}
      {s.restoreStale && (
        <p className={styles.note} data-tone="amber" role="status">
          <TriangleAlert aria-hidden="true" />
          <span>{s.restore ? copy.staleRestore : copy.neverRestore}</span>
        </p>
      )}
      <ul className={styles.backupRows}>
        <li>
          <DatabaseBackup aria-hidden="true" />
          <span className={styles.backupText}>
            <b>{copy.successTitle}</b>
            {s.success ? (
              <>
                <span>
                  {s.success.when} · {s.success.age}
                </span>
                {s.success.files && <span>{s.success.files}</span>}
              </>
            ) : (
              <span>{copy.none}</span>
            )}
          </span>
        </li>
        <li>
          <TriangleAlert aria-hidden="true" />
          <span className={styles.backupText}>
            <b>{copy.failureTitle}</b>
            {s.failure ? (
              <span>
                {s.failure.when}
                {s.failure.step && ` · ${copy.step(s.failure.step)}`}
              </span>
            ) : (
              <span>{copy.noFailure}</span>
            )}
          </span>
          {s.failure?.afterSuccess && <Chip tone="amber">{copy.afterSuccess}</Chip>}
        </li>
        <li>
          {s.restore?.passed ? <CheckCircle2 aria-hidden="true" /> : <History aria-hidden="true" />}
          <span className={styles.backupText}>
            <b>{copy.restoreTitle}</b>
            {s.restore ? (
              <span>
                {s.restore.when}
                {s.restore.point && ` · ${copy.point(s.restore.point)}`} ·{' '}
                {copy.restoreFiles(s.restore.files)}
              </span>
            ) : (
              <span>{copy.noRestore}</span>
            )}
          </span>
          {s.restore && (
            <Chip tone={s.restore.passed ? 'green' : 'red'}>
              {s.restore.passed ? copy.passed : copy.failed}
            </Chip>
          )}
        </li>
      </ul>
      <p className={styles.hint}>{copy.how}</p>
    </section>
  )
}
