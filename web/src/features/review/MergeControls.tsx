import { FileDown, Loader, RotateCcw, TriangleAlert } from 'lucide-react'
import { useId } from 'react'
import { th } from '../../copy/th'
import type { Merge } from './useMergePdf'
import styles from './review.module.css'

const copy = th.review.viewer.merge

/**
 * ปุ่ม “ดาวน์โหลด PDF” ต่อจากปุ่มหมุนในแถบเครื่องมือ (UX 9 [ยืนยัน 29 ก.ย.]): ชี้ที่ปุ่มเห็นชื่อไฟล์ที่จะได้ (title)
 * และอ่านออกเสียงด้วย aria-describedby; ระหว่างรวมเปลี่ยนเป็น “กำลังรวมไฟล์…” และกดซ้ำไม่ได้
 */
export function MergeButton({ merge, fileCount }: { merge: Merge; fileCount: number }) {
  const hintId = useId()
  const hint = copy.hint(merge.fileName, fileCount)
  return (
    <>
      <button
        type="button"
        className={styles.vt}
        title={hint}
        aria-describedby={hintId}
        aria-busy={merge.busy}
        disabled={merge.busy}
        onClick={merge.run}
      >
        {merge.busy ? (
          <Loader className={styles.spin} aria-hidden="true" />
        ) : (
          <FileDown aria-hidden="true" />
        )}
        {merge.busy ? copy.busy : copy.button}
      </button>
      <span id={hintId} className={styles.srOnly}>
        {hint}
      </span>
    </>
  )
}

/** ความคืบหน้า / คำถามเมื่อมีไฟล์เปิดไม่ได้ / ข้อผิดพลาด — อยู่ใต้แถบเครื่องมือ */
export function MergeNotice({ merge }: { merge: Merge }) {
  const v = merge.view
  if (v.phase === 'idle') return null
  if (v.phase === 'loading' || v.phase === 'merging') {
    return (
      <p className={styles.partial} role="status">
        <Loader className={styles.spin} aria-hidden="true" />
        <span>
          {v.total === 0
            ? copy.preparing
            : v.phase === 'loading'
              ? copy.loadingFile(v.done, v.total)
              : copy.mergingFile(v.done, v.total)}
        </span>
      </p>
    )
  }
  if (v.phase === 'ask') {
    return (
      <div className={styles.error} role="alertdialog" aria-label={copy.askAria}>
        <TriangleAlert aria-hidden="true" />
        <span>{copy.ask(v.failed, v.pages)}</span>
        <button type="button" className={styles.vt} onClick={merge.proceed}>
          {copy.proceed}
        </button>
        <button type="button" className={styles.vt} onClick={merge.dismiss}>
          {copy.cancel}
        </button>
      </div>
    )
  }
  if (v.phase === 'none') {
    return (
      <p className={styles.error} role="alert">
        <TriangleAlert aria-hidden="true" />
        <span>{v.failed.length > 0 ? copy.noneOpenable(v.failed) : copy.noFiles}</span>
        <button type="button" className={styles.vt} onClick={merge.dismiss}>
          {copy.close}
        </button>
      </p>
    )
  }
  return (
    <p className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {v.error.message}
        {v.error.ref && ` (${th.errors.reference(v.error.ref)})`}
      </span>
      <button type="button" className={styles.vt} onClick={merge.run}>
        <RotateCcw aria-hidden="true" />
        {copy.retry}
      </button>
    </p>
  )
}
