import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Bell,
  CalendarClock,
  Check,
  FilePen,
  Info,
  Lock,
  Megaphone,
  RefreshCw,
  Send,
  Sparkles,
  TriangleAlert,
} from 'lucide-react'
import { useRef, useState, type FormEvent, type RefObject } from 'react'
import { Link, useNavigate } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { appErrorOf } from '../../lib/request'
import { bangkokToUtcIso, thaiDate, thaiTime } from '../../lib/thaiTime'
import { Card, Chip, Field, Input, Stepper, Textarea, useToast } from '../../ui'
import type { Classroom } from '../classrooms/api'
import { createPost, updatePost } from './api'
import {
  defaultPostForm,
  dueReminder,
  FIELD_ORDER,
  formFromPost,
  locksOf,
  POST_LIMITS,
  SERVER_FIELD,
  toUpdatePayload,
  validatePostForm,
  withLockedValues,
  type EditablePost,
  type PostField,
  type PostFormValues,
  type PostKind,
} from './postForm'
import { applyScript, type ScriptKind } from './script'
import styles from './posts.module.css'

// ฟอร์ม T02 ใช้ทั้งสร้าง (P3-02) และแก้ไข (P3-02b, N2) — UX_DESIGN ส่วน 9
// โหมดแก้ไข: ซ่อนตัวเลือกชนิด, ช่องที่ล็อกเป็นสีจางพร้อมเหตุผลและส่งค่าล่าสุดจากเซิร์ฟเวอร์เสมอ, กำหนดส่ง/วันปิดรับ
// เป็นข้อความอย่างเดียว (ปุ่ม M1/M2 มากับ P4-03), version ที่ส่งคือของตอนเปิดฟอร์ม (เปลี่ยนเมื่อกด “โหลดข้อมูลล่าสุด”
// เท่านั้น — การโหลดเบื้องหลังจึงไม่กลืนการแก้จากหน้าจออื่น)
export type PostEditorMode =
  | { kind: 'create'; initialKind: PostKind; homeworkAllowed: boolean }
  | {
      kind: 'edit'
      /** ข้อมูลล่าสุดจาก query (สถานะล็อกอัปเดตตามนี้) */
      post: EditablePost
      /** โหลดโพสต์ใหม่จากเซิร์ฟเวอร์ คืนค่าล่าสุด */
      reload: () => Promise<EditablePost | null | undefined>
    }

const LOCK_CODES = new Set(['full_score_locked', 'reward_locked', 'after_solution_locked'])

export function PostEditor({
  classroom: c,
  teacherName,
  adminMode,
  mode,
}: {
  classroom: Classroom
  teacherName: string
  adminMode: boolean
  mode: PostEditorMode
}) {
  const copy = th.posts.create
  const editCopy = th.posts.edit
  const editing = mode.kind === 'edit'
  const [values, setValues] = useState<PostFormValues>(() =>
    mode.kind === 'edit' ? formFromPost(mode.post) : defaultPostForm(mode.initialKind),
  )
  // version และชนิดที่ใช้ส่ง (ของตอนเปิดฟอร์มหรือตอนกดโหลดข้อมูลล่าสุด)
  const [base, setBase] = useState<EditablePost | null>(mode.kind === 'edit' ? mode.post : null)
  const [errors, setErrors] = useState<Partial<Record<PostField, string>>>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [stale, setStale] = useState(false)
  const [staleDraft, setStaleDraft] = useState<string | null>(null)
  const titleRef = useRef<HTMLInputElement>(null)
  const bodyRef = useRef<HTMLTextAreaElement>(null)
  const fullScoreRef = useRef<HTMLInputElement>(null)
  const latePctRef = useRef<HTMLInputElement>(null)
  const dueRef = useRef<HTMLInputElement>(null)
  const closeRef = useRef<HTMLInputElement>(null)
  // ช่องโทเคน/รับหลังเฉลยเป็นปุ่ม ไม่ย้ายโฟกัส ข้อความผิดพลาดอยู่ใต้แถวนั้น
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
  // ส่งซ้ำด้วยเนื้อหาเดิมใช้ request key เดิม → ไม่เกิดโพสต์ซ้ำ/ได้ผลเดิม
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const toast = useToast()

  const latest = mode.kind === 'edit' ? mode.post : null
  const locks = latest ? locksOf(latest) : { fullScore: false, reward: false, afterSolution: false }
  const shown = latest ? withLockedValues(values, latest) : values
  const homework = shown.kind === 'homework'
  const roomTab = (kind: PostKind) => `/t/c/${c.id}?tab=${kind === 'homework' ? 'work' : 'general'}`

  const set = <K extends keyof PostFormValues>(
    key: K,
    value: PostFormValues[K],
    field?: PostField,
  ) => {
    setValues((v) => ({ ...v, [key]: value }))
    if (field && errors[field]) setErrors((e) => ({ ...e, [field]: undefined }))
  }

  const showServerError = async (error: unknown) => {
    const e = appErrorOf(error)
    const field = SERVER_FIELD[e.code]
    if (e.code === 'stale_revision') {
      setStale(true)
      setFormError(e.message)
      return
    }
    if (field) {
      setErrors((x) => ({ ...x, [field]: e.message }))
      setFormError(null)
      // ช่องล็อกระหว่างเปิดฟอร์ม: เปลี่ยนเป็นค่าล่าสุดสีจาง เก็บค่าที่พิมพ์ในช่องอื่นไว้ (UX 9)
      if (LOCK_CODES.has(e.code) && mode.kind === 'edit') {
        const fresh = await mode.reload()
        if (fresh) setValues((v) => withLockedValues(v, fresh))
      } else {
        focusField(field)
      }
      return
    }
    setFormError(e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : ''))
    // ภาคเรียนเปลี่ยนสถานะระหว่างกรอก → โหลดสถานะใหม่ให้ฟอร์มตรงกับกติกา K5 (UX 7.1)
    if (e.code === 'term_ended') await queryClient.invalidateQueries({ queryKey: ['term'] })
  }

  const createMutation = useMutation({
    mutationFn: createPost,
    onSuccess: async (created) => {
      await queryClient.invalidateQueries({ queryKey: ['posts', c.id] })
      toast(copy.posted[created.kind](created.title), { tone: 'success' })
      navigate(roomTab(created.kind))
    },
    onError: showServerError,
  })
  const updateMutation = useMutation({
    mutationFn: updatePost,
    onSuccess: async (updated) => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['posts', c.id] }),
        queryClient.invalidateQueries({ queryKey: ['post-edit', updated.post_id] }),
      ])
      toast(updated.changed ? editCopy.saved : editCopy.unchanged, {
        tone: updated.changed ? 'success' : undefined,
      })
      navigate(roomTab(updated.kind))
    },
    onError: showServerError,
  })
  const pending = createMutation.isPending || updateMutation.isPending

  const reloadLatest = async () => {
    if (mode.kind !== 'edit') return
    const fresh = await mode.reload()
    if (!fresh) return
    // เก็บสิ่งที่พิมพ์ไว้ให้คัดลอกได้ (UX 7.1 stale_revision) แล้วเริ่มจากข้อมูลล่าสุด
    setStaleDraft([values.title, values.body].filter((x) => x.trim()).join('\n\n'))
    setBase(fresh)
    setValues(formFromPost(fresh))
    setErrors({})
    setFormError(null)
    setStale(false)
  }

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
    if (pending) return
    const result = validatePostForm(shown)
    const messages = Object.fromEntries(
      Object.entries(result.errors).map(([field, code]) => [field, th.errors[code]]),
    ) as Partial<Record<PostField, string>>
    setErrors(messages)
    setFormError(null)
    setStale(false)
    if (!result.payload) {
      const first = FIELD_ORDER.find((field) => messages[field])
      if (first) focusField(first)
      return
    }
    if (mode.kind === 'edit' && base) {
      const payload = toUpdatePayload(result.payload)
      const fingerprint = JSON.stringify(['edit', base.id, base.version, payload])
      if (requestKey.current?.fingerprint !== fingerprint) {
        requestKey.current = { fingerprint, key: crypto.randomUUID() }
      }
      updateMutation.mutate({
        postId: base.id,
        payload,
        expectedVersion: base.version,
        requestKey: requestKey.current.key,
        adminMode,
      })
      return
    }
    const fingerprint = JSON.stringify(['create', c.id, result.payload])
    if (requestKey.current?.fingerprint !== fingerprint) {
      requestKey.current = { fingerprint, key: crypto.randomUUID() }
    }
    createMutation.mutate({
      classroomId: c.id,
      payload: result.payload,
      requestKey: requestKey.current.key,
      adminMode,
    })
  }

  const lockHint = (text: string) => (
    <span className={styles.lockHint}>
      <Lock aria-hidden="true" />
      {text}
    </span>
  )
  const dueAt = latest?.assignment?.due_at ?? null
  const closeAt = latest?.assignment?.close_at ?? null

  return (
    <div className={styles.createGrid}>
      <Card as="section" padding="none">
        <form className={styles.form} onSubmit={submit} noValidate>
          {mode.kind === 'create' && (
            <div className={styles.group} role="group" aria-labelledby="postKindLabel">
              <span id="postKindLabel" className={styles.groupLabel}>
                {copy.kind}
              </span>
              <div className={styles.seg}>
                {(['homework', 'announcement'] as const).map((kind) => {
                  const disabled = kind === 'homework' && !mode.homeworkAllowed
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
              {!mode.homeworkAllowed && <p className={styles.small}>{copy.termEndedHomework}</p>}
            </div>
          )}

          <Field label={copy.titleLabel[shown.kind]} error={errors.title}>
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
            label={copy.bodyLabel[shown.kind]}
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
                  <Field
                    label={copy.fullScore}
                    hint={locks.fullScore ? lockHint(editCopy.lockedScore) : copy.fullScoreHint}
                    error={errors.fullScore}
                  >
                    <Input
                      ref={fullScoreRef}
                      className={styles.num}
                      inputMode="numeric"
                      value={shown.fullScore}
                      disabled={locks.fullScore}
                      onChange={(e) => set('fullScore', e.target.value, 'fullScore')}
                      autoComplete="off"
                    />
                  </Field>
                  <Field
                    label={copy.latePct}
                    hint={locks.fullScore ? lockHint(editCopy.lockedScore) : copy.latePctHint}
                    error={errors.latePct}
                  >
                    <Input
                      ref={latePctRef}
                      className={styles.num}
                      inputMode="numeric"
                      value={shown.latePct}
                      disabled={locks.fullScore}
                      onChange={(e) => set('latePct', e.target.value, 'latePct')}
                      autoComplete="off"
                    />
                  </Field>
                  {editing ? (
                    <dl className={`${styles.readonlyList} ${styles.full}`}>
                      <div>
                        <dt>{copy.due}</dt>
                        <dd>{dueAt && editCopy.dueText(thaiDate(dueAt), thaiTime(dueAt))}</dd>
                      </div>
                      <div>
                        <dt>{copy.close}</dt>
                        <dd>
                          {closeAt
                            ? editCopy.dueText(thaiDate(closeAt), thaiTime(closeAt))
                            : editCopy.noClose}
                        </dd>
                      </div>
                    </dl>
                  ) : (
                    <>
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
                    </>
                  )}
                </div>
              </section>
              <section className={styles.fsec} aria-labelledby="rewardSection">
                <h2 id="rewardSection">{copy.rewardSection}</h2>
                <div className={styles.rewardEdit} data-locked={locks.reward || undefined}>
                  <span className={styles.coin} aria-hidden="true">
                    <Sparkles />
                  </span>
                  <span className={styles.rewardText}>
                    <b>{copy.reward}</b>
                    <span>{locks.reward ? lockHint(editCopy.lockedReward) : copy.rewardHint}</span>
                  </span>
                  <Stepper
                    label={copy.rewardLabel}
                    value={shown.reward}
                    min={POST_LIMITS.rewardMin}
                    max={POST_LIMITS.rewardMax}
                    disabled={locks.reward}
                    onChange={(n) => set('reward', n, 'reward')}
                  />
                </div>
                {errors.reward && <FieldError text={errors.reward} />}
                <label className={styles.switchRow} data-locked={locks.afterSolution || undefined}>
                  <span>
                    <b>{copy.afterSolution}</b>
                    <span>
                      {locks.afterSolution
                        ? lockHint(editCopy.lockedAfterSolution)
                        : copy.afterSolutionHint}
                    </span>
                  </span>
                  <input
                    type="checkbox"
                    role="switch"
                    className={styles.switch}
                    checked={shown.acceptAfterSolution}
                    disabled={locks.afterSolution}
                    onChange={(e) => set('acceptAfterSolution', e.target.checked, 'afterSolution')}
                  />
                </label>
                {errors.afterSolution && <FieldError text={errors.afterSolution} />}
                {!editing && (
                  <p className={styles.note} data-tone="plain">
                    <Info aria-hidden="true" />
                    <span>{copy.solutionNote}</span>
                  </p>
                )}
              </section>
            </>
          ) : (
            !editing && (
              <p className={styles.note} data-tone="plain">
                <Info aria-hidden="true" />
                <span>{copy.announcementNote}</span>
              </p>
            )
          )}

          {staleDraft && (
            <Field label={editCopy.staleDraft}>
              <Textarea value={staleDraft} readOnly rows={4} />
            </Field>
          )}

          <div className={styles.formFoot}>
            {formError && (
              <div className={styles.alert} role="alert">
                <TriangleAlert aria-hidden="true" />
                <span>{formError}</span>
                {stale && (
                  <button
                    type="button"
                    className={styles.alertAction}
                    onClick={() => void reloadLatest()}
                  >
                    <RefreshCw aria-hidden="true" />
                    {th.errors.reloadLatest}
                  </button>
                )}
              </div>
            )}
            <Link to={roomTab(shown.kind)} className={styles.ghostLink}>
              {copy.cancel}
            </Link>
            <button type="submit" className={styles.submit} disabled={pending}>
              {editing ? <Check aria-hidden="true" /> : <Send aria-hidden="true" />}
              {editing
                ? updateMutation.isPending
                  ? editCopy.submitting
                  : editCopy.submit
                : createMutation.isPending
                  ? copy.submitting
                  : copy.submit[shown.kind]}
            </button>
          </div>
        </form>
      </Card>
      <Preview values={shown} teacherName={teacherName} editing={editing} closeAtSaved={closeAt} />
    </div>
  )
}

function FieldError({ text }: { text: string }) {
  return (
    <p className={styles.fieldError} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>{text}</span>
    </p>
  )
}

// ตัวอย่างฝั่งนักเรียน + ข้อความแจ้งเตือนตามเวลาที่เหลือ (J7) — โหมดแก้ไขไม่มีแจ้งเตือน (N1) จึงไม่แสดงข้อความนั้น
function Preview({
  values,
  teacherName,
  editing,
  closeAtSaved,
}: {
  values: PostFormValues
  teacherName: string
  editing: boolean
  closeAtSaved: string | null
}) {
  const copy = th.posts.create
  const dueAt = bangkokToUtcIso(values.dueDate, values.dueTime)
  const closeAt = editing
    ? closeAtSaved
    : values.hasClose
      ? bangkokToUtcIso(values.closeDate, values.closeTime)
      : null
  const reminder = values.kind === 'homework' && !editing ? dueReminder(dueAt) : null
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
        {!editing && values.kind === 'announcement' && (
          <p className={styles.note} data-tone="plain">
            <Bell aria-hidden="true" />
            <span>{copy.remind.announcement}</span>
          </p>
        )}
        {reminder && (
          <p className={styles.note} data-tone={reminder === 'past' ? 'amber' : 'plain'}>
            {reminder === 'past' ? (
              <TriangleAlert aria-hidden="true" />
            ) : (
              <Bell aria-hidden="true" />
            )}
            <span>{copy.remind[reminder]}</span>
          </p>
        )}
      </div>
    </aside>
  )
}
