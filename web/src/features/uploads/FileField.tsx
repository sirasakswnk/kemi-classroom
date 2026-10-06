import {
  ArrowDown,
  ArrowUp,
  FileText,
  Image as ImageIcon,
  Paperclip,
  RotateCcw,
  TriangleAlert,
  X,
} from 'lucide-react'
import { useId, useRef, useState, type ChangeEvent } from 'react'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { Button, Modal } from '../../ui'
import { ACCEPT, formatBytes } from './rules'
import type { AttachmentRef } from './AttachmentList'
import {
  useFileField,
  type FileFieldState,
  type FileFieldTarget,
  type FileItem,
} from './useFileField'
import styles from './uploads.module.css'

// ช่องไฟล์ของ T02 (ไฟล์โจทย์/ไฟล์แนบ) และ S03 (ไฟล์งาน — P3-08) — UX_DESIGN 6, 9 และแบบ v2 (.file-chip): ป้ายจำนวน/เพดาน, แถวไฟล์
// พร้อมตัวอย่างรูปจากเครื่อง ความคืบหน้า ข้อความติดไฟล์ ลองใหม่/นำออก และคำแนะนำเมื่อรวมเกิน 5 MB
// ทุกปุ่มกดได้ด้วยนิ้ว/คีย์บอร์ด ไม่มีปุ่มที่ต้อง hover (CLAUDE.md ส่วน 7)
export function FileField({
  kind,
  target,
  initial,
  onChange,
  error,
}: {
  kind: 'homework' | 'announcement' | 'submission'
  target: FileFieldTarget
  /** ไฟล์เดิมของโพสต์ (โหมดแก้ไข) — เปลี่ยนชุดเริ่มต้นให้ remount ด้วย key */
  initial?: AttachmentRef[]
  onChange?: (state: FileFieldState) => void
  /** ข้อความผิดพลาดจากเซิร์ฟเวอร์ของทั้งช่อง (post_file_unavailable, too_many_files, batch_too_large) */
  error?: string
}) {
  const copy = th.uploads
  const field = useFileField(target, { initial, onChange })
  const errorId = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const labelId = useId()
  const hintId = useId()
  const submission = kind === 'submission'
  const [preview, setPreview] = useState<FileItem | null>(null)

  const pick = (e: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? [])
    // ล้างค่าเพื่อให้เลือกไฟล์เดิมซ้ำได้หลังนำออก
    e.target.value = ''
    if (files.length) void field.add(files)
  }

  return (
    <div
      className={styles.group}
      role="group"
      aria-labelledby={labelId}
      aria-describedby={
        [submission && hintId, error && errorId].filter(Boolean).join(' ') || undefined
      }
    >
      <span id={labelId} className={styles.label}>
        {copy.label[kind]}{' '}
        <span className={styles.meta}>
          {submission ? copy.metaSubmission(field.count) : copy.meta(field.count)}
        </span>
      </span>
      {submission && (
        <p id={hintId} className={styles.hint}>
          {copy.submissionHint[0]}
          <br />
          {copy.submissionHint[1]}
        </p>
      )}
      {field.items.length > 0 && (
        <ul className={styles.rows}>
          {field.items.map((item, index) => (
            <FileRow
              key={item.id}
              item={item}
              first={index === 0}
              last={index === field.items.length - 1}
              onPreview={() => setPreview(item)}
              onRetry={() => field.retry(item.id)}
              onRemove={() => field.remove(item.id)}
              onMove={(delta) => field.move(item.id, delta)}
            />
          ))}
        </ul>
      )}
      {error && (
        <p id={errorId} className={styles.error} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{error}</span>
        </p>
      )}
      {field.largeSet && !submission && (
        <p className={styles.hint} role="note">
          {copy.largeSetHint}
        </p>
      )}
      <div className={styles.actions}>
        <Button
          variant="ghost"
          icon={<Paperclip />}
          disabled={field.full}
          onClick={() => inputRef.current?.click()}
        >
          {copy.add}
        </Button>
        {field.uploading && (
          <Button variant="ghost" size="sm" onClick={field.cancelAll}>
            {copy.cancelAll}
          </Button>
        )}
      </div>
      <input
        ref={inputRef}
        className="sr-only"
        type="file"
        accept={ACCEPT}
        multiple
        tabIndex={-1}
        aria-hidden="true"
        onChange={pick}
      />
      <Modal open={preview !== null} onClose={() => setPreview(null)} title={copy.previewTitle}>
        {preview?.previewUrl && (
          <figure className={styles.previewFig}>
            <img src={preview.previewUrl} alt={preview.name} className={styles.previewImg} />
            <figcaption>
              {preview.name}
              {preview.prepared && ` · ${formatBytes(preview.prepared.blob.size)}`}
            </figcaption>
          </figure>
        )}
      </Modal>
    </div>
  )
}

function statusText(item: FileItem): string {
  const copy = th.uploads
  switch (item.status) {
    case 'preparing':
      return copy.preparing
    case 'waiting':
      return copy.waiting
    case 'uploading':
      return copy.uploading(Math.round(item.progress * 100))
    case 'completing':
      return copy.completing
    case 'done':
      return copy.done
    case 'error':
      return ''
  }
}

function FileRow({
  item,
  first,
  last,
  onPreview,
  onRetry,
  onRemove,
  onMove,
}: {
  item: FileItem
  first: boolean
  last: boolean
  onPreview: () => void
  onRetry: () => void
  onRemove: () => void
  onMove: (delta: -1 | 1) => void
}) {
  const copy = th.uploads
  const pdf = item.kind === 'pdf'
  const size = item.prepared?.blob.size ?? item.sizeBytes
  const resized = item.prepared?.converted && item.sizeBytes !== item.prepared.blob.size
  const status = statusText(item)
  const errorId = useId()
  return (
    <li className={cx(styles.chip, item.status === 'error' && styles.chipError)}>
      {item.previewUrl ? (
        <button
          type="button"
          className={styles.thumb}
          onClick={onPreview}
          aria-label={copy.preview(item.name)}
        >
          <img src={item.previewUrl} alt="" />
        </button>
      ) : (
        <span className={cx(styles.fi, !pdf && styles.fiImg)} aria-hidden="true">
          {pdf ? <FileText /> : <ImageIcon />}
        </span>
      )}
      <span className={styles.text}>
        <b>{item.name}</b>
        <small>
          {pdf ? copy.kindPdf : copy.kindImage} · {formatBytes(size)}
          {resized && ` (${copy.resized(formatBytes(item.sizeBytes))})`}
          {status && (
            <span className={styles.status} aria-live="polite">
              {' · '}
              {status}
            </span>
          )}
        </small>
        {item.status === 'uploading' && (
          <span className={styles.bar} aria-hidden="true">
            <i style={{ width: `${Math.round(item.progress * 100)}%` }} />
          </span>
        )}
        {item.error && (
          <span id={errorId} className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{item.error}</span>
          </span>
        )}
      </span>
      <span className={styles.rowActions}>
        {!(first && last) && (
          <span className={styles.moveBtns}>
            <button
              type="button"
              className={styles.iconBtn}
              disabled={first}
              onClick={() => onMove(-1)}
              aria-label={copy.moveUp(item.name)}
            >
              <ArrowUp aria-hidden="true" />
            </button>
            <button
              type="button"
              className={styles.iconBtn}
              disabled={last}
              onClick={() => onMove(1)}
              aria-label={copy.moveDown(item.name)}
            >
              <ArrowDown aria-hidden="true" />
            </button>
          </span>
        )}
        {item.status === 'error' && item.retryable && (
          <Button variant="soft" size="sm" icon={<RotateCcw />} onClick={onRetry}>
            {copy.retry}
          </Button>
        )}
        <button
          type="button"
          className={styles.iconBtn}
          onClick={onRemove}
          aria-label={copy.remove(item.name)}
          aria-describedby={item.error ? errorId : undefined}
        >
          <X aria-hidden="true" />
        </button>
      </span>
    </li>
  )
}
