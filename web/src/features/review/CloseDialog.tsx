import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Info, Lock, LockOpen, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { th } from '../../copy/th'
import { addDays, bangkokParts, bangkokToUtcIso, thaiDate, thaiTime } from '../../lib/thaiTime'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { Button, DatePicker, Field, Modal, TimePicker, useToast } from '../../ui'
import type { Intake } from './api'
import { closeAssignment, refreshAssignment, reopenAssignment } from './assignmentApi'
import styles from './dialogs.module.css'
import { useRequestKey } from './useRequestKey'

// M2 ปิดรับงาน (UX 8–9, ผู้ใช้ยืนยัน 17 ต.ค. 2026):
//   เปิดรับอยู่      → “ปิดรับทันที” (กดยืนยันซ้ำ) หรือ “ตั้งเวลาปิดรับ”; เวลาที่ตั้งไว้เปลี่ยนหรือยกเลิกได้
//   ปิดแล้ว ไม่มีเฉลย → “เปิดรับอีกครั้ง”
//   ช่วงรับหลังเฉลย   → ปิดช่วงนี้ (กดยืนยันซ้ำ)
//   ปิดแล้ว มีเฉลย    → คำอธิบายว่าเปิดเพิ่มได้ผ่านตัวเลือกรับงานหลังเฉลยเท่านั้น

const when = (iso: string) => `${thaiDate(iso)} ${thaiTime(iso)} น.`

export function CloseDialog({
  open,
  onClose,
  postId,
  intake,
  dueAt,
  closeAt,
  solutionPublished,
  acceptAfterSolution,
  notSubmitted,
  waiting,
  adminMode,
}: {
  open: boolean
  onClose: () => void
  postId: string
  intake: Intake
  dueAt: string
  closeAt: string | null
  solutionPublished: boolean
  acceptAfterSolution: boolean
  notSubmitted: number
  waiting: number
  adminMode: boolean
}) {
  const copy = th.workActions.close_
  const queryClient = useQueryClient()
  const toast = useToast()
  const requestKey = useRequestKey()
  const [mode, setMode] = useState<'now' | 'later'>(closeAt ? 'later' : 'now')
  const [confirming, setConfirming] = useState(false)
  // ค่าเริ่ม: เวลาที่ตั้งไว้ หรือ 7 วันหลังกำหนดส่ง (เวลาเดียวกับฟอร์มสร้างงาน — P3-02)
  const start = closeAt ? bangkokParts(closeAt) : bangkokParts(dueAt)
  const [date, setDate] = useState(closeAt ? start.date : addDays(start.date, 7))
  const [time, setTime] = useState(start.time)
  const [error, setError] = useState<AppError | null>(null)
  const iso = bangkokToUtcIso(date, time)

  const run = useMutation({
    mutationFn: (action: { kind: 'close' | 'reopen'; closeAt: string | null }) => {
      const input = {
        postId,
        closeAt: action.closeAt,
        requestKey: requestKey.keyFor(JSON.stringify(action)),
        adminMode,
      }
      return action.kind === 'close' ? closeAssignment(input) : reopenAssignment(input)
    },
    onSuccess: async (_result, action) => {
      requestKey.reset()
      const message =
        action.kind === 'reopen'
          ? intake === 'open'
            ? copy.cancelToast
            : copy.reopenToast
          : action.closeAt
            ? copy.scheduledToast(when(action.closeAt))
            : intake === 'after_solution'
              ? copy.afterClosedToast
              : copy.closedToast
      toast(message, { tone: 'success' })
      await refreshAssignment(queryClient, postId)
      onClose()
    },
    onError: (err) => {
      const e = appErrorOf(err)
      setError(e)
      setConfirming(false)
      if (e.action === 'reload' || e.code === 'stale_revision')
        void refreshAssignment(queryClient, postId)
    },
  })

  const fieldCodes = ['close_at_invalid', 'close_before_due']
  const laterError =
    iso == null
      ? th.errors.close_at_invalid
      : Date.parse(iso) < Date.parse(dueAt)
        ? th.errors.close_before_due
        : error && fieldCodes.includes(error.code)
          ? error.message
          : undefined

  const cancel = (
    <Button variant="ghost" onClick={onClose}>
      {th.workActions.cancel}
    </Button>
  )
  const errorLine = error && !fieldCodes.includes(error.code) && (
    <p className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {error.message}
        {error.ref && ` (${th.errors.reference(error.ref)})`}
      </span>
    </p>
  )

  // ---- ปิดแล้ว ----
  if (intake === 'closed') {
    return (
      <Modal
        open={open}
        onClose={onClose}
        icon={<Lock />}
        title={copy.closedTitle}
        footer={
          solutionPublished ? (
            <Button variant="ghost" onClick={onClose}>
              {th.workActions.closeDialog}
            </Button>
          ) : (
            <>
              {cancel}
              <Button
                icon={<LockOpen />}
                disabled={run.isPending}
                onClick={() => run.mutate({ kind: 'reopen', closeAt: null })}
              >
                {th.workActions.reopen}
              </Button>
            </>
          )
        }
      >
        <div className={styles.body}>
          <p className={styles.note}>
            <Info aria-hidden="true" />
            <span>{solutionPublished ? th.errors.solution_published : copy.closedHint}</span>
          </p>
          {errorLine}
        </div>
      </Modal>
    )
  }

  // ---- ช่วงรับหลังเฉลย ----
  if (intake === 'after_solution') {
    return (
      <Modal
        open={open}
        onClose={onClose}
        icon={<Lock />}
        title={copy.afterTitle}
        footer={
          <>
            {cancel}
            <Button
              variant={confirming ? 'danger' : 'primary'}
              icon={<Lock />}
              disabled={run.isPending}
              onClick={() =>
                confirming ? run.mutate({ kind: 'close', closeAt: null }) : setConfirming(true)
              }
            >
              {confirming ? copy.confirmAfter : th.workActions.closeAfter}
            </Button>
          </>
        }
      >
        <div className={styles.body}>
          <p className={styles.note}>
            <Info aria-hidden="true" />
            <span>{copy.afterHint}</span>
          </p>
          {confirming && <p className={styles.confirm}>{copy.confirmNote}</p>}
          {errorLine}
        </div>
      </Modal>
    )
  }

  // ---- เปิดรับอยู่ ----
  return (
    <Modal
      open={open}
      onClose={onClose}
      icon={<Lock />}
      title={copy.title}
      footer={
        <>
          {cancel}
          {mode === 'now' ? (
            <Button
              variant={confirming ? 'danger' : 'primary'}
              icon={<Lock />}
              disabled={run.isPending}
              onClick={() =>
                confirming ? run.mutate({ kind: 'close', closeAt: null }) : setConfirming(true)
              }
            >
              {confirming ? copy.confirmNow : copy.doNow}
            </Button>
          ) : (
            <Button
              icon={<Lock />}
              disabled={run.isPending || !!laterError || !iso}
              onClick={() => iso && run.mutate({ kind: 'close', closeAt: iso })}
            >
              {copy.doLater}
            </Button>
          )}
        </>
      }
    >
      <div className={styles.body}>
        {closeAt && (
          <div className={styles.kv}>
            <span>{copy.scheduled(when(closeAt))}</span>
            <Button
              size="sm"
              variant="ghost"
              disabled={run.isPending}
              onClick={() => run.mutate({ kind: 'reopen', closeAt: null })}
            >
              {copy.cancelSchedule}
            </Button>
          </div>
        )}
        <fieldset className={styles.choices}>
          <legend className="sr-only">{copy.title}</legend>
          {(['now', 'later'] as const).map((m) => (
            <label key={m} className={styles.radioCard}>
              <input
                type="radio"
                name="closeMode"
                checked={mode === m}
                onChange={() => {
                  setMode(m)
                  setConfirming(false)
                  setError(null)
                }}
              />
              <span>
                <b>{m === 'now' ? copy.now : copy.later}</b>
                <span>{m === 'now' ? copy.nowHint : copy.laterHint}</span>
              </span>
            </label>
          ))}
        </fieldset>
        {mode === 'later' && (
          <Field label={copy.closeAt} error={laterError}>
            <div className={styles.dt}>
              <DatePicker label={copy.closeAt} value={date} onChange={setDate} />
              <TimePicker label={copy.closeAt} value={time} onChange={setTime} />
            </div>
          </Field>
        )}
        <div className={styles.effects}>
          <b>{copy.effects}</b>
          <ul>
            <li>{notSubmitted ? copy.notSubmitted(notSubmitted) : copy.allSubmitted}</li>
            <li>{copy.waiting(waiting)}</li>
            <li>{copy.afterClose(acceptAfterSolution)}</li>
          </ul>
        </div>
        {confirming && <p className={styles.confirm}>{copy.confirmNote}</p>}
        {errorLine}
      </div>
    </Modal>
  )
}
