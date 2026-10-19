import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Download, Trash2, TriangleAlert } from 'lucide-react'
import { useId, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { Button, Modal, useToast } from '../../ui'
import { classroomQuery } from '../classrooms/api'
import { gradeTableQuery } from '../gradebook/api'
import { csvFileName, downloadCsv, gradeCsv } from '../gradebook/gradeCsv'
import { useRequestKey } from '../review/useRequestKey'
import { deletePost, postDeletePreviewQuery, refreshAfterDelete } from './deleteApi'
import dialogs from '../review/dialogs.module.css'
import styles from './posts.module.css'

// หน้าต่างลบการบ้าน/ประกาศ (N4, UX 9 [ยืนยัน N4]) — ลบถาวรและหายจากหน้าห้องของนักเรียนทันที
//   การบ้าน: สรุปยอดที่จะถูกลบ (งานส่ง ผลตรวจ ความคิดเห็น ไฟล์) · โทเคนที่ได้ไปแล้วไม่ถูกเรียกคืน · ลิงก์ดาวน์โหลด CSV คะแนนก่อนลบ
//   (เมื่อมีผลตรวจ) · ช่องติ๊ก “เข้าใจแล้วว่าลบถาวร” ก่อนปุ่ม “ลบงาน” จะกดได้
//   ประกาศ: หน้าต่างยืนยันสั้น (ไม่มีช่องติ๊ก)
// ยอดมาจาก post_delete_preview แล้วส่งกลับไปกับ delete_post — เซิร์ฟเวอร์ตรวจซ้ำหลังล็อก ไม่ตรงได้ preview_changed:
// แสดงข้อความ โหลดยอดใหม่ในหน้าต่างเดิม และให้ติ๊กยืนยันใหม่ (UX 7.1)
export function DeletePostDialog({
  open,
  onClose,
  postId,
  adminMode,
  onDeleted,
}: {
  open: boolean
  onClose: () => void
  postId: string
  adminMode: boolean
  /** หลังลบสำเร็จ (เช่น กลับหน้าห้อง) — หน้าต่างปิดเองก่อนเรียก */
  onDeleted?: () => void
}) {
  const copy = th.deletePost
  const queryClient = useQueryClient()
  const toast = useToast()
  const requestKey = useRequestKey()
  const checkId = useId()
  const preview = useQuery({ ...postDeletePreviewQuery(postId), enabled: open })
  const [understood, setUnderstood] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const [csvBusy, setCsvBusy] = useState(false)
  const [csvError, setCsvError] = useState<AppError | null>(null)
  const p = preview.data
  const homework = p?.kind === 'homework'

  const remove = useMutation({
    mutationFn: () => {
      if (!p) throw new Error('no preview')
      const expected = {
        submissions: p.submissions,
        grades: p.grades,
        comments: p.comments,
        files: p.files,
      }
      return deletePost({
        postId,
        expected,
        requestKey: requestKey.keyFor(JSON.stringify(expected)),
        adminMode,
      })
    },
    onSuccess: async (result) => {
      toast(copy.deleted(result.title), { tone: 'success' })
      onClose()
      await refreshAfterDelete(queryClient, postId)
      onDeleted?.()
    },
    onError: (err) => {
      const e = appErrorOf(err)
      setError(e)
      if (e.code === 'preview_changed') {
        // ยอดเปลี่ยนระหว่างเปิดหน้าต่าง: โหลดยอดใหม่ในหน้าต่างเดิม ครูตรวจแล้วติ๊กยืนยันอีกครั้ง
        setUnderstood(false)
        void preview.refetch()
      } else if (e.code === 'forbidden') {
        // โพสต์ถูกลบไปแล้ว (จากอีกแท็บ) — เอาออกจากแคชแล้วปิด
        void refreshAfterDelete(queryClient, postId)
      }
    },
  })

  // CSV คะแนนของงานนี้ก่อนลบ: ใช้ตารางคะแนนของห้อง (T04) กรองเหลือคอลัมน์ของงานนี้
  const downloadScores = async () => {
    if (!p || csvBusy) return
    setCsvBusy(true)
    setCsvError(null)
    try {
      const [table, room] = await Promise.all([
        queryClient.fetchQuery({ ...gradeTableQuery(p.classroom_id), staleTime: 0 }),
        queryClient.fetchQuery(classroomQuery(p.classroom_id)),
      ])
      downloadCsv(
        csvFileName(room?.name ?? '', table.term_name, p.title),
        gradeCsv(table, p.post_id),
      )
    } catch (err) {
      setCsvError(appErrorOf(err))
    } finally {
      setCsvBusy(false)
    }
  }

  const ready = !!p && !preview.isFetching && !remove.isPending && (!homework || understood)
  const previewError = preview.isError ? appErrorOf(preview.error) : null

  return (
    <Modal
      open={open}
      onClose={onClose}
      icon={<Trash2 />}
      title={p?.kind === 'announcement' ? copy.titleAnnouncement : copy.title}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            {th.workActions.cancel}
          </Button>
          <Button
            variant="danger"
            icon={<Trash2 />}
            disabled={!ready}
            onClick={() => {
              setError(null)
              remove.mutate()
            }}
          >
            {remove.isPending
              ? copy.deleting
              : p?.kind === 'announcement'
                ? copy.confirmAnnouncement
                : copy.confirm}
          </Button>
        </>
      }
    >
      <div className={dialogs.body}>
        {preview.isPending && (
          <p role="status" className={dialogs.muted}>
            {copy.checking}
          </p>
        )}
        {previewError && (
          <p className={dialogs.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {previewError.code === 'forbidden' ? copy.gone : previewError.message}
              {previewError.ref && ` (${th.errors.reference(previewError.ref)})`}
            </span>
          </p>
        )}
        {p && (
          <>
            <p className={styles.deleteLead}>
              {p.kind === 'announcement' ? copy.leadAnnouncement(p.title) : copy.lead(p.title)}
            </p>
            {homework ? (
              <div className={dialogs.effects} aria-live="polite">
                <b>{copy.willDelete}</b>
                <ul>
                  <li>{copy.submissions(p.submissions)}</li>
                  <li>{copy.grades(p.grades)}</li>
                  <li>{copy.comments(p.comments)}</li>
                  <li>{copy.files(p.files)}</li>
                </ul>
              </div>
            ) : (
              p.files > 0 && <p className={dialogs.muted}>{copy.announcementFiles(p.files)}</p>
            )}
            {homework && <p className={dialogs.note}>{copy.tokensKept}</p>}
            {homework && p.grades > 0 && (
              <div className={styles.deleteCsv}>
                <Button
                  variant="soft"
                  size="sm"
                  icon={<Download />}
                  disabled={csvBusy}
                  onClick={() => void downloadScores()}
                >
                  {csvBusy ? copy.csvBusy : copy.csv}
                </Button>
                {csvError && (
                  <span className={styles.deleteCsvError} role="alert">
                    {csvError.message}
                  </span>
                )}
              </div>
            )}
            {homework && (
              <label className={styles.deleteCheck} htmlFor={checkId}>
                <input
                  id={checkId}
                  type="checkbox"
                  checked={understood}
                  onChange={(e) => setUnderstood(e.target.checked)}
                />
                <span>{copy.understood}</span>
              </label>
            )}
            <p className={dialogs.muted}>{copy.irreversible}</p>
          </>
        )}
        {error?.code === 'preview_changed' && (
          <p className={dialogs.note} data-tone="amber" role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{error.message}</span>
          </p>
        )}
        {error && error.code !== 'preview_changed' && (
          <p className={dialogs.error} role="alert">
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
