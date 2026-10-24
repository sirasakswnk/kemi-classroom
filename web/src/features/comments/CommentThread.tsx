import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Lock, MoreHorizontal, SendHorizontal, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { MenuButton } from '../../ui'
import { postComment, retractComment, threadKey, threadQuery, type Comment } from './api'
import { remaining } from './commentText'
import styles from './comments.module.css'

// ความคิดเห็นส่วนตัวของงานหนึ่งกับนักเรียนหนึ่งคน (UX 8, แบบ v2 thread/bubble/composer) — ใช้ทั้งครู (T03) และนักเรียน (S03)
// ยกเลิกได้เฉพาะข้อความตนเอง (เมนู) แล้วแสดง “ข้อความนี้ถูกยกเลิก”; กล่องเขียนและเมนูยกเลิกซ่อนเมื่อเขียนไม่ได้
// (นักเรียน: จบภาคเรียนหรือไม่ได้อยู่ในห้องแล้ว — can_write จากเซิร์ฟเวอร์)

type Props =
  | { mode: 'student'; assignmentId: string }
  | {
      mode: 'teacher'
      assignmentId: string
      studentId: string
      studentName: string
      adminMode: boolean
    }

const firstName = (name: string) => name.trim().split(/\s+/)[0] ?? name

export function CommentThread(props: Props) {
  const copy = th.comments
  const queryClient = useQueryClient()
  const studentId = props.mode === 'teacher' ? props.studentId : null
  const adminMode = props.mode === 'teacher' && props.adminMode
  const key = threadKey(props.assignmentId, studentId)
  const thread = useQuery(threadQuery(props.assignmentId, studentId))
  const [draft, setDraft] = useState('')
  const [error, setError] = useState<AppError | null>(null)
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const canWrite = thread.data?.can_write ?? false
  const text = draft.trim()
  const left = remaining(draft)

  const send = useMutation({
    mutationFn: () => {
      const fingerprint = text
      if (requestKey.current?.fingerprint !== fingerprint)
        requestKey.current = { fingerprint, key: crypto.randomUUID() }
      return postComment({
        assignmentId: props.assignmentId,
        studentId,
        body: text,
        requestKey: requestKey.current.key,
        adminMode,
      })
    },
    onSuccess: async () => {
      setDraft('')
      setError(null)
      requestKey.current = null
      await queryClient.invalidateQueries({ queryKey: key })
    },
    onError: (err) => {
      setError(appErrorOf(err))
      // จบภาคเรียน/ถูกเอาออกระหว่างเปิดหน้า: โหลดใหม่ให้กล่องเขียนหายตามสถานะจริง
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })

  const retract = useMutation({
    mutationFn: (commentId: string) => retractComment(commentId, adminMode),
    onSuccess: async () => {
      setError(null)
      await queryClient.invalidateQueries({ queryKey: key })
    },
    onError: (err) => {
      setError(appErrorOf(err))
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })

  const who = (c: Comment) => {
    if (c.mine) return copy.you
    if (c.author_role === 'admin') return copy.admin
    if (c.author_role === 'student') return firstName(c.author_name ?? '')
    return c.author_name ?? copy.teacher
  }

  return (
    <section className={styles.thread} aria-labelledby="commentsTitle">
      <div className={styles.head}>
        <h2 id="commentsTitle">{copy.title}</h2>
        <span className={styles.privateTag}>
          <Lock aria-hidden="true" />
          {props.mode === 'student'
            ? copy.privateStudent
            : copy.privateTeacher(firstName(props.studentName))}
        </span>
      </div>

      {thread.isPending ? (
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      ) : thread.isError ? (
        <ErrorLine error={appErrorOf(thread.error)} />
      ) : thread.data.comments.length === 0 ? (
        <p className={styles.muted}>
          {props.mode === 'teacher'
            ? copy.emptyTeacher
            : canWrite
              ? copy.emptyStudent
              : copy.emptyClosed}
        </p>
      ) : (
        <ol className={styles.list}>
          {thread.data.comments.map((c) => (
            <li
              key={c.comment_id}
              className={styles.bubble}
              data-side={c.mine ? 'me' : 'them'}
              data-gone={c.retracted_at ? true : undefined}
            >
              {c.retracted_at ? (
                <span className={styles.gone}>{copy.retracted}</span>
              ) : (
                <>
                  <span className={styles.body}>{c.body}</span>
                  <span className={styles.meta}>
                    <small>
                      {who(c)} · {thaiDate(c.created_at)} {thaiTime(c.created_at)} น.
                    </small>
                    {c.mine && canWrite && (
                      <MenuButton
                        label={copy.menu}
                        icon={<MoreHorizontal />}
                        className={styles.menu}
                        items={[
                          {
                            label: copy.retract,
                            tone: 'danger',
                            onSelect: () => retract.mutate(c.comment_id),
                          },
                        ]}
                      />
                    )}
                  </span>
                </>
              )}
            </li>
          ))}
        </ol>
      )}

      {thread.isSuccess &&
        (canWrite ? (
          <form
            className={styles.composer}
            onSubmit={(e) => {
              e.preventDefault()
              if (text && left >= 0 && !send.isPending) send.mutate()
            }}
          >
            <textarea
              className={styles.input}
              rows={2}
              value={draft}
              placeholder={
                props.mode === 'student' ? copy.placeholderStudent : copy.placeholderTeacher
              }
              aria-label={props.mode === 'student' ? copy.ariaStudent : copy.ariaTeacher}
              aria-invalid={left < 0 || undefined}
              onChange={(e) => {
                setDraft(e.target.value)
                if (error?.code === 'comment_too_long') setError(null)
              }}
            />
            <button
              type="submit"
              className={styles.send}
              aria-label={copy.send}
              disabled={!text || left < 0 || send.isPending}
            >
              <SendHorizontal aria-hidden="true" />
            </button>
            {left < 200 && (
              <p className={styles.counter} data-over={left < 0 || undefined} aria-live="polite">
                {left < 0 ? th.errors.comment_too_long : copy.left(left)}
              </p>
            )}
          </form>
        ) : (
          <p className={styles.muted}>
            {props.mode === 'student' ? copy.closedStudent : copy.closedTeacher}
          </p>
        ))}

      {error && <ErrorLine error={error} />}
    </section>
  )
}

function ErrorLine({ error }: { error: AppError }) {
  return (
    <p className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {error.message}
        {error.ref && ` (${th.errors.reference(error.ref)})`}
      </span>
    </p>
  )
}
