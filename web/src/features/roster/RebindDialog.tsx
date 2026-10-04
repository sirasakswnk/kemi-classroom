import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Link2, ShieldCheck, TriangleAlert, Unlink, UserCog } from 'lucide-react'
import { useRef, useState, type FormEvent } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button, Field, Input, Modal, useToast } from '../../ui'
import {
  rebindPreview,
  rebindStudent,
  unbindStudent,
  type RebindPreview,
  type RosterRow,
} from './rosterApi'
import styles from './RosterList.module.css'

export type RebindMode = 'move' | 'unbind'

// UX 10 แก้การผูกบัญชี: “ผูกกับบัญชีอื่น” (พิมพ์อีเมล → หน้าทวน → ยืนยัน) และ “ถอดการผูก” (กล่องยืนยันพร้อมคำเตือน)
// ทั้งสองแบบเพิกถอน session ของบัญชีเดิมในฝั่งเซิร์ฟเวอร์ (0008_rebind) และไม่แตะงาน คะแนน ชั้นเรียน โทเคน
export function RebindDialog({
  student,
  mode,
  adminMode,
  onClose,
}: {
  student: RosterRow | null
  mode: RebindMode
  adminMode: boolean
  onClose: () => void
}) {
  const copy = th.rosterList
  const [email, setEmail] = useState('')
  const [fieldError, setFieldError] = useState<string | null>(null)
  const [formError, setFormError] = useState<string | null>(null)
  const [review, setReview] = useState<RebindPreview | null>(null)
  const emailRef = useRef<HTMLInputElement>(null)
  const confirmRef = useRef<HTMLButtonElement>(null)
  const queryClient = useQueryClient()
  const toast = useToast()

  const showError = (error: unknown, field: boolean) => {
    const e = appErrorOf(error)
    const text = e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : '')
    if (field && e.action === 'field') {
      setFieldError(text)
      setReview(null)
      emailRef.current?.focus()
    } else {
      setFormError(text)
    }
  }

  const done = async (message: string) => {
    await queryClient.invalidateQueries({ queryKey: ['roster-overview'] })
    // ห้อง/สมาชิกในหน้าครูอาจแสดงชื่อบัญชีเก่า — โหลดใหม่เมื่อเปิดครั้งถัดไป
    void queryClient.invalidateQueries({ queryKey: ['members'] })
    toast(message, { tone: 'success' })
    onClose()
  }

  const check = useMutation({
    mutationFn: () => rebindPreview(student?.student_id ?? '', email, adminMode),
    onSuccess: (result) => {
      setReview(result)
      // ย้ายโฟกัสไปปุ่มยืนยันหลังแสดงหน้าทวน
      requestAnimationFrame(() => confirmRef.current?.focus())
    },
    onError: (error) => showError(error, true),
  })
  const save = useMutation({
    mutationFn: () =>
      rebindStudent(student?.student_id ?? '', review?.new_email ?? email, adminMode),
    onSuccess: (result) => done(copy.move.done(result.display_name)),
    onError: (error) => showError(error, true),
  })
  const unbind = useMutation({
    mutationFn: () => unbindStudent(student?.student_id ?? '', adminMode),
    onSuccess: (result) => done(copy.unbind.done(result.display_name)),
    onError: (error) => showError(error, false),
  })

  const busy = check.isPending || save.isPending || unbind.isPending
  const close = () => {
    if (!busy) onClose()
  }

  const submitEmail = (e: FormEvent) => {
    e.preventDefault()
    setFormError(null)
    if (!email.trim()) {
      setFieldError(th.errors.account_not_found)
      emailRef.current?.focus()
      return
    }
    check.mutate()
  }

  const formAlert = formError && (
    <p className={styles.alert} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>{formError}</span>
    </p>
  )

  if (mode === 'unbind') {
    return (
      <Modal
        open={student !== null}
        onClose={close}
        icon={<Unlink />}
        title={student ? copy.unbind.title(student.display_name) : ''}
        description={copy.unbind.body(student?.account_email ?? copy.move.none)}
        footer={
          <>
            <Button variant="ghost" disabled={busy} onClick={close}>
              {copy.cancel}
            </Button>
            <Button
              variant="danger"
              icon={<Unlink />}
              disabled={busy}
              onClick={() => {
                setFormError(null)
                unbind.mutate()
              }}
            >
              {unbind.isPending ? copy.unbind.saving : copy.unbind.confirm}
            </Button>
          </>
        }
      >
        <p className={styles.note} data-tone="amber">
          <TriangleAlert aria-hidden="true" />
          <span>{copy.unbind.warning}</span>
        </p>
        {formAlert}
      </Modal>
    )
  }

  return (
    <Modal
      open={student !== null}
      onClose={close}
      icon={<UserCog />}
      title={review ? copy.move.reviewTitle : student ? copy.move.title(student.display_name) : ''}
      description={review ? undefined : copy.move.intro}
      initialFocusRef={emailRef}
      footer={
        review ? (
          <>
            <Button
              variant="ghost"
              disabled={busy}
              onClick={() => {
                setReview(null)
                requestAnimationFrame(() => emailRef.current?.focus())
              }}
            >
              {copy.move.back}
            </Button>
            <Button
              ref={confirmRef}
              icon={<Link2 />}
              disabled={busy}
              onClick={() => {
                setFormError(null)
                save.mutate()
              }}
            >
              {save.isPending ? copy.move.saving : copy.move.confirm}
            </Button>
          </>
        ) : (
          <>
            <Button variant="ghost" disabled={busy} onClick={close}>
              {copy.cancel}
            </Button>
            <Button type="submit" form="rebindEmailForm" disabled={busy}>
              {check.isPending ? copy.move.checking : copy.move.check}
            </Button>
          </>
        )
      }
    >
      {review ? (
        <>
          <dl className={styles.review}>
            <dt>{copy.move.student}</dt>
            <dd>{review.display_name}</dd>
            <dt>{copy.move.oldAccount}</dt>
            <dd>{review.old_email ?? copy.move.none}</dd>
            <dt>{copy.move.newAccount}</dt>
            <dd>
              <b>{review.new_email}</b>
            </dd>
          </dl>
          <p className={styles.note} data-tone="purple">
            <ShieldCheck aria-hidden="true" />
            <span>{copy.move.warning}</span>
          </p>
        </>
      ) : (
        <form id="rebindEmailForm" onSubmit={submitEmail} noValidate>
          <Field label={copy.move.emailLabel} error={fieldError}>
            <Input
              ref={emailRef}
              type="email"
              inputMode="email"
              autoComplete="off"
              spellCheck={false}
              value={email}
              onChange={(e) => {
                setEmail(e.target.value)
                if (fieldError) setFieldError(null)
              }}
              placeholder={copy.move.emailPlaceholder}
            />
          </Field>
        </form>
      )}
      {formAlert}
    </Modal>
  )
}
