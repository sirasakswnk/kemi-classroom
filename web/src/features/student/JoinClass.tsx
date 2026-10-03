import { useMutation } from '@tanstack/react-query'
import { Info, LogIn, Search, TriangleAlert } from 'lucide-react'
import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { ClassBanner } from '../classrooms/ClassBanner'
import {
  joinClassroom,
  lookupClassroom,
  normalizeCode,
  type ClassCard,
  type FindResult,
} from './api'
import { useStudent } from './studentContext'
import styles from './student.module.css'

type View =
  | { kind: 'idle' }
  | { kind: 'found' | 'member'; classroom: ClassCard }
  | { kind: 'error'; message: string }

const CODE_LENGTH = 6

/** ข้อความของผลที่หา/เข้าไม่ได้ ตาม UX 4 และ 9 */
function messageFor(result: FindResult): string | null {
  if (result.status === 'closed') return th.student.join.closed
  if (result.status === 'not_found') return th.student.join.notFound
  return null
}

// เข้าชั้นเรียนด้วยรหัส (แบบ v2 joinForm): พิมพ์รหัส (ตัวเล็ก เว้นวรรค ขีดได้ แปลงเป็นตัวใหญ่ให้) → ค้นหา
// → แสดงชื่อห้อง ครู จำนวนสมาชิกให้ตรวจ → กด “เข้าร่วมชั้นเรียนนี้” เอง (ลิงก์เชิญก็ไม่เข้าอัตโนมัติ)
export function JoinClass({
  initialCode = '',
  autoSearch = false,
  invite = false,
  termName,
  onCancel,
  onJoined,
}: {
  initialCode?: string
  /** ลิงก์เชิญ: ค้นหารหัสจากลิงก์ให้ทันทีหนึ่งครั้ง */
  autoSearch?: boolean
  invite?: boolean
  termName: string
  onCancel?: () => void
  onJoined: (classroom: ClassCard) => void
}) {
  const id = useId()
  const { reloadStudent } = useStudent()
  const [code, setCode] = useState(() => initialCode.toUpperCase())
  const [view, setView] = useState<View>({ kind: 'idle' })
  const searchedOnce = useRef(false)

  const fail = (error: unknown) => {
    const e = appErrorOf(error)
    if (e.code === 'identity_required') {
      reloadStudent()
      return
    }
    const message =
      e.code === 'rate_limited'
        ? th.student.join.limited
        : e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : '')
    setView({ kind: 'error', message })
  }

  const lookup = useMutation({
    mutationFn: lookupClassroom,
    onSuccess: (result) => {
      const message = messageFor(result)
      if (message) setView({ kind: 'error', message })
      else if (
        result.status === 'found' ||
        result.status === 'member' ||
        result.status === 'joined'
      )
        setView({
          kind: result.status === 'found' ? 'found' : 'member',
          classroom: result.classroom,
        })
    },
    onError: fail,
  })

  const join = useMutation({
    mutationFn: joinClassroom,
    onSuccess: (result) => {
      const message = messageFor(result)
      if (message) setView({ kind: 'error', message })
      else if (result.status === 'joined') onJoined(result.classroom)
      else if (result.status === 'member' || result.status === 'found')
        setView({ kind: 'member', classroom: result.classroom })
    },
    onError: fail,
  })

  // ลิงก์เชิญ: ค้นหาให้หนึ่งครั้งตอนเปิดหน้า (ref กันเรียกซ้ำตอน StrictMode)
  const { mutate: lookupNow } = lookup
  useEffect(() => {
    if (!autoSearch || searchedOnce.current || !initialCode) return
    searchedOnce.current = true
    lookupNow(initialCode)
  }, [autoSearch, initialCode, lookupNow])

  const canSearch = normalizeCode(code).length >= CODE_LENGTH && !lookup.isPending
  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (canSearch) lookup.mutate(code)
  }

  const busy = lookup.isPending || join.isPending
  const announce =
    view.kind === 'error'
      ? view.message
      : view.kind === 'idle'
        ? ''
        : `${th.student.join.foundAria(view.classroom.name)}${view.kind === 'member' ? ` ${th.student.join.already}` : ''}`

  return (
    <section className={styles.joinForm} aria-labelledby={`${id}title`}>
      <div className={styles.sectionHead}>
        <h3 id={`${id}title`}>{th.student.join.title}</h3>
        {onCancel && (
          <button type="button" className={styles.link} onClick={onCancel}>
            {th.student.join.cancel}
          </button>
        )}
      </div>
      <label className={styles.lbl} htmlFor={`${id}code`}>
        {th.student.join.codeLabel}
      </label>
      <form className={styles.joinRow} onSubmit={submit}>
        <input
          id={`${id}code`}
          className={styles.codeInput}
          value={code}
          onChange={(e) => {
            setCode(e.target.value.toUpperCase())
            if (view.kind !== 'idle') setView({ kind: 'idle' })
          }}
          placeholder={th.student.join.placeholder}
          maxLength={12}
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          enterKeyHint="search"
          aria-invalid={view.kind === 'error' || undefined}
          aria-describedby={`${id}hint${view.kind === 'error' ? ` ${id}error` : ''}`}
        />
        <button type="submit" className={styles.searchBtn} disabled={!canSearch}>
          <Search aria-hidden="true" />
          {lookup.isPending ? th.student.join.searching : th.student.join.search}
        </button>
      </form>
      <p className="sr-only" aria-live="polite">
        {announce}
      </p>
      {view.kind === 'error' && (
        <p id={`${id}error`} className={styles.note} data-tone="red">
          <TriangleAlert aria-hidden="true" />
          <span>{view.message}</span>
        </p>
      )}
      {(view.kind === 'found' || view.kind === 'member') && (
        <div className={styles.found}>
          <ClassBanner
            tone={0}
            eyebrow={invite ? th.student.join.fromInvite : termName}
            title={view.classroom.name}
          />
          <div className={styles.foundBody}>
            <span>
              {th.student.classMeta(view.classroom.teacher_name, view.classroom.member_count + 1)}
            </span>
            {view.kind === 'member' ? (
              <>
                <p className={styles.note} data-tone="purple">
                  <Info aria-hidden="true" />
                  <span>{th.student.join.already}</span>
                </p>
                <Link to={`/c/${view.classroom.id}`} className={styles.softBlock}>
                  {th.student.join.openClass}
                </Link>
              </>
            ) : (
              <button
                type="button"
                className={styles.primaryBlock}
                disabled={busy}
                onClick={() => join.mutate(code)}
              >
                <LogIn aria-hidden="true" />
                {join.isPending ? th.student.join.joining : th.student.join.submit}
              </button>
            )}
          </div>
        </div>
      )}
      <p id={`${id}hint`} className={styles.hint}>
        {th.student.join.hint}
      </p>
    </section>
  )
}
