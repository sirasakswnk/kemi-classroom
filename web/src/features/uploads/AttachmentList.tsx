import { useQueryClient } from '@tanstack/react-query'
import { Download, Eye, FileText, Image as ImageIcon, TriangleAlert } from 'lucide-react'
import { useId, useState } from 'react'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { signedFileOptions, type FileMode } from '../../lib/files'
import { appErrorOf } from '../../lib/request'
import { Button } from '../../ui'
import { formatBytes } from './rules'
import styles from './uploads.module.css'

export interface AttachmentRef {
  asset_id: string
  file_name: string
  content_type: string
  size_bytes: number
}

// รายการไฟล์แนบที่เปิดดู/ดาวน์โหลดได้ — แบบ v2 fileChip(f, act) (.file-chip.dl) และ UX_DESIGN ส่วน 8 (S03 แถวไฟล์)
// ขอลิงก์ (POST /files/sign) เมื่อกดเท่านั้น ผ่านแคชเดียวกับ useSignedFile — กดซ้ำภายในอายุลิงก์ไม่ขอใหม่/ไม่นับงบ
//   เปิดดู: ลิงก์ inline ในแท็บใหม่ (เปิดแท็บว่างทันทีตอนกด แล้วจึงใส่ลิงก์ — ไม่โดนตัวกันป๊อปอัปของ Safari)
//   ดาวน์โหลด: ลิงก์ attachment (ชื่อไฟล์ไทยจาก filename*) — เบราว์เซอร์ดาวน์โหลดโดยไม่ออกจากหน้า
// ข้อผิดพลาด (เช่นครบโควตาของวัน) แสดงใต้แถวไฟล์นั้น (UX 7.1)
export function AttachmentList({ files }: { files: AttachmentRef[] }) {
  const copy = th.files
  const hintId = useId()
  return (
    <div className={styles.attachments}>
      <ul className={styles.rows} aria-describedby={hintId}>
        {files.map((f) => (
          <AttachmentRow key={f.asset_id} file={f} />
        ))}
      </ul>
      <p id={hintId} className={styles.listHint}>
        {copy.listHint}
      </p>
    </div>
  )
}

function AttachmentRow({ file }: { file: AttachmentRef }) {
  const copy = th.files
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState<FileMode | null>(null)
  const [error, setError] = useState<string | null>(null)
  const pdf = file.content_type === 'application/pdf'

  const open = async (mode: FileMode) => {
    if (busy) return
    setError(null)
    setBusy(mode)
    const win = mode === 'view' ? window.open('', '_blank') : null
    try {
      const signed = await queryClient.fetchQuery(signedFileOptions(file.asset_id, mode))
      if (mode === 'view') {
        if (win) {
          win.opener = null
          win.location.replace(signed.url)
        } else {
          window.open(signed.url, '_blank', 'noopener')
        }
      } else {
        const a = document.createElement('a')
        a.href = signed.url
        a.rel = 'noopener'
        document.body.append(a)
        a.click()
        a.remove()
      }
    } catch (e) {
      win?.close()
      const err = appErrorOf(e)
      setError(err.message + (err.ref ? ` (${th.errors.reference(err.ref)})` : ''))
    } finally {
      setBusy(null)
    }
  }

  return (
    <li className={cx(styles.chip, error && styles.chipError)}>
      <span className={cx(styles.fi, !pdf && styles.fiImg)} aria-hidden="true">
        {pdf ? <FileText /> : <ImageIcon />}
      </span>
      <span className={styles.text}>
        <b>{file.file_name}</b>
        <small>
          {pdf ? th.uploads.kindPdf : th.uploads.kindImage} · {formatBytes(file.size_bytes)}
        </small>
        {error && (
          <span className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{error}</span>
          </span>
        )}
      </span>
      <span className={styles.rowActions}>
        <Button
          variant="ghost"
          size="sm"
          icon={<Eye />}
          aria-label={copy.viewAria(file.file_name)}
          aria-busy={busy === 'view' || undefined}
          onClick={() => void open('view')}
        >
          {copy.view}
        </Button>
        <button
          type="button"
          className={styles.iconBtn}
          aria-label={copy.download(file.file_name)}
          aria-busy={busy === 'download' || undefined}
          onClick={() => void open('download')}
        >
          <Download aria-hidden="true" />
        </button>
      </span>
    </li>
  )
}
