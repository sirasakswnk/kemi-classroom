import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Bell,
  CalendarClock,
  FilePen,
  Info,
  Megaphone,
  Send,
  Sparkles,
  TriangleAlert,
} from 'lucide-react'
import { useRef, useState, type FormEvent, type RefObject } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { appErrorOf } from '../../lib/request'
import { bangkokToUtcIso, thaiDate, thaiTime } from '../../lib/thaiTime'
import { Card, Chip, Field, Input, Stepper, Textarea, useToast } from '../../ui'
import { classroomQuery, teachersQuery, type Classroom } from '../classrooms/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { createPost } from './api'
import {
  defaultPostForm,
  dueReminder,
  FIELD_ORDER,
  POST_LIMITS,
  validatePostForm,
  type PostField,
  type PostFormValues,
  type PostKind,
} from './postForm'
import { applyScript, type ScriptKind } from './script'
import styles from './posts.module.css'

// T02 สร้างงาน/ประกาศ (UX_DESIGN ส่วน 9): เลือกชนิด → กรอก → โพสต์ แล้วกลับ T08 แท็บของชนิดนั้น
// ตรวจตามเพดานเดียวกับฐานข้อมูลก่อนส่ง; กดซ้ำ/เน็ตหลุดแล้วส่งเนื้อหาเดิมใช้ request key เดิม → โพสต์เดียว
// K5: ภาคเรียนจบแล้ว (ended) สร้างได้เฉพาะประกาศ; ห้องของภาคเรียนก่อนโพสต์ไม่ได้
// ไฟล์โจทย์/ไฟล์แนบมากับโมดูลอัปโหลด (P3-06) เป็นคีย์ใหม่ในก้อน p_post
export default function CreatePost() {
  const { classId = '' } = useParams()
  const [search] = useSearchParams()
  const { term, adminMode } = useTeacher()
  const classroom = useQuery(classroomQuery(classId))
  const teachers = useQuery(teachersQuery)
  const copy = th.posts.create
  const roomCopy = th.classrooms.room

  const crumbs = (name: string) => [
    { label: th.teacher.overview, to: '/t' },
    { label: name, to: `/t/c/${classId}` },
    { label: copy.crumb },
  ]

  if (classroom.isPending) {
    return (
      <TeacherPage crumbs={crumbs('…')}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  if (classroom.isError || !classroom.data) {
    const error = classroom.isError ? appErrorOf(classroom.error) : null
    return (
      <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.crumb }]}>
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error
              ? `${error.message}${error.ref ? ` (${th.errors.reference(error.ref)})` : ''}`
              : roomCopy.notFoundBody}
          </span>
        </p>
        <Link to="/t" className={styles.ghostLink}>
          {roomCopy.backToOverview}
        </Link>
      </TeacherPage>
    )
  }

  const c = classroom.data
  const oldTerm = !!term && c.term_id !== term.id
  const homeworkAllowed = term?.status === 'active'
  const teacherName = teachers.data?.find((t) => t.id === c.teacher_id)?.display_name ?? ''
  const requested: PostKind = search.get('kind') === 'announcement' ? 'announcement' : 'homework'
  return (
    <TeacherPage crumbs={crumbs(c.name)}>
      <div className={styles.head}>
        <span className={styles.eyebrow}>{copy.eyebrow(c.name)}</span>
        <h1>{copy.title}</h1>
        <p>{copy.intro}</p>
      </div>
      {oldTerm || !term ? (
        <>
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{copy.oldTerm}</span>
          </p>
          <Link to={`/t/c/${c.id}`} className={styles.ghostLink}>
            {copy.backToRoom}
          </Link>
        </>
      ) : (
        <PostForm
          key={c.id}
          classroom={c}
          initialKind={homeworkAllowed ? requested : 'announcement'}
          homeworkAllowed={homeworkAllowed}
          adminMode={adminMode}
          teacherName={teacherName}
        />
      )}
    </TeacherPage>
  )
}

function PostForm({
  classroom: c,
  initialKind,
  homeworkAllowed,
  adminMode,
  teacherName,
}: {
  classroom: Classroom
  initialKind: PostKind
  homeworkAllowed: boolean
  adminMode: boolean
  teacherName: string
}) {
  const copy = th.posts.create
  const [values, setValues] = useState<PostFormValues>(() => defaultPostForm(initialKind))
  const [errors, setErrors] = useState<Partial<Record<PostField, string>>>({})
  const [formError, setFormError] = useState<string | null>(null)
  const titleRef = useRef<HTMLInputElement>(null)
  const bodyRef = useRef<HTMLTextAreaElement>(null)
  const fullScoreRef = useRef<HTMLInputElement>(null)
  const latePctRef = useRef<HTMLInputElement>(null)
  const dueRef = useRef<HTMLInputElement>(null)
  const closeRef = useRef<HTMLInputElement>(null)
  // ช่องโทเคนเป็นปุ่ม −/+ ไม่มีช่องให้โฟกัส ข้อความผิดพลาดอยู่ใต้แถวรางวัล
  const focusField = (field: PostField) => {
    const targets: Partial<Record<PostField, RefObject<HTMLElement | null>>> = {
      title: titleRef,
      body: bodyRef,
      fullScore: fullScoreRef,
      latePct: latePctRef,
      due: dueRef,
      close: closeRef,
    }
    targets[field]?.current?.focus()
  }
  // ส่งซ้ำด้วยเนื้อหาเดิมใช้ request key เดิม → ไม่เกิดโพสต์ซ้ำ (เหมือน T09)
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const toast = useToast()
  const homework = values.kind === 'homework'

  const set = <K extends keyof PostFormValues>(
    key: K,
    value: PostFormValues[K],
    field?: PostField,
  ) => {
    setValues((v) => ({ ...v, [key]: value }))
    if (field && errors[field]) setErrors((e) => ({ ...e, [field]: undefined }))
  }

  const mutation = useMutation({
    mutationFn: createPost,
    onSuccess: async (created) => {
      await queryClient.invalidateQueries({ queryKey: ['posts', c.id] })
      toast(copy.posted[created.kind](created.title), { tone: 'success' })
      navigate(`/t/c/${c.id}?tab=${created.kind === 'homework' ? 'work' : 'general'}`)
    },
    onError: async (error) => {
      const e = appErrorOf(error)
      setFormError(e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : ''))
      // ภาคเรียนเปลี่ยนสถานะระหว่างกรอก → โหลดสถานะใหม่ให้ฟอร์มตรงกับกติกา K5 (UX 7.1)
      if (e.code === 'term_ended') await queryClient.invalidateQueries({ queryKey: ['term'] })
    },
  })

  const applyScriptTo = (kind: ScriptKind) => {
    const box = bodyRef.current
    if (!box) return
    const result = applyScript(values.body, box.selectionStart ?? 0, box.selectionEnd ?? 0, kind)
    if (!result) {
      toast(copy.selectFirst)
      box.focus()
      return
    }
    set('body', result.value, 'body')
    requestAnimationFrame(() => {
      box.focus()
      box.setSelectionRange(result.start, result.end)
    })
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (mutation.isPending) return
    const result = validatePostForm(values)
    const messages = Object.fromEntries(
      Object.entries(result.errors).map(([field, code]) => [field, copy.errors[code]]),
    ) as Partial<Record<PostField, string>>
    setErrors(messages)
    setFormError(null)
    if (!result.payload) {
      const first = FIELD_ORDER.find((field) => messages[field])
      if (first) focusField(first)
      return
    }
    const fingerprint = JSON.stringify([c.id, result.payload])
    if (requestKey.current?.fingerprint !== fingerprint) {
      requestKey.current = { fingerprint, key: crypto.randomUUID() }
    }
    mutation.mutate({
      classroomId: c.id,
      payload: result.payload,
      requestKey: requestKey.current.key,
      adminMode,
    })
  }

  return (
    <div className={styles.createGrid}>
      <Card as="section" padding="none">
        <form className={styles.form} onSubmit={submit} noValidate>
          <div className={styles.group} role="group" aria-labelledby="postKindLabel">
            <span id="postKindLabel" className={styles.groupLabel}>
              {copy.kind}
            </span>
            <div className={styles.seg}>
              {(['homework', 'announcement'] as const).map((kind) => {
                const disabled = kind === 'homework' && !homeworkAllowed
                return (
                  <button
                    key={kind}
                    type="button"
                    aria-pressed={values.kind === kind}
                    aria-disabled={disabled || undefined}
                    onClick={() => {
                      if (disabled) return
                      set('kind', kind)
                      setErrors({})
                    }}
                  >
                    {kind === 'homework' ? (
                      <FilePen aria-hidden="true" />
                    ) : (
                      <Megaphone aria-hidden="true" />
                    )}
                    {copy.kinds[kind]}
                  </button>
                )
              })}
            </div>
            {!homeworkAllowed && <p className={styles.small}>{copy.termEndedHomework}</p>}
          </div>

          <Field label={copy.titleLabel[values.kind]} error={errors.title}>
            <Input
              ref={titleRef}
              value={values.title}
              onChange={(e) => set('title', e.target.value, 'title')}
              maxLength={POST_LIMITS.titleMax}
              autoComplete="off"
              required
            />
          </Field>

          <Field
            label={copy.bodyLabel[values.kind]}
            optional={homework}
            hint={copy.bodyHint}
            error={errors.body}
          >
            <div className={styles.toolRow}>
              {(['sub', 'sup'] as const).map((kind) => (
                <button
                  key={kind}
                  type="button"
                  className={styles.tool}
                  // ไม่ดึงโฟกัสออกจากช่องข้อความตอนกด (ช่วงที่เลือกยังอยู่)
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyScriptTo(kind)}
                >
                  {copy[kind]}
                </button>
              ))}
            </div>
            <Textarea
              ref={bodyRef}
              value={values.body}
              onChange={(e) => set('body', e.target.value, 'body')}
              rows={5}
              required={!homework}
            />
          </Field>

          {homework ? (
            <>
              <section className={styles.fsec} aria-labelledby="scoreSection">
                <h2 id="scoreSection">{copy.scoreSection}</h2>
                <div className={styles.fgrid}>
                  <Field label={copy.fullScore} hint={copy.fullScoreHint} error={errors.fullScore}>
                    <Input
                      ref={fullScoreRef}
                      className={styles.num}
                      inputMode="numeric"
                      value={values.fullScore}
                      onChange={(e) => set('fullScore', e.target.value, 'fullScore')}
                      autoComplete="off"
                    />
                  </Field>
                  <Field label={copy.latePct} hint={copy.latePctHint} error={errors.latePct}>
                    <Input
                      ref={latePctRef}
                      className={styles.num}
                      inputMode="numeric"
                      value={values.latePct}
                      onChange={(e) => set('latePct', e.target.value, 'latePct')}
                      autoComplete="off"
                    />
                  </Field>
                  <Field
                    className={styles.full}
                    label={copy.due}
                    hint={copy.dueHint}
                    error={errors.due}
                  >
                    <div className={styles.dt}>
                      <Input
                        ref={dueRef}
                        type="date"
                        value={values.dueDate}
                        onChange={(e) => set('dueDate', e.target.value, 'due')}
                      />
                      <Input
                        id="postDueTime"
                        type="time"
                        aria-label={copy.dueTimeAria}
                        value={values.dueTime}
                        onChange={(e) => set('dueTime', e.target.value, 'due')}
                      />
                    </div>
                  </Field>
                  <label className={`${styles.switchRow} ${styles.full}`}>
                    <span>
                      <b>{copy.hasClose}</b>
                      <span>{copy.hasCloseHint}</span>
                    </span>
                    <input
                      type="checkbox"
                      role="switch"
                      className={styles.switch}
                      checked={values.hasClose}
                      onChange={(e) => set('hasClose', e.target.checked, 'close')}
                    />
                  </label>
                  {values.hasClose && (
                    <Field className={styles.full} label={copy.close} error={errors.close}>
                      <div className={styles.dt}>
                        <Input
                          ref={closeRef}
                          type="date"
                          value={values.closeDate}
                          onChange={(e) => set('closeDate', e.target.value, 'close')}
                        />
                        <Input
                          id="postCloseTime"
                          type="time"
                          aria-label={copy.closeTimeAria}
                          value={values.closeTime}
                          onChange={(e) => set('closeTime', e.target.value, 'close')}
                        />
                      </div>
                    </Field>
                  )}
                </div>
              </section>
              <section className={styles.fsec} aria-labelledby="rewardSection">
                <h2 id="rewardSection">{copy.rewardSection}</h2>
                <div className={styles.rewardEdit}>
                  <span className={styles.coin} aria-hidden="true">
                    <Sparkles />
                  </span>
                  <span className={styles.rewardText}>
                    <b>{copy.reward}</b>
                    <span>{copy.rewardHint}</span>
                  </span>
                  <Stepper
                    label={copy.rewardLabel}
                    value={values.reward}
                    min={POST_LIMITS.rewardMin}
                    max={POST_LIMITS.rewardMax}
                    onChange={(n) => set('reward', n, 'reward')}
                  />
                </div>
                {errors.reward && (
                  <p className={styles.fieldError} role="alert">
                    <TriangleAlert aria-hidden="true" />
                    <span>{errors.reward}</span>
                  </p>
                )}
                <label className={styles.switchRow}>
                  <span>
                    <b>{copy.afterSolution}</b>
                    <span>{copy.afterSolutionHint}</span>
                  </span>
                  <input
                    type="checkbox"
                    role="switch"
                    className={styles.switch}
                    checked={values.acceptAfterSolution}
                    onChange={(e) => set('acceptAfterSolution', e.target.checked)}
                  />
                </label>
                <p className={styles.note} data-tone="plain">
                  <Info aria-hidden="true" />
                  <span>{copy.solutionNote}</span>
                </p>
              </section>
            </>
          ) : (
            <p className={styles.note} data-tone="plain">
              <Info aria-hidden="true" />
              <span>{copy.announcementNote}</span>
            </p>
          )}

          <div className={styles.formFoot}>
            {formError && (
              <p className={styles.alert} role="alert">
                <TriangleAlert aria-hidden="true" />
                <span>{formError}</span>
              </p>
            )}
            <Link to={`/t/c/${c.id}`} className={styles.ghostLink}>
              {copy.cancel}
            </Link>
            <button type="submit" className={styles.submit} disabled={mutation.isPending}>
              <Send aria-hidden="true" />
              {mutation.isPending ? copy.submitting : copy.submit[values.kind]}
            </button>
          </div>
        </form>
      </Card>
      <Preview values={values} teacherName={teacherName} />
    </div>
  )
}

// ตัวอย่างฝั่งนักเรียน + ข้อความแจ้งเตือนตามเวลาที่เหลือ (J7)
function Preview({ values, teacherName }: { values: PostFormValues; teacherName: string }) {
  const copy = th.posts.create
  const dueAt = bangkokToUtcIso(values.dueDate, values.dueTime)
  const closeAt = values.hasClose ? bangkokToUtcIso(values.closeDate, values.closeTime) : null
  const reminder = values.kind === 'homework' ? dueReminder(dueAt) : null
  const list = th.posts.list
  return (
    <aside className={styles.previewWrap} aria-labelledby="postPreviewTitle">
      <h2 id="postPreviewTitle">{copy.preview}</h2>
      <div className={styles.miniPhone}>
        <span className={styles.eyebrow}>{copy.previewEyebrow[values.kind]}</span>
        {values.kind === 'homework' ? (
          <>
            <div className={styles.workCard}>
              <span className={styles.wIc} aria-hidden="true">
                <FilePen />
              </span>
              <div className={styles.workText}>
                <b className={styles.workTitle}>{values.title.trim() || copy.previewTitle}</b>
                {dueAt && (
                  <span className={styles.meta}>{list.due(thaiDate(dueAt), thaiTime(dueAt))}</span>
                )}
                <span className={styles.chips}>
                  <Chip tone="amber" icon={<FilePen />}>
                    {list.notSubmitted}
                  </Chip>
                  {values.reward > 0 && (
                    <Chip tone="gold" icon={<Sparkles />}>
                      {list.reward(values.reward)}
                    </Chip>
                  )}
                </span>
              </div>
            </div>
            <div className={styles.previewDetail}>
              <span className={styles.eyebrow}>{copy.previewScore(values.fullScore.trim())}</span>
              {values.body.trim() && <p className={styles.postBody}>{values.body}</p>}
              <span className={styles.chips}>
                <Chip tone="plain" icon={<CalendarClock />}>
                  {closeAt ? list.closeAt(thaiDate(closeAt), thaiTime(closeAt)) : list.noClose}
                </Chip>
                <Chip tone="plain">{list.latePct(Number(values.latePct) || 0)}</Chip>
              </span>
            </div>
          </>
        ) : (
          <article className={styles.post}>
            <div className={styles.postHead}>
              <span className={styles.avatar} aria-hidden="true">
                {initialOf(teacherName)}
              </span>
              <span>
                <b>{teacherName}</b>
                <span>{copy.justPosted}</span>
              </span>
            </div>
            {values.title.trim() && <b className={styles.postTitle}>{values.title}</b>}
            <p className={styles.postBody}>{values.body.trim() || copy.previewBody}</p>
          </article>
        )}
        {values.kind === 'announcement' ? (
          <p className={styles.note} data-tone="plain">
            <Bell aria-hidden="true" />
            <span>{copy.remind.announcement}</span>
          </p>
        ) : (
          reminder && (
            <p className={styles.note} data-tone={reminder === 'past' ? 'amber' : 'plain'}>
              {reminder === 'past' ? (
                <TriangleAlert aria-hidden="true" />
              ) : (
                <Bell aria-hidden="true" />
              )}
              <span>{copy.remind[reminder]}</span>
            </p>
          )
        )}
      </div>
    </aside>
  )
}
