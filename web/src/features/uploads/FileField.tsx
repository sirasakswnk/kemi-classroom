import { FileText, Image as ImageIcon, Paperclip, RotateCcw, TriangleAlert, X } from 'lucide-react'
import { useId, useRef, useState, type ChangeEvent } from 'react'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { Button, Modal } from '../../ui'
import { ACCEPT, formatBytes } from './rules'
import { useFileField, type FileFieldTarget, type FileItem } from './useFileField'
import styles from './uploads.module.css'

// ช่องไฟล์ของ T02 (ไฟล์โจทย์/ไฟล์แนบ) — UX_DESIGN 9 และแบบ v2 (.file-chip): ป้ายจำนวน/เพดาน, แถวไฟล์
// พร้อมตัวอย่างรูปจากเครื่อง ความคืบหน้า ข้อความติดไฟล์ ลองใหม่/นำออก และคำแนะนำเมื่อรวมเกิน 5 MB
// ทุกปุ่มกดได้ด้วยนิ้ว/คีย์บอร์ด ไม่มีปุ่มที่ต้อง hover (CLAUDE.md ส่วน 7)
export function FileField({
  kind,
  target,
  onAssetsChange,
  note,
}: {
  kind: 'homework' | 'announcement'
  target: FileFieldTarget
  onAssetsChange?: (assetIds: string[]) => void
  /** ข้อความเล็กใต้ป้าย (เช่นบอกว่าเป็นช่องทดลอง) */
  note?: string
}) {
  const copy = th.uploads
  const field = useFileField(target, onAssetsChange)
  const inputRef = useRef<HTMLInputElement>(null)
  const labelId = useId()
  const [preview, setPreview] = useState<FileItem | null>(null)

  const pick = (e: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? [])
    // ล้างค่าเพื่อให้เลือกไฟล์เดิมซ้ำได้หลังนำออก
    e.target.value = ''
    if (files.length) void field.add(files)
  }

  return (
    <div className={styles.group} role="group" aria-labelledby={labelId}>
      <span id={labelId} className={styles.label}>
        {copy.label[kind]} <span className={styles.meta}>{copy.meta(field.count)}</span>
      </span>
      {note && <p className={styles.note}>{note}</p>}
      {field.items.length > 0 && (
        <ul className={styles.rows}>
          {field.items.map((item) => (
            <FileRow
              key={item.id}
              item={item}
              onPreview={() => setPreview(item)}
              onRetry={() => field.retry(item.id)}
              onRemove={() => field.remove(item.id)}
            />
          ))}
        </ul>
      )}
      {field.largeSet && (
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
  onPreview,
  onRetry,
  onRemove,
}: {
  item: FileItem
  onPreview: () => void
  onRetry: () => void
  onRemove: () => void
}) {
  const copy = th.uploads
  const pdf = item.kind === 'pdf'
  const size = item.prepared?.blob.size ?? item.original.size
  const resized = item.prepared?.converted && item.original.size !== item.prepared.blob.size
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
          {resized && ` (${copy.resized(formatBytes(item.original.size))})`}
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
