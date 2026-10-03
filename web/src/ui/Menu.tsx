import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import { cx } from '../lib/cx'
import styles from './Menu.module.css'

export interface MenuItem {
  label: string
  icon?: ReactNode
  /** danger = การกระทำที่ต้องระวัง (สีแดง) */
  tone?: 'default' | 'danger'
  onSelect: () => void
}

export interface MenuButtonProps {
  /** ชื่อปุ่มสำหรับเครื่องอ่านหน้าจอ (ปุ่มแสดงแค่ไอคอน) */
  label: string
  icon: ReactNode
  items: MenuItem[]
  className?: string
}

// ปุ่มเปิดเมนู (WAI-ARIA APG Menu Button): กด/Enter/Space/↓ เปิดแล้วโฟกัสรายการแรก, ↑↓ Home End เลื่อน,
// Esc ปิดแล้วคืนโฟกัสปุ่ม, Tab หรือแตะนอกเมนูปิด — ไม่มีอะไรที่ต้อง hover
export function MenuButton({ label, icon, items, className }: MenuButtonProps) {
  const id = useId()
  const [open, setOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const focusIndex = useRef<number | null>(null)

  const itemsOf = () => [
    ...(menuRef.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? []),
  ]

  useEffect(() => {
    if (!open) return
    const target = focusIndex.current
    focusIndex.current = null
    if (target !== null) itemsOf().at(target)?.focus()
    const onPointerDown = (e: PointerEvent) => {
      const t = e.target as Node
      if (!menuRef.current?.contains(t) && !buttonRef.current?.contains(t)) setOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [open])

  const openAt = (index: number) => {
    focusIndex.current = index
    setOpen(true)
  }
  const close = (refocus: boolean) => {
    setOpen(false)
    if (refocus) buttonRef.current?.focus()
  }

  const onButtonKey = (e: KeyboardEvent) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      openAt(e.key === 'ArrowDown' ? 0 : -1)
    }
  }

  const onMenuKey = (e: KeyboardEvent) => {
    const list = itemsOf()
    const at = list.indexOf(document.activeElement as HTMLElement)
    const move = (i: number) => {
      e.preventDefault()
      list.at(i % list.length)?.focus()
    }
    if (e.key === 'ArrowDown') move(at + 1)
    else if (e.key === 'ArrowUp') move(at - 1)
    else if (e.key === 'Home') move(0)
    else if (e.key === 'End') move(-1)
    else if (e.key === 'Escape') {
      // ไม่ให้ Esc หลุดไปปิดกล่องที่อยู่ด้านนอก
      e.preventDefault()
      e.stopPropagation()
      close(true)
    } else if (e.key === 'Tab') close(false)
  }

  return (
    <div className={cx(styles.wrap, className)}>
      <button
        ref={buttonRef}
        type="button"
        className={styles.trigger}
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? `${id}menu` : undefined}
        onClick={() => (open ? close(false) : openAt(0))}
        onKeyDown={onButtonKey}
      >
        {icon}
      </button>
      {open && (
        <div
          ref={menuRef}
          id={`${id}menu`}
          role="menu"
          aria-label={label}
          className={styles.menu}
          onKeyDown={onMenuKey}
        >
          {items.map((item) => (
            <button
              key={item.label}
              type="button"
              role="menuitem"
              tabIndex={-1}
              className={cx(styles.item, item.tone === 'danger' && styles.danger)}
              onClick={() => {
                close(true)
                item.onSelect()
              }}
            >
              {item.icon && <span aria-hidden="true">{item.icon}</span>}
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
