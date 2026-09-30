import { CircleCheck, Info } from 'lucide-react'
import {
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactNode,
} from 'react'
import { cx } from '../lib/cx'
import { subscribeDialogs, topDialog } from './dialogStack'
import styles from './Toast.module.css'
import { ToastContext, ToastItemsContext, type ShowToast, type ToastItem } from './toastContext'

const MAX_VISIBLE = 3

// ช่องแสดง toast (role="status") มีอยู่ในหน้าตลอด และมีอีกช่องในกล่องที่เปิดอยู่แต่ละกล่อง
// รายการ toast แสดงในช่องที่ "ใช้งาน" เพียงช่องเดียว: กล่องบนสุด หรือหน้าหลักเมื่อไม่มีกล่องเปิด
// — กล่องอยู่ใน top layer และทำให้ส่วนอื่นเป็น inert; toast ในกล่องจึงมองเห็นได้และเครื่องอ่านหน้าจอยังอ่าน
// ไม่รับการแตะ (pointer-events: none) จึงไม่บังการกดปุ่มด้านล่าง;
// หน้าที่มีแถบปุ่มติดขอบล่างตั้ง --toast-offset เป็นความสูงของแถบนั้นเพื่อยก toast ขึ้นพ้นปุ่ม
export function ToastViewport({ active }: { active: boolean }) {
  const items = useContext(ToastItemsContext)
  return (
    <div className={styles.viewport} role="status" aria-live="polite">
      {active &&
        items.map((t) => (
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
  )
}

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
  const anyDialogOpen = useSyncExternalStore(
    subscribeDialogs,
    () => topDialog() !== null,
    () => false,
  )

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
      <ToastItemsContext value={items}>
        {children}
        <ToastViewport active={!anyDialogOpen} />
      </ToastItemsContext>
    </ToastContext>
  )
}
