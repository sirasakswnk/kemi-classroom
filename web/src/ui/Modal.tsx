import { X } from 'lucide-react'
import { useId, type ReactNode, type RefObject } from 'react'
import { th } from '../copy/th'
import { DialogBase } from './DialogBase'
import styles from './Dialog.module.css'

export interface ModalProps {
  open: boolean
  onClose: () => void
  title: ReactNode
  description?: ReactNode
  /** ไอคอนในกรอบม่วงหน้าหัวเรื่อง (แบบ v2 .tm-ic) */
  icon?: ReactNode
  /** ปุ่มท้ายกล่อง เช่น ยกเลิก/ยืนยัน */
  footer?: ReactNode
  /** false = ปิดเองไม่ได้ ไม่มีปุ่ม X */
  dismissible?: boolean
  initialFocusRef?: RefObject<HTMLElement | null>
  children?: ReactNode
}

// กล่องยืนยันกลางจอ (แบบ v2 .t-modal)
export function Modal({
  open,
  onClose,
  title,
  description,
  icon,
  footer,
  dismissible = true,
  initialFocusRef,
  children,
}: ModalProps) {
  const id = useId()
  return (
    <DialogBase
      open={open}
      onClose={onClose}
      dismissible={dismissible}
      labelledBy={`${id}title`}
      describedBy={description ? `${id}desc` : undefined}
      initialFocusRef={initialFocusRef}
      className={styles.modal}
    >
      <div className={styles.modalHead}>
        {icon && (
          <span className={styles.modalIcon} aria-hidden="true">
            {icon}
          </span>
        )}
        <div className={styles.modalHeadText}>
          <h2 id={`${id}title`}>{title}</h2>
          {description && <p id={`${id}desc`}>{description}</p>}
        </div>
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
      </div>
      {children && <div className={styles.modalBody}>{children}</div>}
      {footer && <div className={styles.modalFoot}>{footer}</div>}
    </DialogBase>
  )
}
