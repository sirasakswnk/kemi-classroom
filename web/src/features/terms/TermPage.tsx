import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Archive,
  ArrowRight,
  CalendarRange,
  ClipboardCheck,
  Flag,
  FolderArchive,
  Gem,
  Lock,
  Pencil,
  School,
  ShieldCheck,
  Table2,
  TriangleAlert,
  Users,
} from 'lucide-react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { thaiDate } from '../../lib/thaiTime'
import { Button, Chip, Field, Input, Modal, useToast } from '../../ui'
import { Coin } from '../rewards/Medal'
import { useRequestKey } from '../review/useRequestKey'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { pastClassroomsQuery } from '../classrooms/api'
import { TERM_NAME_MAX, termOverviewQuery, termsEnd, termsStart, type TermOverview } from './api'
import styles from './terms.module.css'

const copy = th.terms

// T07 ภาคเรียนและข้อมูลเก่า (UX T07; แบบ v2 tTerm): สถานะ + ตัวเลขรวม · เริ่ม/เปิดภาคเรียนใหม่ · จบภาคเรียน (J9)
// ทั้งสองปุ่มเปิดหน้าต่างยืนยันที่สรุปผล (ผู้ใช้ขอ 24 ต.ค. 2026) — ส่งภาคเรียนที่หน้าจอเห็นไปเทียบ (stale_revision)
// สำเร็จหรือ term_ended/stale_revision: โหลดข้อมูลทุกหน้าใหม่ เพราะภาคเรียน/ห้อง/ยอดเปลี่ยนทั้งระบบ
// ดาวน์โหลด/ยืนยันลบข้อมูลเก่ามากับระยะ 6 — ตอนนี้แสดงวันครบอายุอย่างเดียว
export default function TermPage() {
  const { adminMode } = useTeacher()
  const overview = useQuery(termOverviewQuery(adminMode))

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: th.teacher.term }]}>
      {overview.isError ? (
        <div className={styles.loadFailed}>
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {copy.loadFailed} · {appErrorOf(overview.error).message}
            </span>
          </p>
          <Button variant="ghost" onClick={() => void overview.refetch()}>
            {copy.retry}
          </Button>
        </div>
      ) : overview.data ? (
        <TermBody data={overview.data} adminMode={adminMode} />
      ) : null}
    </TeacherPage>
  )
}

function TermBody({ data, adminMode }: { data: TermOverview; adminMode: boolean }) {
  const ended = data.term.status === 'ended'
  return (
    <>
      <div className={styles.head}>
        <span className={styles.eyebrow}>{copy.sharedBy(data.classrooms)}</span>
        <h1>{copy.title}</h1>
        <p>{copy.intro}</p>
      </div>
      <div className={styles.grid}>
        <section className={styles.now} aria-labelledby="term-now">
          <span className={styles.eyebrow}>{ended ? copy.latest : copy.current}</span>
          <h2 id="term-now">{data.term.name}</h2>
          {ended && (
            <Chip tone="purple" icon={<Lock />} className={styles.chip}>
              {copy.endedChip}
            </Chip>
          )}
          <dl className={styles.stats}>
            <Stat value={data.classrooms} label={copy.stats.classrooms} />
            <Stat value={data.students} label={copy.stats.students} />
            <Stat value={data.tokens} label={copy.stats.tokens} />
            <Stat value={data.waiting} label={copy.stats.waiting} />
          </dl>
          <h3>{copy.retentionTitle}</h3>
          <ol className={styles.timeline}>
            <Step icon={<Flag />} title={copy.tlPress} body={copy.tlPressBody} />
            <Step icon={<FolderArchive />} title={copy.tlFiles} body={copy.tlFilesBody} />
            <Step icon={<Table2 />} title={copy.tlData} body={copy.tlDataBody} gold />
          </ol>
          <p className={styles.note} data-tone="plain">
            <ShieldCheck aria-hidden="true" />
            <span>{copy.noAutoDelete}</span>
          </p>
        </section>
        <StartPanel data={data} adminMode={adminMode} />
      </div>
      {ended ? (
        <p className={styles.note} data-tone="purple">
          <Lock aria-hidden="true" />
          <span>{copy.endedNote(data.term.name, thaiDate(data.term.ended_at ?? ''))}</span>
        </p>
      ) : (
        <EndPanel data={data} adminMode={adminMode} />
      )}
      <OldTerms data={data} />
    </>
  )
}

function Stat({ value, label }: { value: number; label: string }) {
  return (
    <div>
      <dd className="num">{value}</dd>
      <dt>{label}</dt>
    </div>
  )
}

function Step(props: { icon: ReactNode; title: string; body: string; gold?: boolean }) {
  return (
    <li className={styles.step}>
      <span className={styles.dot} data-gold={props.gold || undefined} aria-hidden="true">
        {props.icon}
      </span>
      <b>{props.title}</b>
      <span>{props.body}</span>
    </li>
  )
}

function Effects({ items }: { items: { icon: ReactNode; text: string; gold?: boolean }[] }) {
  return (
    <ul className={styles.effects}>
      {items.map((e) => (
        <li key={e.text}>
          <span className={styles.eIcon} data-gold={e.gold || undefined} aria-hidden="true">
            {e.icon}
          </span>
          <span>{e.text}</span>
        </li>
      ))}
    </ul>
  )
}

/** หลังเริ่ม/จบ (หรือรู้ว่าสถานะเปลี่ยนแล้ว): ภาคเรียน ห้อง ยอด และสถานะงานเปลี่ยนทั้งระบบ */
function useReloadAll() {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries()
}

function StartPanel({ data, adminMode }: { data: TermOverview; adminMode: boolean }) {
  const ended = data.term.status === 'ended'
  const [name, setName] = useState('')
  const [ack, setAck] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const nameRef = useRef<HTMLInputElement>(null)
  const requestKey = useRequestKey()
  const reloadAll = useReloadAll()
  const toast = useToast()
  const trimmed = name.trim()

  const start = useMutation({
    mutationFn: () =>
      termsStart(
        trimmed,
        data.term.term_id,
        requestKey.keyFor(`${data.term.term_id}:${trimmed}`),
        adminMode,
      ),
    onSuccess: async (res) => {
      setConfirming(false)
      setName('')
      setAck(false)
      toast(copy.started(res.name), { tone: 'success' })
      await reloadAll()
    },
    onError: async (e) => {
      const app = appErrorOf(e)
      setConfirming(false)
      setError(app)
      if (app.code === 'stale_revision' || app.code === 'term_ended') await reloadAll()
    },
  })

  // ชื่อซ้ำ: โฟกัสช่องหลังหน้าต่างยืนยันปิดและคืนโฟกัสให้ปุ่มแล้ว (effect ของ Modal ลูกทำงานก่อน)
  const nameTaken = !confirming && error?.code === 'term_name_taken'
  useEffect(() => {
    if (nameTaken) nameRef.current?.focus()
  }, [nameTaken])

  const items = [
    { icon: <Coin size={24} />, text: copy.effectTokens, gold: true },
    { icon: <Gem />, text: copy.effectCharms },
    { icon: <ClipboardCheck />, text: copy.effectOldWork },
    { icon: <FolderArchive />, text: ended ? copy.effectMoveEnded : copy.effectMove },
  ]
  const nameError = error?.code === 'term_name_taken' ? error.message : undefined

  return (
    <section className={styles.panel} aria-labelledby="term-start">
      <h2 id="term-start">{ended ? copy.resumeTitle : copy.startTitle}</h2>
      <Field label={copy.nameLabel} hint={copy.nameHint(TERM_NAME_MAX)} error={nameError}>
        <Input
          ref={nameRef}
          value={name}
          maxLength={TERM_NAME_MAX}
          onChange={(e) => {
            setName(e.target.value)
            if (error) setError(null)
          }}
        />
      </Field>
      <Effects items={items} />
      {data.waiting > 0 && !ended && (
        <p className={styles.note} data-tone="amber">
          <TriangleAlert aria-hidden="true" />
          <span>{copy.waitingNote(data.waiting)}</span>
        </p>
      )}
      <label className={styles.check}>
        <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} />
        {copy.startAck}
      </label>
      {error && !nameError && <ErrorLine error={error} />}
      <Button
        icon={<CalendarRange />}
        disabled={!ack || !trimmed || start.isPending}
        onClick={() => {
          setError(null)
          setConfirming(true)
        }}
      >
        {copy.startButton(trimmed)}
      </Button>
      <Modal
        open={confirming}
        onClose={() => !start.isPending && setConfirming(false)}
        icon={<CalendarRange />}
        title={copy.confirmStartTitle(trimmed)}
        description={copy.confirmDesc}
        footer={
          <>
            <Button variant="ghost" disabled={start.isPending} onClick={() => setConfirming(false)}>
              {copy.cancel}
            </Button>
            <Button disabled={start.isPending} onClick={() => start.mutate()}>
              {start.isPending ? copy.working : copy.confirmStart}
            </Button>
          </>
        }
      >
        <Effects
          items={[
            { icon: <Coin size={24} />, text: copy.confirmTokens(data.tokens), gold: true },
            { icon: <Gem />, text: copy.effectCharms },
            { icon: <ClipboardCheck />, text: copy.effectOldWork },
            { icon: <School />, text: copy.effectRooms },
            { icon: <FolderArchive />, text: ended ? copy.effectMoveEnded : copy.effectMove },
          ]}
        />
        {data.waiting > 0 && !ended && (
          <p className={styles.note} data-tone="amber">
            <TriangleAlert aria-hidden="true" />
            <span>{copy.waitingNote(data.waiting)}</span>
          </p>
        )}
      </Modal>
    </section>
  )
}

function EndPanel({ data, adminMode }: { data: TermOverview; adminMode: boolean }) {
  const [ack, setAck] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const requestKey = useRequestKey()
  const reloadAll = useReloadAll()
  const toast = useToast()

  const end = useMutation({
    mutationFn: () => termsEnd(data.term.term_id, requestKey.keyFor(data.term.term_id), adminMode),
    onSuccess: async (res) => {
      setConfirming(false)
      toast(copy.ended(res.name), { tone: 'success' })
      await reloadAll()
    },
    onError: async (e) => {
      const app = appErrorOf(e)
      setConfirming(false)
      setError(app)
      if (app.code === 'stale_revision' || app.code === 'term_ended') await reloadAll()
    },
  })

  const items = [
    { icon: <Lock />, text: copy.endEffectStudents },
    { icon: <Pencil />, text: copy.endEffectTeacher },
    { icon: <FolderArchive />, text: copy.endEffectRetention },
    { icon: <Users />, text: copy.endEffectAccounts },
  ]

  return (
    <section className={styles.panel} aria-labelledby="term-end">
      <div>
        <h2 id="term-end">{copy.endTitle}</h2>
        <p className={styles.muted}>{copy.endIntro}</p>
      </div>
      <Effects items={items} />
      {error && <ErrorLine error={error} />}
      <div className={styles.endAct}>
        <label className={styles.check}>
          <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} />
          {copy.endAck}
        </label>
        <Button
          variant="ghost"
          icon={<Flag />}
          disabled={!ack || end.isPending}
          onClick={() => {
            setError(null)
            setConfirming(true)
          }}
        >
          {copy.endButton(data.term.name)}
        </Button>
      </div>
      <Modal
        open={confirming}
        onClose={() => !end.isPending && setConfirming(false)}
        icon={<Flag />}
        title={copy.confirmEndTitle(data.term.name)}
        description={copy.confirmDesc}
        footer={
          <>
            <Button variant="ghost" disabled={end.isPending} onClick={() => setConfirming(false)}>
              {copy.cancel}
            </Button>
            <Button disabled={end.isPending} onClick={() => end.mutate()}>
              {end.isPending ? copy.working : copy.confirmEnd}
            </Button>
          </>
        }
      >
        <Effects items={items} />
      </Modal>
    </section>
  )
}

// ลิงก์ไปห้องของแต่ละภาคเรียน (UX ข้อใหม่ใต้ “[ยืนยัน I5]”): ห้องเทอมเก่าตาม RLS (ครู = ห้องตัวเอง, ผู้ดูแล = ทุกห้อง)
// + ห้องของภาคเรียนปัจจุบันเมื่อกดจบแล้ว (ภาคเรียนนั้นอยู่ในข้อมูลเก่าด้วย)
function OldTerms({ data }: { data: TermOverview }) {
  const { classrooms } = useTeacher()
  const past = useQuery(pastClassroomsQuery(data.term.term_id))
  const rooms = [...(past.data ?? []), ...classrooms]
  return (
    <section className={styles.panel} aria-labelledby="term-old">
      <h2 id="term-old">{copy.oldTitle}</h2>
      {data.old_terms.length === 0 ? (
        <p className={styles.locked}>
          <Archive aria-hidden="true" />
          <span>{copy.oldEmpty}</span>
        </p>
      ) : (
        data.old_terms.map((t) => (
          <div key={t.id} className={styles.oldTerm}>
            <div className={styles.oldHead}>
              <h3>{t.name}</h3>
              <span className={styles.muted}>
                {copy.oldHow[t.how]} {thaiDate(t.retention_from)}
              </span>
            </div>
            <div className={styles.retRow}>
              <b>{copy.oldFiles}</b>
              <span className={styles.muted}>{copy.due(thaiDate(t.files_due))}</span>
            </div>
            <div className={styles.retRow}>
              <b>{copy.oldData}</b>
              <span className={styles.muted}>{copy.due(thaiDate(t.data_due))}</span>
            </div>
            <OldRooms rooms={rooms.filter((c) => c.term_id === t.id)} loading={past.isPending} />
          </div>
        ))
      )}
    </section>
  )
}

function OldRooms({ rooms, loading }: { rooms: { id: string; name: string }[]; loading: boolean }) {
  if (loading) return null
  return (
    <div className={styles.roomRow}>
      <b>{th.classrooms.pastRoomsLabel}</b>
      {rooms.length === 0 ? (
        <span className={styles.muted}>{th.classrooms.pastRoomsNone}</span>
      ) : (
        <ul className={styles.roomLinks}>
          {rooms.map((c) => (
            <li key={c.id}>
              <Link to={`/t/c/${c.id}`}>
                {c.name}
                <ArrowRight aria-hidden="true" />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ErrorLine({ error }: { error: AppError }) {
  return (
    <p className={styles.alert} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {error.message}
        {error.ref && <small> {th.errors.reference(error.ref)}</small>}
      </span>
    </p>
  )
}
