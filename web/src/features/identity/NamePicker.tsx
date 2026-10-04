import { Check, ChevronRight, Info, Lock, OctagonAlert, Search, TriangleAlert } from 'lucide-react'
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { th } from '../../copy/th'
import type { AppError } from '../../lib/supabase'
import { Button, Input, Sheet } from '../../ui'
import {
  canSearch,
  claimIdentity,
  initialOf,
  REMAINING_WARN_AT,
  searchRoster,
  type Match,
  type SearchResult,
} from './identity'
import styles from './NamePicker.module.css'

type View =
  | { kind: 'hint' }
  | { kind: 'results'; result: SearchResult }
  | { kind: 'limited' }
  | { kind: 'taken' }
  | { kind: 'expired' }
  | { kind: 'error'; error: AppError }

export interface NamePickerProps {
  /** อีเมลของบัญชีที่ล็อกอินอยู่ */
  email: string
  onSwitchAccount: () => void
  /** ผูกสำเร็จ — ได้ชื่อเต็มครั้งแรกตรงนี้ */
  onClaimed: (displayName: string) => void
  /** บัญชีนี้ผูกชื่อไปแล้ว (เช่นจากอีกแท็บ) */
  onAlreadyBound: () => void
}

// A02 ป๊อปอัปเลือกชื่อ (UX_DESIGN ส่วน 4, L3) — แผ่นที่ปิดเองไม่ได้จนผูกสำเร็จ 2 ขั้น: ค้นหา → ยืนยันว่าเป็นฉัน
// ค้นเมื่อกดปุ่มเท่านั้น; ผลเป็นชื่อปิดบางส่วน ห้อง เลขที่; ชื่อเต็มแสดงหลังผูกสำเร็จเท่านั้น
export function NamePicker({ email, onSwitchAccount, onClaimed, onAlreadyBound }: NamePickerProps) {
  const [query, setQuery] = useState('')
  const [view, setView] = useState<View>({ kind: 'hint' })
  const [remaining, setRemaining] = useState<number | null>(null)
  const [selected, setSelected] = useState<Match | null>(null)
  const [busy, setBusy] = useState<'search' | 'claim' | null>(null)
  const [claimError, setClaimError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const titleRef = useRef<HTMLHeadingElement>(null)
  // ย้ายโฟกัสหลังเปลี่ยนขั้น (หลัง render เสร็จ)
  const focusNext = useRef<'title' | 'input' | null>(null)

  useEffect(() => {
    const target = focusNext.current
    if (!target) return
    focusNext.current = null
    if (target === 'title') titleRef.current?.focus()
    else inputRef.current?.focus()
  })

  const backToSearch = (next: View) => {
    setSelected(null)
    setClaimError(null)
    setView(next)
    focusNext.current = 'input'
  }

  const search = async (e: FormEvent) => {
    e.preventDefault()
    if (busy || !canSearch(query)) return
    setBusy('search')
    const outcome = await searchRoster(query)
    setBusy(null)
    if (outcome.ok) {
      setRemaining(outcome.data.remaining)
      setView({ kind: 'results', result: outcome.data })
    } else if (outcome.error.code === 'already_bound') {
      onAlreadyBound()
    } else if (outcome.error.code === 'rate_limited') {
      setRemaining(0)
      setView({ kind: 'limited' })
    } else {
      setView({ kind: 'error', error: outcome.error })
    }
  }

  const pick = (match: Match) => {
    setSelected(match)
    setClaimError(null)
    focusNext.current = 'title'
  }

  const confirm = async () => {
    if (!selected || busy) return
    setBusy('claim')
    setClaimError(null)
    const outcome = await claimIdentity(selected.ref)
    setBusy(null)
    if (outcome.ok) {
      const result = outcome.data
      if (result.status === 'claimed') onClaimed(result.display_name)
      else backToSearch({ kind: result.status === 'name_taken' ? 'taken' : 'expired' })
    } else if (outcome.error.code === 'already_bound') {
      onAlreadyBound()
    } else if (outcome.error.code === 'rate_limited') {
      setClaimError(th.identity.claimLimited)
    } else {
      setClaimError(withRef(outcome.error))
    }
  }

  if (selected) {
    return (
      <Sheet
        open
        onClose={() => {}}
        dismissible={false}
        align="start"
        eyebrow={th.identity.step(2)}
        title={th.identity.confirmTitle}
        titleRef={titleRef}
        // ref เดียวกับขั้นค้นหา: แผ่นเดิมไม่ปิด-เปิดใหม่ตอนเปลี่ยนขั้น
        initialFocusRef={inputRef}
      >
        <div className={styles.card}>
          <span className={styles.avatarLg} aria-hidden="true">
            {initialOf(selected.masked_name)}
          </span>
          <div>
            <b className={styles.cardName}>{selected.masked_name}</b>
            <span>{th.identity.place(selected.group_name, selected.roll_number)}</span>
            <span>{th.identity.fullNameLater}</span>
          </div>
        </div>
        <p className={styles.note} data-tone="amber">
          <Info aria-hidden="true" />
          <span>{th.identity.onceOnly}</span>
        </p>
        <p className="sr-only" aria-live="polite">
          {claimError ?? ''}
        </p>
        {claimError && (
          <p className={styles.note} data-tone="red">
            <TriangleAlert aria-hidden="true" />
            <span>{claimError}</span>
          </p>
        )}
        <Button block icon={<Check />} disabled={busy === 'claim'} onClick={confirm}>
          {busy === 'claim' ? th.identity.confirming : th.identity.confirm}
        </Button>
        <Button
          block
          variant="ghost"
          disabled={busy === 'claim'}
          onClick={() => backToSearch(view)}
        >
          {th.identity.back}
        </Button>
      </Sheet>
    )
  }

  const result = view.kind === 'results' ? view.result : null
  const total = result ? result.matches.length + (result.bound ? 1 : 0) : 0

  return (
    <Sheet
      open
      onClose={() => {}}
      dismissible={false}
      align="start"
      eyebrow={th.identity.step(1)}
      title={th.identity.searchTitle}
      titleRef={titleRef}
      initialFocusRef={inputRef}
    >
      <p className={styles.acct}>
        {th.identity.signedInAs(email)} ·{' '}
        <button type="button" className={styles.link} onClick={onSwitchAccount}>
          {th.identity.switchAccount}
        </button>
      </p>
      <form className={styles.searchRow} onSubmit={search} role="search">
        <label className="sr-only" htmlFor="pickQuery">
          {th.identity.queryLabel}
        </label>
        <div className={styles.searchField}>
          <Search aria-hidden="true" />
          <Input
            ref={inputRef}
            id="pickQuery"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={th.identity.queryPlaceholder}
            autoComplete="off"
            autoCapitalize="off"
            spellCheck={false}
            enterKeyHint="search"
            maxLength={120}
          />
        </div>
        <Button type="submit" disabled={busy === 'search' || !canSearch(query)}>
          {busy === 'search' ? th.identity.searching : th.identity.search}
        </Button>
      </form>
      {remaining !== null && remaining <= REMAINING_WARN_AT && view.kind === 'results' && (
        <p className={styles.hint}>{th.identity.remaining(remaining)}</p>
      )}
      {/* ผลแต่ละครั้งอ่านให้เครื่องอ่านหน้าจอฟัง (กล่องข้อความที่เห็นไม่ใช่ live region เพื่อไม่ให้มีช่องว่างเกิน) */}
      <p className="sr-only" aria-live="polite">
        {announce(view, total)}
      </p>
      {view.kind === 'hint' && <p className={styles.hint}>{th.identity.hint}</p>}
      {result && total === 0 && (
        <p className={styles.note} data-tone="plain">
          <Search aria-hidden="true" />
          <span>{th.identity.notFound}</span>
        </p>
      )}
      {view.kind === 'limited' && (
        <p className={styles.note} data-tone="red">
          <OctagonAlert aria-hidden="true" />
          <span>
            <b>{th.identity.searchLimitedTitle}</b>
            <br />
            {th.identity.searchLimited}
          </span>
        </p>
      )}
      {view.kind === 'taken' && (
        <p className={styles.note} data-tone="plain">
          <Lock aria-hidden="true" />
          <span>{th.identity.bound}</span>
        </p>
      )}
      {view.kind === 'expired' && (
        <p className={styles.note} data-tone="amber">
          <Info aria-hidden="true" />
          <span>{th.identity.expired}</span>
        </p>
      )}
      {view.kind === 'error' && (
        <p className={styles.note} data-tone="red">
          <TriangleAlert aria-hidden="true" />
          <span>{withRef(view.error)}</span>
        </p>
      )}
      {result && total > 0 && (
        <ul className={styles.list}>
          {result.matches.map((m) => (
            <li key={m.ref}>
              <button type="button" className={styles.row} onClick={() => pick(m)}>
                <span className={styles.avatar} aria-hidden="true">
                  {initialOf(m.masked_name)}
                </span>
                <span>
                  <b>{m.masked_name}</b>
                  <span>{th.identity.place(m.group_name, m.roll_number)}</span>
                </span>
                <ChevronRight aria-hidden="true" />
              </button>
            </li>
          ))}
          {result.bound && (
            <li className={styles.row} data-taken="true">
              <span className={styles.avatar} aria-hidden="true">
                <Lock />
              </span>
              <span>
                <b>{th.identity.boundTitle}</b>
                <span>{th.identity.bound}</span>
              </span>
            </li>
          )}
        </ul>
      )}
    </Sheet>
  )
}

function announce(view: View, total: number): string {
  switch (view.kind) {
    case 'hint':
      return ''
    case 'results':
      return total > 0 ? th.identity.found(total) : th.identity.notFound
    case 'limited':
      return `${th.identity.searchLimitedTitle} ${th.identity.searchLimited}`
    case 'taken':
      return th.identity.bound
    case 'expired':
      return th.identity.expired
    case 'error':
      return withRef(view.error)
  }
}

function withRef(error: AppError): string {
  return error.ref ? `${error.message} (${th.errors.reference(error.ref)})` : error.message
}
