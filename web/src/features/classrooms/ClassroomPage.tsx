import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  FilePlus,
  Link2,
  Lock,
  LockOpen,
  Maximize2,
  Megaphone,
  TriangleAlert,
  Users,
} from 'lucide-react'
import { useCallback, useId, useRef, useState, type KeyboardEvent } from 'react'
import { Link, useParams, useSearchParams } from 'react-router'
import { th } from '../../copy/th'
import { useToast } from '../../ui'
import { initialOfTeacher } from '../teacher/initial'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import {
  appErrorOf,
  classroomQuery,
  inviteLink,
  setJoinEnabled,
  teachersQuery,
  type Classroom,
} from './api'
import { ClassBanner } from './ClassBanner'
import { CodeFullscreen } from './CodeFullscreen'
import { requestPageFullscreen } from './fullscreen'
import styles from './classrooms.module.css'
import { MembersPanel } from './MembersPanel'

const TABS = ['general', 'work', 'members'] as const
type Tab = (typeof TABS)[number]

// T08 ห้องเรียนของครู: แถบบนมีรหัส (กด → T10) ปิด/เปิดการเข้าห้อง คัดลอกลิงก์เชิญ; สามแท็บเดียวกับนักเรียน
// งานและประกาศมาในระยะ 3 — ตอนนี้แท็บสมาชิกใช้งานได้จริง
export default function ClassroomPage() {
  const { id = '' } = useParams()
  const { term, adminMode, classrooms } = useTeacher()
  const classroom = useQuery(classroomQuery(id))
  const teachers = useQuery(teachersQuery)

  const crumbsFor = (name: string) => [{ label: th.teacher.overview, to: '/t' }, { label: name }]

  if (classroom.isPending) {
    return (
      <TeacherPage crumbs={crumbsFor('…')}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  if (classroom.isError || !classroom.data) {
    const error = classroom.isError ? appErrorOf(classroom.error) : null
    return (
      <TeacherPage crumbs={crumbsFor(th.classrooms.room.notFoundTitle)}>
        <div className={styles.empty}>
          <TriangleAlert aria-hidden="true" />
          <b>{error ? th.teacher.loadFailed : th.classrooms.room.notFoundTitle}</b>
          <span>
            {error
              ? `${error.message}${error.ref ? ` (${th.errors.reference(error.ref)})` : ''}`
              : th.classrooms.room.notFoundBody}
          </span>
          <Link to="/t" className={styles.softLink}>
            {th.classrooms.room.backToOverview}
          </Link>
        </div>
      </TeacherPage>
    )
  }

  const c = classroom.data
  const tone = Math.max(
    0,
    classrooms.findIndex((x) => x.id === c.id),
  )
  const teacherName = teachers.data?.find((t) => t.id === c.teacher_id)?.display_name ?? ''
  return (
    <TeacherPage crumbs={crumbsFor(c.name)}>
      <Room
        key={c.id}
        classroom={c}
        tone={tone}
        termName={term?.name ?? ''}
        termId={term?.id}
        teacherName={teacherName}
        adminMode={adminMode}
      />
    </TeacherPage>
  )
}

function Room({
  classroom: c,
  tone,
  termName,
  termId,
  teacherName,
  adminMode,
}: {
  classroom: Classroom
  tone: number
  termName: string
  termId: string | undefined
  teacherName: string
  adminMode: boolean
}) {
  const copy = th.classrooms.room
  const id = useId()
  const [params, setParams] = useSearchParams()
  const tabParam = params.get('tab')
  const tab: Tab = (TABS as readonly string[]).includes(tabParam ?? '') ? (tabParam as Tab) : 'work'
  const tabRefs = useRef<Partial<Record<Tab, HTMLButtonElement | null>>>({})
  const [fullOpen, setFullOpen] = useState(false)
  const [joinError, setJoinError] = useState<string | null>(null)
  const queryClient = useQueryClient()
  const toast = useToast()

  const toggle = useMutation({
    mutationFn: (enabled: boolean) => setJoinEnabled(c.id, enabled, adminMode),
    onSuccess: async (result) => {
      setJoinError(null)
      queryClient.setQueryData(classroomQuery(c.id).queryKey, (prev) =>
        prev ? { ...prev, join_enabled: result.join_enabled } : prev,
      )
      await queryClient.invalidateQueries({ queryKey: ['classrooms'] })
      toast(
        result.join_enabled ? copy.openedToast(c.name, result.join_code) : copy.closedToast(c.name),
        { tone: 'success' },
      )
    },
    onError: (error) => {
      const e = appErrorOf(error)
      setJoinError(e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : ''))
    },
  })

  const openFull = () => {
    if (!c.join_enabled) return
    requestPageFullscreen()
    setFullOpen(true)
  }
  const closeFull = useCallback(() => setFullOpen(false), [])

  const copyInvite = async () => {
    try {
      await navigator.clipboard.writeText(inviteLink(c.join_code))
      toast(copy.inviteCopied, { tone: 'success' })
    } catch {
      toast(copy.inviteCopyFailed(c.join_code))
    }
  }

  const selectTab = (next: Tab, focus = false) => {
    setParams(
      (p) => {
        const n = new URLSearchParams(p)
        n.set('tab', next)
        return n
      },
      { replace: true },
    )
    if (focus) tabRefs.current[next]?.focus()
  }

  // ลูกศรซ้าย/ขวา Home End เลือกแท็บ (WAI-ARIA APG Tabs แบบเลือกทันที)
  const onTabKey = (e: KeyboardEvent) => {
    const at = TABS.indexOf(tab)
    const to =
      e.key === 'ArrowRight'
        ? (at + 1) % TABS.length
        : e.key === 'ArrowLeft'
          ? (at + TABS.length - 1) % TABS.length
          : e.key === 'Home'
            ? 0
            : e.key === 'End'
              ? TABS.length - 1
              : null
    if (to === null) return
    e.preventDefault()
    selectTab(TABS[to], true)
  }

  return (
    <>
      <section className={styles.hero} aria-label={c.name}>
        <ClassBanner tone={tone} size="hero" level={1} eyebrow={termName} title={c.name}>
          <p className={styles.teacherLine}>
            <span className={styles.bannerAvatar} aria-hidden="true">
              {initialOfTeacher(teacherName)}
            </span>
            <span>
              {[teacherName, copy.members(c.member_count + 1), c.description]
                .filter(Boolean)
                .join(' · ')}
            </span>
          </p>
          <div className={styles.tools}>
            {c.join_enabled ? (
              <>
                <button
                  type="button"
                  className={styles.codeChip}
                  aria-label={copy.codeAria(c.join_code)}
                  onClick={openFull}
                >
                  <span aria-hidden="true">{copy.codeLabel}</span>
                  <b aria-hidden="true">{c.join_code}</b>
                  <Maximize2 aria-hidden="true" />
                </button>
                <button
                  type="button"
                  className={styles.toolBtn}
                  disabled={toggle.isPending}
                  onClick={() => toggle.mutate(false)}
                >
                  <Lock aria-hidden="true" />
                  {copy.close}
                </button>
                <button type="button" className={styles.toolBtn} onClick={() => void copyInvite()}>
                  <Link2 aria-hidden="true" />
                  {copy.copyInvite}
                </button>
              </>
            ) : (
              <>
                <span className={styles.codeOff}>
                  <Lock aria-hidden="true" />
                  <span>{copy.closedBadge}</span>
                </span>
                <button
                  type="button"
                  className={styles.toolBtn}
                  disabled={toggle.isPending}
                  onClick={() => toggle.mutate(true)}
                >
                  <LockOpen aria-hidden="true" />
                  {copy.open}
                </button>
              </>
            )}
            {!adminMode && (
              <Link to="/t/roster/import" className={styles.toolBtn} data-solid="true">
                <Users aria-hidden="true" />
                {copy.roster}
              </Link>
            )}
          </div>
        </ClassBanner>
      </section>
      {joinError && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{joinError}</span>
        </p>
      )}

      <div className={styles.tabs} role="tablist" aria-label={copy.tabsLabel} onKeyDown={onTabKey}>
        {TABS.map((t) => (
          <button
            key={t}
            ref={(el) => {
              tabRefs.current[t] = el
            }}
            type="button"
            role="tab"
            id={`${id}tab-${t}`}
            aria-selected={tab === t}
            aria-controls={`${id}panel`}
            tabIndex={tab === t ? 0 : -1}
            className={styles.tab}
            onClick={() => selectTab(t)}
          >
            {copy.tabs[t]}
          </button>
        ))}
      </div>
      <div
        id={`${id}panel`}
        role="tabpanel"
        aria-labelledby={`${id}tab-${tab}`}
        tabIndex={0}
        className={styles.panel}
      >
        {tab === 'members' ? (
          <MembersPanel
            classroom={c}
            termId={termId}
            teacherName={teacherName}
            adminMode={adminMode}
            onOpenCode={openFull}
          />
        ) : (
          <>
            <h2 className={styles.panelTitle}>
              {tab === 'general' ? copy.generalHead : copy.workHead}
            </h2>
            <div className={styles.empty}>
              {tab === 'general' ? (
                <Megaphone aria-hidden="true" />
              ) : (
                <FilePlus aria-hidden="true" />
              )}
              <b>{tab === 'general' ? copy.generalEmptyTitle : copy.workEmptyTitle}</b>
              <span>{tab === 'general' ? copy.generalEmptyBody : copy.postsLater}</span>
            </div>
          </>
        )}
      </div>

      <CodeFullscreen open={fullOpen} onClose={closeFull} name={c.name} code={c.join_code} />
    </>
  )
}
