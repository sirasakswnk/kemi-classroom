import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link2, Lock, LockOpen, Maximize2, Table2, TriangleAlert, Users } from 'lucide-react'
import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router'
import { th } from '../../copy/th'
import { Tabs, useToast } from '../../ui'
import { useTabParam } from '../../lib/useTabParam'
import { initialOf as initialOfTeacher } from '../../lib/initial'
import { RoomPosts } from '../posts/RoomPosts'
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

// T08 ห้องเรียนของครู: แถบบนมีรหัส (กด → T10) ปิด/เปิดการเข้าห้อง คัดลอกลิงก์เชิญ; สามแท็บเดียวกับนักเรียน
// แท็บงาน/ประกาศ: รายการโพสต์ + ปุ่มสร้าง (T02) — ยอดส่ง/รอตรวจและ T03 มากับ P3-09
export default function ClassroomPage() {
  const { classId: id = '' } = useParams()
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
        termActive={term?.status === 'active'}
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
  termActive,
  teacherName,
  adminMode,
}: {
  classroom: Classroom
  tone: number
  termName: string
  termId: string | undefined
  termActive: boolean
  teacherName: string
  adminMode: boolean
}) {
  const copy = th.classrooms.room
  const [tab, selectTab] = useTabParam(TABS, 'work')
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
            <Link to={`/t/c/${c.id}/grades`} className={styles.toolBtn} data-solid="true">
              <Table2 aria-hidden="true" />
              {th.gradebook.openFromRoom}
            </Link>
            <Link to="/t/roster" className={styles.toolBtn} data-solid="true">
              <Users aria-hidden="true" />
              {copy.roster}
            </Link>
          </div>
        </ClassBanner>
      </section>
      {joinError && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{joinError}</span>
        </p>
      )}

      <Tabs
        label={copy.tabsLabel}
        tabs={TABS.map((key) => ({ key, label: copy.tabs[key] }))}
        selected={tab}
        onSelect={selectTab}
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
          // K5: ห้องของภาคเรียนก่อนโพสต์ไม่ได้; ภาคเรียนจบแล้วสร้างได้เฉพาะประกาศ
          <RoomPosts
            classroomId={c.id}
            kind={tab === 'work' ? 'homework' : 'announcement'}
            audience="teacher"
            teacherName={teacherName}
            canCreate={c.term_id === termId && (tab !== 'work' || termActive)}
          />
        )}
      </Tabs>

      <CodeFullscreen open={fullOpen} onClose={closeFull} name={c.name} code={c.join_code} />
    </>
  )
}
