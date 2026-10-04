import { Check, Copy, X } from 'lucide-react'
import { useEffect, useId, useRef, useState } from 'react'
import { BrandLogo } from '../../app/common/brand'
import { th } from '../../copy/th'
import { DialogBase } from '../../ui/DialogBase'
import { useToast } from '../../ui'
import styles from './CodeFullscreen.module.css'
import { leaveFullscreen } from './fullscreen'

// T10 รหัสชั้นเรียนเต็มจอ (UX 9): พื้นม่วงเข้ม ตัวอักษรครีมแยกช่องละตัวให้อ่านจากหลังห้อง + สามขั้นตอนเข้าห้อง
// Esc ปิด (ขณะเต็มจอ Esc ของเบราว์เซอร์ออกจากเต็มจอ → ปิดหน้านี้ด้วย) แล้วคืนโฟกัสที่ปุ่มรหัส
export function CodeFullscreen({
  open,
  onClose,
  name,
  code,
}: {
  open: boolean
  onClose: () => void
  name: string
  code: string
}) {
  const id = useId()
  const closeRef = useRef<HTMLButtonElement>(null)
  const [copied, setCopied] = useState(false)
  const toast = useToast()
  const onCloseRef = useRef(onClose)
  useEffect(() => {
    onCloseRef.current = onClose
  })

  // ออกจากเต็มจอ (Esc ของเบราว์เซอร์) = ปิด T10
  useEffect(() => {
    if (!open) return
    let wasFull = !!document.fullscreenElement
    const onChange = () => {
      if (document.fullscreenElement) wasFull = true
      else if (wasFull) onCloseRef.current()
    }
    document.addEventListener('fullscreenchange', onChange)
    return () => {
      document.removeEventListener('fullscreenchange', onChange)
      leaveFullscreen()
    }
  }, [open])

  useEffect(() => {
    if (!copied) return
    const t = setTimeout(() => setCopied(false), 1800)
    return () => clearTimeout(t)
  }, [copied])

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      toast(th.classrooms.full.copiedToast(code), { tone: 'success' })
    } catch {
      toast(th.classrooms.full.copyFailed(code))
    }
  }

  return (
    <DialogBase
      open={open}
      onClose={onClose}
      dismissible
      labelledBy={`${id}name`}
      describedBy={`${id}label`}
      initialFocusRef={closeRef}
      className={styles.full}
    >
      <div className={styles.inner}>
        <div className={styles.top}>
          <span className={styles.brand}>
            <BrandLogo />
            <span>{th.appName}</span>
          </span>
          <div className={styles.actions}>
            <button type="button" className={styles.copy} onClick={() => void copy()}>
              {copied ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}
              {copied ? th.classrooms.full.copied : th.classrooms.full.copy}
            </button>
            <button
              ref={closeRef}
              type="button"
              className={styles.close}
              aria-label={th.classrooms.full.close}
              onClick={onClose}
            >
              <X aria-hidden="true" />
            </button>
          </div>
        </div>
        <div className={styles.mid}>
          <h2 id={`${id}name`} className={styles.name}>
            {name}
          </h2>
          <p id={`${id}label`} className={styles.label}>
            {th.classrooms.full.label}
          </p>
          <p className={styles.code} aria-label={code.split('').join(' ')} role="img">
            {code.split('').map((ch, i) => (
              <i key={i} aria-hidden="true">
                {ch}
              </i>
            ))}
          </p>
          <ol className={styles.steps}>
            {th.classrooms.full.steps.map((s) => (
              <li key={s}>{s}</li>
            ))}
          </ol>
        </div>
      </div>
    </DialogBase>
  )
}
