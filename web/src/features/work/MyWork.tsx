import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Check,
  Info,
  Lock,
  Pencil,
  RotateCcw,
  Send,
  ShieldCheck,
  TriangleAlert,
} from 'lucide-react'
import { useId, useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { Button, Chip, useToast } from '../../ui'
import type { Post } from '../posts/api'
import { AttachmentList } from '../uploads/AttachmentList'
import { FileField } from '../uploads/FileField'
import type { FileFieldState } from '../uploads/useFileField'
import { storageStatusQuery } from '../storage/api'
import { UploadBlocked } from '../storage/Storage'
import { submitAssignment, type SubmissionStatus } from './api'
import { blockedReason, mineBadge, sameFiles, when } from './workState'
import styles from './work.module.css'

const EMPTY: FileFieldState = { assetIds: [], busy: false, hasErrors: false }

// S03 “งานของฉัน” (UX 6; แบบ v2 sWork): สถานะ + งานที่ส่งแล้ว (เวลาที่บันทึกจริง ทัน/สาย ไฟล์) + ฟอร์มส่ง/ส่งแก้
// ส่งได้หรือไม่และผลถ้าส่งตอนนี้มาจากเซิร์ฟเวอร์ (submission_status.outcome/blocked) — ส่งไม่ได้แสดงเหตุผลแทนฟอร์ม
// ส่งแก้: ช่องไฟล์เริ่มจากไฟล์ชุดปัจจุบัน เก็บบางไฟล์ เอาออก เพิ่ม เรียงใหม่ได้ (ไฟล์เดิมไม่อัปโหลดซ้ำ)
// request key เดิมจนกว่าชุดไฟล์เปลี่ยน — กดส่งซ้ำหลังเน็ตหลุดได้ผลเดิม ไม่ส่งซ้ำ
export function MyWork({ post, status }: { post: Post; status: SubmissionStatus }) {
  const copy = th.work
  const queryClient = useQueryClient()
  const toast = useToast()
  const headingRef = useRef<HTMLHeadingElement>(null)
  const hintId = useId()
  const [editing, setEditing] = useState(false)
  const [files, setFiles] = useState<FileFieldState>(EMPTY)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const keyRef = useRef<{ sig: string; key: string } | null>(null)

  const sub = status.submission
  const current = sub?.files.map((f) => f.asset_id) ?? []
  const canSubmit = status.outcome !== null
  const showForm = canSubmit && (!sub || editing)
  // J10.3: พื้นที่เต็ม → แทนกล่องเลือกไฟล์ด้วยกล่องแจ้ง (ส่งงานต่อไม่ได้จนมีพื้นที่)
  const storage = useQuery({ ...storageStatusQuery, enabled: showForm })
  const storageFull = showForm && storage.data?.level === 'full'
  const badge = mineBadge(status, {
    editing: showForm && !!sub,
    attached: files.assetIds.length > 0,
  })

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ['submission-status', post.id] }),
      queryClient.invalidateQueries({ queryKey: ['my-work'] }),
    ])

  const blockReason = files.busy
    ? copy.waitUpload
    : files.hasErrors
      ? copy.fixErrors
      : files.assetIds.length === 0
        ? th.errors.submission_files_required
        : sub && sameFiles(files.assetIds, current)
          ? copy.noChange
          : null

  const submit = async () => {
    if (blockReason || sending) return
    const sig = JSON.stringify([files.assetIds, sub?.content_revision ?? 0])
    if (keyRef.current?.sig !== sig) keyRef.current = { sig, key: crypto.randomUUID() }
    setSending(true)
    setError(null)
    try {
      await submitAssignment({
        assignmentId: post.id,
        files: files.assetIds,
        expectedRevision: sub?.content_revision ?? 0,
        requestKey: keyRef.current.key,
      })
      keyRef.current = null
      toast(sub ? copy.sentEdit : copy.sent, { tone: 'success' })
      setEditing(false)
      setFiles(EMPTY)
      await refresh()
      headingRef.current?.focus()
    } catch (e) {
      const err = appErrorOf(e)
      setError(err)
      // สถานะอาจเปลี่ยนแล้ว (ปิดรับ/ส่งจากหน้าจออื่น/เน็ตหลุดหลังบันทึก) — โหลดสถานะจริงก่อนให้ส่งอีกครั้ง
      if (err.code !== 'submission_file_unavailable' && err.code !== 'submission_files_required')
        void refresh()
    } finally {
      setSending(false)
    }
  }

  const stale = error?.code === 'stale_revision'
  const errorBox = error && (
    <p className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {stale ? copy.staleRevision : error.message}
        {error.ref && ` (${th.errors.reference(error.ref)})`}
      </span>
      {stale ? (
        <Button
          size="sm"
          variant="ghost"
          icon={<RotateCcw />}
          onClick={() => {
            setError(null)
            setEditing(false)
            void refresh()
          }}
        >
          {copy.reloadStatus}
        </Button>
      ) : (
        (error.action === 'fallback' || error.action === 'retry_later') &&
        showForm && (
          <Button size="sm" variant="ghost" icon={<RotateCcw />} onClick={() => void submit()}>
            {copy.retrySend}
          </Button>
        )
      )}
    </p>
  )

  const permissionNote = status.outcome === 'resubmit_permission' && (
    <p className={styles.note} data-tone="purple">
      <Pencil aria-hidden="true" />
      <span>
        <b>{copy.permissionTitle}</b>
        <br />
        {copy.permissionBody}
      </span>
    </p>
  )

  return (
    <section className={styles.section} aria-labelledby="workMine">
      <div className={styles.sectionHead}>
        <h2 id="workMine" ref={headingRef} tabIndex={-1}>
          {copy.mine}
        </h2>
        <Chip tone={badge.tone}>{badge.label}</Chip>
      </div>

      {!showForm && error && errorBox}

      {sub && !showForm && (
        <div className={styles.card}>
          <div className={styles.doneTop}>
            <span
              className={styles.ok}
              data-tone={sub.timing === 'late' ? 'red' : undefined}
              aria-hidden="true"
            >
              <Check />
            </span>
            <span>
              <b>{sub.content_revision > 1 ? copy.revisedTitle : copy.doneTitle[sub.timing]}</b>
              <ul className={styles.times}>
                <li>{copy.firstAt(when(sub.first_submitted_at))}</li>
                {sub.content_revision > 1 && <li>{copy.lastAt(when(sub.last_submitted_at))}</li>}
                <li>{copy.revision(sub.content_revision)}</li>
              </ul>
            </span>
          </div>
          {sub.first_after_solution && (
            <p className={styles.note} data-tone="plain">
              <Info aria-hidden="true" />
              <span>{copy.afterSolutionNote}</span>
            </p>
          )}
          <span className={styles.muted}>{copy.sentFiles}</span>
          <AttachmentList files={sub.files} />
          {canSubmit ? (
            <>
              {permissionNote}
              <Button
                variant="ghost"
                block
                icon={<Pencil />}
                onClick={() => {
                  setError(null)
                  setEditing(true)
                }}
              >
                {status.outcome === 'resubmit' ? copy.editUntilDue : copy.edit}
              </Button>
            </>
          ) : (
            status.blocked && (
              <p className={styles.note} data-tone="plain">
                <Info aria-hidden="true" />
                <span>{blockedReason(status.blocked)}</span>
              </p>
            )
          )}
        </div>
      )}

      {!sub && !canSubmit && status.blocked && (
        <p className={styles.locked}>
          <Lock aria-hidden="true" />
          <span>{blockedReason(status.blocked)}</span>
        </p>
      )}

      {showForm && (
        <div className={styles.form}>
          {sub && (
            <p className={styles.note} data-tone="purple">
              <ShieldCheck aria-hidden="true" />
              <span>{copy.keepOld}</span>
            </p>
          )}
          {permissionNote}
          {status.outcome === 'first_late' && (
            <p className={styles.note}>
              <Info aria-hidden="true" />
              <span>{copy.lateNotice}</span>
            </p>
          )}
          {status.outcome === 'first_after_solution' && (
            <p className={styles.note}>
              <Info aria-hidden="true" />
              <span>{copy.afterSolutionNotice}</span>
            </p>
          )}
          {storageFull ? (
            <UploadBlocked />
          ) : (
            <FileField
              key={`${sub?.content_revision ?? 0}:${editing}`}
              kind="submission"
              target={{
                purpose: 'submission',
                classroomId: post.classroom_id,
                postId: post.id,
                adminMode: false,
              }}
              initial={editing ? sub?.files : undefined}
              onChange={setFiles}
            />
          )}
          {!sub && files.assetIds.length > 0 && !files.busy && (
            <p className={styles.note}>
              <Info aria-hidden="true" />
              <span>{copy.attachedNotSent}</span>
            </p>
          )}
          {errorBox}
          {!storageFull && (
            <div className={styles.submitBar}>
              <Button
                variant="primary"
                icon={<Send />}
                disabled={!!blockReason || sending}
                aria-describedby={blockReason ? hintId : undefined}
                onClick={() => void submit()}
              >
                {sending
                  ? copy.submitting
                  : sub
                    ? copy.submitEdit(files.assetIds.length)
                    : copy.submit(files.assetIds.length)}
              </Button>
              {blockReason && (
                <span id={hintId} className={styles.submitHint}>
                  {blockReason}
                </span>
              )}
              {editing && (
                <Button
                  variant="ghost"
                  disabled={sending}
                  onClick={() => {
                    setEditing(false)
                    setError(null)
                    setFiles(EMPTY)
                  }}
                >
                  {copy.cancelEdit}
                </Button>
              )}
            </div>
          )}
        </div>
      )}
    </section>
  )
}
