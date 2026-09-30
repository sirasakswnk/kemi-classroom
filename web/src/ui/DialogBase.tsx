import {
  useEffect,
  useRef,
  type MouseEvent,
  type PointerEvent,
  type ReactNode,
  type RefObject,
} from 'react'
import { useScrollLock } from '../lib/useScrollLock'

// dialog ที่เปิดอยู่ เรียงจากล่างขึ้นบน — Esc/Tab มีผลกับตัวบนสุดเท่านั้น
const openStack: HTMLDialogElement[] = []

const TABBABLE =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

// องค์ประกอบที่ Tab ไปถึงได้และมองเห็นอยู่
function tabbables(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(TABBABLE)].filter(
    (el) => el.tabIndex >= 0 && el.getClientRects().length > 0,
  )
}

export interface DialogBaseProps {
  open: boolean
  onClose: () => void
  /** false = ปิดด้วย Esc/แตะพื้นหลังไม่ได้ และไม่มีปุ่ม X (เช่น A02 เลือกชื่อ) */
  dismissible: boolean
  labelledBy: string
  describedBy?: string
  initialFocusRef?: RefObject<HTMLElement | null>
  className: string
  children: ReactNode
}

// ใช้ <dialog>.showModal(): หน้าด้านหลังถูก inert โฟกัสจึงอยู่ด้านในเสมอ (UX 13)
// Esc: ดักที่ keydown ระดับเอกสารแล้ว preventDefault เพื่อไม่ให้เบราว์เซอร์ส่งคำขอปิดเอง
//   (Chrome อาจข้าม cancel ที่ถูกยกเลิกซ้ำเมื่อกด Esc ครั้งที่สองโดยไม่มีการกระทำอื่นคั่น)
// ถ้าเบราว์เซอร์ยังปิดเองได้ (เช่นปุ่มย้อนกลับของ Android) แบบปิดไม่ได้จะเปิดกลับทันที
export function DialogBase({
  open,
  onClose,
  dismissible,
  labelledBy,
  describedBy,
  initialFocusRef,
  className,
  children,
}: DialogBaseProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const onCloseRef = useRef(onClose)
  const dismissibleRef = useRef(dismissible)
  const pressedBackdrop = useRef(false)

  useEffect(() => {
    onCloseRef.current = onClose
    dismissibleRef.current = dismissible
  })

  useScrollLock(open)

  useEffect(() => {
    const dialog = ref.current
    if (!open || !dialog) return

    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    if (!dialog.open) dialog.showModal()
    initialFocusRef?.current?.focus()
    openStack.push(dialog)

    const requestClose = () => {
      if (dismissibleRef.current) onCloseRef.current()
    }
    const onKeyDown = (e: KeyboardEvent) => {
      if (openStack.at(-1) !== dialog) return
      if (e.key === 'Escape') {
        e.preventDefault()
        e.stopPropagation()
        requestClose()
      } else if (e.key === 'Tab') {
        // วนโฟกัสในกล่อง (WAI-ARIA APG) — <dialog> เองปล่อยให้ Tab หลุดไปแถบเบราว์เซอร์หนึ่งจังหวะ
        const items = tabbables(dialog)
        if (items.length === 0) return
        const first = items[0]
        const last = items[items.length - 1]
        const active = document.activeElement
        const inside = active instanceof Node && dialog.contains(active)
        if (e.shiftKey && (!inside || active === first)) {
          e.preventDefault()
          last.focus()
        } else if (!e.shiftKey && (!inside || active === last)) {
          e.preventDefault()
          first.focus()
        }
      }
    }
    const onCancel = (e: Event) => {
      e.preventDefault()
      requestClose()
    }
    const onNativeClose = () => {
      // เบราว์เซอร์ปิดเองขณะที่ open ยังเป็น true
      if (dismissibleRef.current) onCloseRef.current()
      else dialog.showModal()
    }

    document.addEventListener('keydown', onKeyDown, true)
    dialog.addEventListener('cancel', onCancel)
    dialog.addEventListener('close', onNativeClose)
    return () => {
      document.removeEventListener('keydown', onKeyDown, true)
      dialog.removeEventListener('cancel', onCancel)
      dialog.removeEventListener('close', onNativeClose)
      openStack.splice(openStack.indexOf(dialog), 1)
      if (dialog.open) dialog.close()
      // คืนโฟกัสจุดเดิม (UX 13)
      if (opener?.isConnected) opener.focus()
    }
  }, [open, initialFocusRef])

  // แตะพื้นหลัง (::backdrop) = คลิกที่ตัว dialog นอกกรอบ — ต้องเริ่มกดและปล่อยที่พื้นหลังทั้งคู่
  const isBackdrop = (e: PointerEvent<HTMLDialogElement> | MouseEvent<HTMLDialogElement>) => {
    if (e.target !== e.currentTarget) return false
    const r = e.currentTarget.getBoundingClientRect()
    return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom
  }

  return (
    <dialog
      ref={ref}
      className={className}
      aria-labelledby={labelledBy}
      aria-describedby={describedBy}
      onPointerDown={(e) => {
        pressedBackdrop.current = isBackdrop(e)
      }}
      onClick={(e) => {
        if (pressedBackdrop.current && isBackdrop(e) && dismissibleRef.current) onCloseRef.current()
        pressedBackdrop.current = false
      }}
    >
      {open && children}
    </dialog>
  )
}
