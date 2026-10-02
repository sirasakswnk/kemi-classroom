import { X } from 'lucide-react'
import { useId, type ReactNode, type RefObject } from 'react'
import { th } from '../copy/th'
import { cx } from '../lib/cx'
import { DialogBase } from './DialogBase'
import styles from './Dialog.module.css'

export interface SheetProps {
  open: boolean
  onClose: () => void
  title: ReactNode
  description?: ReactNode
  /** false = ปิดเองไม่ได้ ไม่มีปุ่ม X (A02: ยังไม่ปิดจนผูกชื่อสำเร็จ — UX 4) */
  dismissible?: boolean
  /** center = การ์ดประกาศผลแบบแบบ v2, start = แผ่นที่มีฟอร์ม/รายการ (.sheet.pick) */
  align?: 'center' | 'start'
  initialFocusRef?: RefObject<HTMLElement | null>
  children?: ReactNode
}

// แผ่นเลื่อนจากขอบล่างบนมือถือ; ตั้งแต่ 768 px แสดงเป็นแผ่นลอยกลางจอ
export function Sheet({
  open,
  onClose,
  title,
  description,
  dismissible = true,
  align = 'center',
  initialFocusRef,
  children,
}: SheetProps) {
  const id = useId()
  return (
    <DialogBase
      open={open}
      onClose={onClose}
      dismissible={dismissible}
      labelledBy={`${id}title`}
      describedBy={description ? `${id}desc` : undefined}
      initialFocusRef={initialFocusRef}
      className={cx(styles.sheet, align === 'start' && styles.start)}
    >
      <div className={styles.handle} aria-hidden="true" />
      {dismissible && (
        <button
          type="button"
          className={styles.close}
          aria-label={th.dialog.close}
          onClick={onClose}
        >
          <X aria-hidden="true" />
        </button>
      )}
      <h2 id={`${id}title`} className={styles.sheetTitle}>
        {title}
      </h2>
      {description && (
        <p id={`${id}desc`} className={styles.sheetDesc}>
          {description}
        </p>
      )}
      {children && <div className={styles.sheetBody}>{children}</div>}
    </DialogBase>
  )
}
