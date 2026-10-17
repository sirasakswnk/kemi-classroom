import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, Clock, Info, Lock, Pencil, RotateCcw, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip, Field, Input, Textarea, useToast } from '../../ui'
import { editablePostQuery } from '../posts/api'
import type { StatusRow } from '../review/api'
import { gradeKey, gradeQuery, gradeSubmission, type Grade } from './api'
import { evaluateDraft, formulaParts, initialDraft, REASON_MAX, type GradeDraft } from './gradeForm'
import styles from './grading.module.css'

// แผงผลตรวจของ T03 (P4-04): คะแนนก่อนหัก + สูตรหักส่งช้า + ปรับเฉพาะคน (งานสายเท่านั้น) + ยืนยันงานครบถ้วน
// ระยะ 4 ยังไม่มีโทเคน จึงยังไม่มีกล่องผลต่อรางวัลของแบบ v2 (มากับระยะ 5)

interface Props {
  postId: string
  row: StatusRow & { submission_id: string }
  adminMode: boolean
}

export function GradePanel({ postId, row, adminMode }: Props) {
  const post = useQuery(editablePostQuery(postId))
  const grade = useQuery(gradeQuery(row.submission_id))
  if (post.isPending || grade.isPending) {
    return (
      <p role="status" className={styles.muted}>
        {th.common.loading}
      </p>
    )
  }
  const error = post.isError
    ? appErrorOf(post.error)
    : grade.isError
      ? appErrorOf(grade.error)
      : null
  const assignment = post.data?.assignment
  if (error || !assignment) {
    return <ErrorNote error={error} />
  }
  // key: ร่างเริ่มใหม่เมื่อเปลี่ยนคน; บันทึกสำเร็จตั้งร่างจากผลที่บันทึก — โหลดข้อมูลล่าสุด (stale_revision) ไม่ล้างสิ่งที่พิมพ์ (UX 7.1)
  return (
    <GradeForm
      key={row.submission_id}
      postId={postId}
      row={row}
      adminMode={adminMode}
      grade={grade.data ?? null}
      fullScore={assignment.full_score}
      latePct={assignment.late_penalty_pct}
      fullScoreLocked={!!assignment.full_score_locked_at}
    />
  )
}

function GradeForm({
  postId,
  row,
  adminMode,
  grade,
  fullScore,
  latePct,
  fullScoreLocked,
}: Props & { grade: Grade | null; fullScore: number; latePct: number; fullScoreLocked: boolean }) {
  const copy = th.grading
  const queryClient = useQueryClient()
  const toast = useToast()
  const timing = row.timing ?? 'on_time'
  const ctx = { fullScore, latePct, timing, storedOverride: grade?.penalty_override_pct ?? null }
  const [draft, setDraft] = useState<GradeDraft>(() => initialDraft(grade, timing))
  const [serverError, setServerError] = useState<AppError | null>(null)
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const rawRef = useRef<HTMLInputElement>(null)
  const reasonRef = useRef<HTMLTextAreaElement>(null)
  const result = evaluateDraft(ctx, draft)
  const formula = formulaParts(result.raw, result.pct)
  const reasonLength = [...draft.reason.trim()].length
  const set = <K extends keyof GradeDraft>(key: K, value: GradeDraft[K]) => {
    setDraft((d) => ({ ...d, [key]: value }))
    setServerError(null)
  }

  const save = useMutation({
    mutationFn: () => {
      const payload = {
        submissionId: row.submission_id,
        raw: result.raw,
        pass: draft.pass,
        overridePct: result.overridePct,
        reason: result.reasonNeeded ? draft.reason.trim() : null,
        seenRevision: row.content_revision ?? 1,
        expectedVersion: grade?.version ?? 0,
        adminMode,
      }
      // คำขอเดิมที่เน็ตหลุดใช้ key เดิม (ได้ผลเดิม) — แก้ข้อมูลแล้วได้ key ใหม่
      const fingerprint = JSON.stringify(payload)
      if (requestKey.current?.fingerprint !== fingerprint)
        requestKey.current = { fingerprint, key: crypto.randomUUID() }
      return gradeSubmission({ ...payload, requestKey: requestKey.current.key })
    },
    onSuccess: async (saved) => {
      setDraft(initialDraft(saved, saved.timing))
      toast(copy.saved, { tone: 'success' })
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: gradeKey(row.submission_id) }),
        queryClient.invalidateQueries({ queryKey: ['submission-list', postId] }),
        queryClient.invalidateQueries({ queryKey: ['post-edit', postId] }),
        queryClient.invalidateQueries({ queryKey: ['work-summary'] }),
      ])
    },
    onError: (err) => {
      const e = appErrorOf(err)
      setServerError(e)
      if (e.code === 'score_invalid') rawRef.current?.focus()
      if (e.code === 'reason_required') reasonRef.current?.focus()
      // งานกลายเป็นทัน/ถูกส่งแก้: โหลดสถานะล่าสุด (ร่างที่พิมพ์ยังอยู่จนผลตรวจเปลี่ยนรุ่น)
      if (e.code === 'penalty_not_late')
        void queryClient.invalidateQueries({ queryKey: ['submission-list', postId] })
    },
  })

  const reload = () => {
    setServerError(null)
    void queryClient.invalidateQueries({ queryKey: ['submission-list', postId] })
    void queryClient.invalidateQueries({ queryKey: gradeKey(row.submission_id) })
  }

  const rawError =
    result.problems.includes('raw') || serverError?.code === 'score_invalid'
      ? copy.scoreRange(fullScore)
      : undefined
  const reasonError =
    serverError?.code === 'comment_too_long' || result.problems.includes('reason_too_long')
      ? th.errors.comment_too_long
      : serverError?.code === 'reason_required'
        ? th.errors.reason_required
        : undefined
  const fieldCodes = ['score_invalid', 'comment_too_long', 'reason_required']
  const blocked = result.problems.length > 0
  const graded = !!grade
  const oldRevision = grade && grade.graded_revision < (row.content_revision ?? 1)

  return (
    <form
      className={styles.panel}
      aria-label={copy.title}
      onSubmit={(e) => {
        e.preventDefault()
        if (!blocked && !save.isPending) save.mutate()
      }}
    >
      <div className={styles.chips}>
        {row.last_submitted_at && (
          <Chip tone="plain" icon={<Clock />}>
            {thaiDate(row.first_submitted_at ?? row.last_submitted_at)}{' '}
            {thaiTime(row.first_submitted_at ?? row.last_submitted_at)} น.
          </Chip>
        )}
        {timing === 'late' ? (
          <Chip tone="red">{copy.chipLate}</Chip>
        ) : (
          <Chip tone="green">{copy.chipOnTime}</Chip>
        )}
        {graded && !oldRevision && <Chip tone="purple">{copy.chipGraded}</Chip>}
      </div>
      {oldRevision && (
        <p className={styles.note}>
          <Info aria-hidden="true" />
          <span>{copy.oldRevision(grade.graded_revision)}</span>
        </p>
      )}

      <Field label={copy.rawLabel} hint={graded ? copy.savedHint : copy.rawHint} error={rawError}>
        <span className={styles.scoreIn}>
          <Input
            ref={rawRef}
            inputMode="numeric"
            autoComplete="off"
            placeholder="–"
            value={draft.raw}
            onChange={(e) => set('raw', e.target.value)}
          />
          <span>{copy.outOf(fullScore)}</span>
        </span>
      </Field>

      {timing === 'late' ? (
        <>
          <div className={styles.calc}>
            <div className={styles.calcRow}>
              <span>{copy.latePenalty}</span>
              <span>{copy.penaltyOf(result.pct, result.override)}</span>
            </div>
            {result.raw != null && (
              <div className={styles.calcRow}>
                <span>{formula ? formula.expression : copy.noDeduct}</span>
                <span>
                  {formula
                    ? formula.rounded
                      ? copy.roundUp(formula.net)
                      : formula.net
                    : result.raw}
                </span>
              </div>
            )}
            <div className={styles.calcRow} data-total>
              <span>{copy.net}</span>
              <span>{copy.netValue(result.net, fullScore)}</span>
            </div>
          </div>
          {draft.overrideOpen ? (
            <div className={styles.override}>
              <div className={styles.overrideRow}>
                <Field
                  label={copy.overrideLabel}
                  error={result.problems.includes('override') ? copy.overrideInvalid : undefined}
                >
                  <span className={styles.scoreIn}>
                    <Input
                      inputMode="numeric"
                      autoComplete="off"
                      placeholder={String(latePct)}
                      value={draft.overrideText}
                      onChange={(e) => set('overrideText', e.target.value)}
                    />
                    <span>%</span>
                  </span>
                </Field>
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onClick={() => set('overrideText', '0')}
                >
                  {copy.exemptButton}
                </Button>
              </div>
              {result.reasonNeeded && (
                <Field
                  label={copy.reasonLabel}
                  error={reasonError}
                  hint={
                    REASON_MAX - reasonLength < 200
                      ? copy.reasonLeft(Math.max(0, REASON_MAX - reasonLength))
                      : undefined
                  }
                >
                  <Textarea
                    ref={reasonRef}
                    rows={3}
                    placeholder={copy.reasonPlaceholder}
                    value={draft.reason}
                    onChange={(e) => set('reason', e.target.value)}
                  />
                </Field>
              )}
              <button
                type="button"
                className={styles.link}
                onClick={() => setDraft((d) => ({ ...d, overrideOpen: false, overrideText: '' }))}
              >
                {copy.useAssignment(latePct)}
              </button>
            </div>
          ) : (
            <>
              <button
                type="button"
                className={styles.link}
                onClick={() => set('overrideOpen', true)}
              >
                <Pencil aria-hidden="true" />
                {copy.adjust}
              </button>
              {result.reasonNeeded && (
                // ล้างค่าที่บันทึกไว้ (กลับไปใช้ของงาน) ก็ต้องมีเหตุผล
                <Field label={copy.reasonLabel} error={reasonError}>
                  <Textarea
                    ref={reasonRef}
                    rows={3}
                    placeholder={copy.reasonPlaceholder}
                    value={draft.reason}
                    onChange={(e) => set('reason', e.target.value)}
                  />
                </Field>
              )}
            </>
          )}
        </>
      ) : (
        <div className={styles.calc}>
          <div className={styles.calcRow} data-total>
            <span>{copy.netOnTime}</span>
            <span>{copy.netValue(result.net, fullScore)}</span>
          </div>
        </div>
      )}

      {!fullScoreLocked && (
        <p className={styles.hint}>
          <Lock aria-hidden="true" />
          <span>{copy.firstLock}</span>
        </p>
      )}

      <label className={styles.passRow}>
        <input
          type="checkbox"
          checked={draft.pass}
          onChange={(e) => set('pass', e.target.checked)}
        />
        <span>
          <b>{copy.passLabel}</b>
          <span>{copy.passHint}</span>
        </span>
      </label>

      {serverError && !fieldCodes.includes(serverError.code) && (
        <ErrorNote error={serverError} onReload={reload} />
      )}

      <div className={styles.actions}>
        <Button type="submit" icon={<Check />} disabled={blocked || save.isPending}>
          {save.isPending ? copy.saving : graded ? copy.saveEdit : copy.save}
        </Button>
      </div>
      {result.problems.includes('reason') && <p className={styles.muted}>{copy.reasonRequired}</p>}
      {result.problems.includes('empty') && <p className={styles.muted}>{copy.needSomething}</p>}
    </form>
  )
}

function ErrorNote({ error, onReload }: { error: AppError | null; onReload?: () => void }) {
  return (
    <div className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {error?.message ?? th.errors.fallback}
        {error?.ref && ` (${th.errors.reference(error.ref)})`}
      </span>
      {onReload && (error?.action === 'reload_latest' || error?.action === 'reload') && (
        <Button type="button" size="sm" variant="ghost" icon={<RotateCcw />} onClick={onReload}>
          {th.grading.reload}
        </Button>
      )}
    </div>
  )
}
