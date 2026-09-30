import {
  useEffect,
  useRef,
  type MouseEvent,
  type PointerEvent,
  type ReactNode,
  type RefObject,
} from 'react'
import { useScrollLock } from '../lib/useScrollLock'

// dialog ที่เปิดอยู่ เรียงจากล่างขึ้นบน — Esc มีผลกับตัวบนสุดเท่านั้น
const openStack: HTMLDialogElement[] = []

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
      if (e.key !== 'Escape' || openStack.at(-1) !== dialog) return
      e.preventDefault()
      e.stopPropagation()
      requestClose()
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
