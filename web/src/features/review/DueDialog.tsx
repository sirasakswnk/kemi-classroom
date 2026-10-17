import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarPlus, Info, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { bangkokParts, bangkokToUtcIso, thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, DatePicker, Field, Modal, TimePicker, useToast } from '../../ui'
import { changeDue, duePreviewQuery, refreshAssignment, type AffectedPerson } from './assignmentApi'
import styles from './dialogs.module.css'
import { useRequestKey } from './useRequestKey'

// M1 เปลี่ยนกำหนดส่งสองทิศ (N3, UX 9): กำหนดเดิม → วันเวลาใหม่ (ตัวเลือกของระบบ ไม่ใช้ input date/time) → ผลก่อนยืนยัน
// รายชื่อสาย→ทัน และ ทัน→สาย มาจาก preview_due_change; บันทึกส่งรายชื่อที่ครูเห็นไป ถ้าเปลี่ยนระหว่างนั้นได้ preview_changed
// → แสดงข้อความ โหลดรายชื่อใหม่ในหน้าต่างเดิม ให้ครูตรวจแล้วกดยืนยันอีกครั้ง (UX 7.1)

const SHOW = 12
const when = (iso: string) => `${thaiDate(iso)} ${thaiTime(iso)} น.`

function Names({ people }: { people: AffectedPerson[] }) {
  const copy = th.workActions.due
  const shown = people.slice(0, SHOW)
  return (
    <span className={styles.names}>
      {shown
        .map((p) =>
          p.roll_number != null ? `${p.roll_number}. ${p.display_name}` : p.display_name,
        )
        .join(', ')}
      {people.length > SHOW && ` ${copy.more(people.length - SHOW)}`}
    </span>
  )
}

export function DueDialog({
  open,
  onClose,
  postId,
  dueAt,
  adminMode,
}: {
  open: boolean
  onClose: () => void
  postId: string
  dueAt: string
  adminMode: boolean
}) {
  const copy = th.workActions.due
  const queryClient = useQueryClient()
  const toast = useToast()
  const requestKey = useRequestKey()
  const [date, setDate] = useState(() => bangkokParts(dueAt).date)
  const [time, setTime] = useState(() => bangkokParts(dueAt).time)
  const [error, setError] = useState<AppError | null>(null)
  const [now] = useState(() => Date.now())
  const iso = bangkokToUtcIso(date, time)
  const same = iso != null && Date.parse(iso) === Date.parse(dueAt)
  const preview = useQuery({
    ...duePreviewQuery(postId, iso ?? ''),
    enabled: open && !!iso && !same,
  })

  const save = useMutation({
    mutationFn: () => {
      if (!iso || !preview.data) throw new Error('no preview')
      const fingerprint = JSON.stringify([iso, preview.data.to_on_time, preview.data.to_late])
      return changeDue({
        postId,
        dueAt: iso,
        preview: preview.data,
        requestKey: requestKey.keyFor(fingerprint),
        adminMode,
      })
    },
    onSuccess: async (result) => {
      toast(copy.saved(when(result.due_at)), { tone: 'success' })
      await refreshAssignment(queryClient, postId)
      onClose()
    },
    onError: (err) => {
      const e = appErrorOf(err)
      setError(e)
      // รายชื่อเปลี่ยน: โหลดผลใหม่ในหน้าต่างเดิม
      if (e.code === 'preview_changed') {
        void preview.refetch()
        void refreshAssignment(queryClient, postId)
      }
    },
  })

  const previewError = preview.isError ? appErrorOf(preview.error) : null
  const fieldError =
    iso == null
      ? th.errors.due_at_invalid
      : previewError && ['due_at_invalid', 'close_before_due'].includes(previewError.code)
        ? previewError.message
        : undefined
  const past = iso != null && !same && Date.parse(iso) < now
  const ready = !!preview.data && !preview.isFetching && !fieldError && !same

  return (
    <Modal
      open={open}
      onClose={onClose}
      icon={<CalendarPlus />}
      title={copy.title}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            {th.workActions.cancel}
          </Button>
          <Button
            icon={<CalendarPlus />}
            disabled={!ready || save.isPending}
            onClick={() => {
              setError(null)
              save.mutate()
            }}
          >
            {copy.save}
          </Button>
        </>
      }
    >
      <div className={styles.body}>
        <div className={styles.kv}>
          <span>{copy.oldDue}</span>
          <b>{when(preview.data?.due_at ?? dueAt)}</b>
        </div>
        <Field label={copy.newDue} error={fieldError} hint={same ? copy.sameDue : undefined}>
          <div className={styles.dt}>
            <DatePicker label={copy.newDue} value={date} onChange={setDate} />
            <TimePicker label={copy.newDue} value={time} onChange={setTime} />
          </div>
        </Field>
        {past && (
          <p className={styles.note} data-tone="amber">
            <TriangleAlert aria-hidden="true" />
            <span>{copy.pastWarn}</span>
          </p>
        )}
        <p className={styles.note}>
          <Info aria-hidden="true" />
          <span>{copy.allNote}</span>
        </p>

        {error?.code === 'preview_changed' && (
          <p className={styles.note} data-tone="amber" role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{error.message}</span>
          </p>
        )}

        {!fieldError && !same && (
          <div className={styles.effects} aria-live="polite">
            <b>{copy.effects}</b>
            {preview.isPending || preview.isFetching ? (
              <p className={styles.muted}>{copy.checking}</p>
            ) : previewError ? (
              <p className={styles.error} role="alert">
                <TriangleAlert aria-hidden="true" />
                <span>{previewError.message}</span>
              </p>
            ) : (
              preview.data && (
                <ul>
                  <li>
                    {preview.data.to_on_time.length ? (
                      <>
                        {copy.toOnTime(preview.data.to_on_time.length)}{' '}
                        <Names people={preview.data.to_on_time} />
                      </>
                    ) : (
                      copy.noneOnTime
                    )}
                  </li>
                  {preview.data.to_late.length > 0 && (
                    <li className={styles.warnLi}>
                      {copy.toLate(preview.data.to_late.length)}{' '}
                      <Names people={preview.data.to_late} />
                    </li>
                  )}
                  <li>{copy.graded(preview.data.graded_count)}</li>
                </ul>
              )
            )}
          </div>
        )}

        {error && error.code !== 'preview_changed' && (
          <p className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {error.message}
              {error.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
          </p>
        )}
      </div>
    </Modal>
  )
}
