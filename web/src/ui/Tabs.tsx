import { useId, useRef, type KeyboardEvent, type ReactNode } from 'react'
import { cx } from '../lib/cx'
import styles from './Tabs.module.css'

export interface TabItem<K extends string> {
  key: K
  label: string
  /** ป้ายเล็กข้างชื่อแท็บ เช่น “ใหม่” — มีจุดพร้อมคำ ไม่ใช้สีอย่างเดียว (UX 5) */
  badge?: string
}

export interface TabsProps<K extends string> {
  /** ชื่อกลุ่มแท็บสำหรับเครื่องอ่านหน้าจอ */
  label: string
  tabs: readonly TabItem<K>[]
  selected: K
  onSelect: (key: K) => void
  className?: string
  /** เนื้อหาของแท็บที่เลือก */
  children: ReactNode
}

// แท็บแบบเลือกทันที (WAI-ARIA APG Tabs): ลูกศรซ้าย/ขวา Home End เลือกแล้วย้ายโฟกัส, แผงรับโฟกัสด้วย Tab ได้
// แบบ v2 .tabs/.tab (ปุ่มทรงแคปซูล แท็บที่เลือกพื้นเข้ม)
export function Tabs<K extends string>({
  label,
  tabs,
  selected,
  onSelect,
  className,
  children,
}: TabsProps<K>) {
  const id = useId()
  const refs = useRef(new Map<K, HTMLButtonElement | null>())

  const onKeyDown = (e: KeyboardEvent) => {
    const at = tabs.findIndex((t) => t.key === selected)
    const n = tabs.length
    const to =
      e.key === 'ArrowRight'
        ? (at + 1) % n
        : e.key === 'ArrowLeft'
          ? (at + n - 1) % n
          : e.key === 'Home'
            ? 0
            : e.key === 'End'
              ? n - 1
              : null
    if (to === null) return
    e.preventDefault()
    const next = tabs[to].key
    onSelect(next)
    refs.current.get(next)?.focus()
  }

  return (
    <>
      <div
        className={cx(styles.tabs, className)}
        role="tablist"
        aria-label={label}
        onKeyDown={onKeyDown}
      >
        {tabs.map((t) => (
          <button
            key={t.key}
            ref={(el) => {
              refs.current.set(t.key, el)
            }}
            type="button"
            role="tab"
            id={`${id}tab-${t.key}`}
            aria-selected={t.key === selected}
            aria-controls={`${id}panel`}
            tabIndex={t.key === selected ? 0 : -1}
            className={styles.tab}
            onClick={() => onSelect(t.key)}
          >
            {t.label}
            {t.badge && (
              <span className={styles.badge}>
                <span className={styles.badgeDot} aria-hidden="true" />
                {t.badge}
              </span>
            )}
          </button>
        ))}
      </div>
      <div
        id={`${id}panel`}
        role="tabpanel"
        aria-labelledby={`${id}tab-${selected}`}
        tabIndex={0}
        className={styles.panel}
      >
        {children}
      </div>
    </>
  )
}
