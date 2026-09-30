import { CircleCheck, Info } from 'lucide-react'
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { cx } from '../lib/cx'
import styles from './Toast.module.css'
import { ToastContext, type ShowToast, type ToastTone } from './toastContext'

interface ToastItem {
  id: number
  message: ReactNode
  tone: ToastTone
}

const MAX_VISIBLE = 3

// ช่องแสดง toast อยู่ในหน้าตลอด (role="status") เพื่อให้เครื่องอ่านหน้าจออ่านข้อความที่เพิ่มเข้ามา
// ไม่รับการแตะ (pointer-events: none) จึงไม่บังการกดปุ่มด้านล่าง;
// หน้าที่มีแถบปุ่มติดขอบล่างตั้ง --toast-offset เป็นความสูงของแถบนั้นเพื่อยก toast ขึ้นพ้นปุ่ม
export function ToastProvider({
  children,
  duration = 4000,
}: {
  children: ReactNode
  duration?: number
}) {
  const [items, setItems] = useState<ToastItem[]>([])
  const nextId = useRef(0)
  const timers = useRef(new Set<ReturnType<typeof setTimeout>>())

  useEffect(() => {
    const pending = timers.current
    return () => pending.forEach(clearTimeout)
  }, [])

  const show = useCallback<ShowToast>(
    (message, options) => {
      const id = ++nextId.current
      setItems((list) =>
        [...list, { id, message, tone: options?.tone ?? 'success' }].slice(-MAX_VISIBLE),
      )
      const timer = setTimeout(() => {
        timers.current.delete(timer)
        setItems((list) => list.filter((t) => t.id !== id))
      }, duration)
      timers.current.add(timer)
    },
    [duration],
  )

  return (
    <ToastContext value={show}>
      {children}
      <div className={styles.viewport} role="status" aria-live="polite">
        {items.map((t) => (
          <div key={t.id} className={cx(styles.toast, styles[t.tone])}>
            {t.tone === 'success' ? (
              <CircleCheck aria-hidden="true" />
            ) : (
              <Info aria-hidden="true" />
            )}
            <span>{t.message}</span>
          </div>
        ))}
      </div>
    </ToastContext>
  )
}
