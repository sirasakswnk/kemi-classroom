import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  FileText,
  Image as ImageIcon,
  Info,
  RotateCcw,
  TriangleAlert,
} from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useParams } from 'react-router'
import { th } from '../../copy/th'
import { loadSignedFile, signedFileKey, signedFileOptions } from '../../lib/files'
import { appErrorOf } from '../../lib/request'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip } from '../../ui'
import { classroomQuery } from '../classrooms/api'
import { postQuery } from '../posts/api'
import { TeacherPage } from '../teacher/TeacherLayout'
import { AttachmentList, type AttachmentRef } from '../uploads/AttachmentList'
import { submissionFilesQuery, submissionListQuery } from './api'
import { isImage, rowBadges } from './reviewState'
import styles from './review.module.css'

// ตัวดูไฟล์เบื้องต้นของ T03 (P3-09): ไฟล์งานส่งของนักเรียนหนึ่งคนทีละไฟล์
// รูป: ขอลิงก์ + โหลด Blob เฉพาะไฟล์ที่เปิดอยู่ (ไม่โหลดล่วงหน้า) แสดงจาก object URL แล้วคืนเมื่อเปลี่ยนไฟล์/ปิด
// PDF: เปิดแท็บใหม่แบบ inline (แถวไฟล์เดียวกับไฟล์แนบ) — ตัวดู PDF ในหน้า ซูม/หมุน และรวม PDF มากับ P4-04
// กลับไปรายชื่อได้ตัวกรองและหน้าเดิม (state.back จาก T03)
export default function SubmissionViewer() {
  const { postId = '', submissionId = '' } = useParams()
  const location = useLocation()
  const backSearch = (location.state as { back?: string } | null)?.back ?? ''
  const post = useQuery(postQuery(postId))
  const list = useQuery(submissionListQuery(postId))
  const files = useQuery(submissionFilesQuery(submissionId))
  const classroomId = post.data?.classroom_id ?? list.data?.classroom_id ?? ''
  const classroom = useQuery({ ...classroomQuery(classroomId), enabled: !!classroomId })
  const [index, setIndex] = useState(0)
  const copy = th.review.viewer

  const statusTo = `/t/w/${postId}${backSearch}`
  const row = list.data?.rows.find((r) => r.submission_id === submissionId)
  const crumbs = [
    { label: th.teacher.overview, to: '/t' },
    ...(classroom.data ? [{ label: classroom.data.name, to: `/t/c/${classroomId}?tab=work` }] : []),
    ...(post.data ? [{ label: post.data.title, to: statusTo }] : []),
    { label: copy.crumb },
  ]
  const back = (
    <Link to={statusTo} className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {copy.back}
    </Link>
  )

  if (list.isPending || files.isPending) {
    return (
      <TeacherPage crumbs={crumbs}>
        {back}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  const error = list.isError
    ? appErrorOf(list.error)
    : files.isError
      ? appErrorOf(files.error)
      : null
  if (error || !row) {
    return (
      <TeacherPage crumbs={crumbs}>
        <div className={styles.page}>
          {back}
          <div className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {error && error.code !== 'forbidden' ? error.message : copy.notFound}
              {error?.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
          </div>
        </div>
      </TeacherPage>
    )
  }

  const all = files.data ?? []
  const current = all[Math.min(index, Math.max(0, all.length - 1))]
  const at = Math.min(index, Math.max(0, all.length - 1))

  return (
    <TeacherPage crumbs={crumbs}>
      <div className={styles.page}>
        {back}
        <header className={styles.head}>
          <span className={styles.eyebrow}>{post.data?.title}</span>
          <h1>
            {row.roll_number != null ? `${row.roll_number} · ` : ''}
            {row.display_name}
          </h1>
          <span className={styles.chips}>
            {rowBadges(row).map((b) => (
              <Chip key={b.label} tone={b.tone}>
                {b.label}
              </Chip>
            ))}
          </span>
          {row.last_submitted_at && (
            <p className={styles.muted}>
              {copy.submittedAt(
                `${thaiDate(row.last_submitted_at)} ${thaiTime(row.last_submitted_at)} น.`,
              )}{' '}
              · {copy.revision(row.content_revision ?? 1)}
            </p>
          )}
        </header>

        {!current ? (
          <div className={styles.empty}>
            <Info aria-hidden="true" />
            <span>{copy.noFiles}</span>
          </div>
        ) : (
          <div className={styles.viewer}>
            <div className={styles.page}>
              <div className={styles.nav}>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<ChevronLeft />}
                  disabled={at <= 0}
                  onClick={() => setIndex(at - 1)}
                >
                  {copy.prevFile}
                </Button>
                <span aria-live="polite">{copy.fileOf(at + 1, all.length)}</span>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<ChevronRight />}
                  disabled={at >= all.length - 1}
                  onClick={() => setIndex(at + 1)}
                >
                  {copy.nextFile}
                </Button>
              </div>
              <div className={styles.stage}>
                {isImage(current.content_type) ? (
                  <ImagePane key={current.asset_id} file={current} owner={row.display_name} />
                ) : (
                  <div className={styles.pdfNote}>
                    <FileText aria-hidden="true" />
                    <span>{copy.pdfNote}</span>
                    <div>
                      <AttachmentList files={[current]} />
                    </div>
                  </div>
                )}
              </div>
            </div>
            <aside className={styles.side}>
              <ul className={styles.files} aria-label={copy.filesAria}>
                {all.map((f, i) => (
                  <li key={f.asset_id}>
                    <button
                      type="button"
                      className={styles.fileBtn}
                      aria-current={i === at}
                      onClick={() => setIndex(i)}
                    >
                      {isImage(f.content_type) ? (
                        <ImageIcon aria-hidden="true" />
                      ) : (
                        <FileText aria-hidden="true" />
                      )}
                      <span>
                        {i + 1}. {f.file_name}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
              {isImage(current.content_type) && <AttachmentList files={[current]} />}
              <p className={styles.note}>
                <Info aria-hidden="true" />
                <span>{copy.gradingSoon}</span>
              </p>
            </aside>
          </div>
        )}
      </div>
    </TeacherPage>
  )
}

function ImagePane({ file, owner }: { file: AttachmentRef; owner: string }) {
  const queryClient = useQueryClient()
  const copy = th.review.viewer
  // Blob ของไฟล์ที่เปิดอยู่เท่านั้น — เก็บใน cache 5 นาทีให้สลับกลับมาไม่โหลดจาก B2 ซ้ำ
  const blob = useQuery({
    queryKey: ['file-blob', file.asset_id],
    queryFn: async () =>
      loadSignedFile(await queryClient.fetchQuery(signedFileOptions(file.asset_id, 'view'))),
    staleTime: Infinity,
    gcTime: 5 * 60_000,
    retry: false,
  })
  // object URL ผูกกับ <img> ตรง ๆ — สร้างเมื่อได้ Blob และคืนเมื่อเปลี่ยนไฟล์/ปิดตัวดู
  const imgRef = useRef<HTMLImageElement>(null)
  useEffect(() => {
    const img = imgRef.current
    if (!blob.data || !img) return
    const url = URL.createObjectURL(blob.data)
    img.src = url
    return () => {
      img.removeAttribute('src')
      URL.revokeObjectURL(url)
    }
  }, [blob.data])

  if (blob.isError) {
    const error = appErrorOf(blob.error)
    return (
      <p className={styles.error} role="alert">
        <TriangleAlert aria-hidden="true" />
        <span>
          {error.message}
          {error.ref && ` (${th.errors.reference(error.ref)})`}
        </span>
        <Button
          size="sm"
          variant="ghost"
          icon={<RotateCcw />}
          onClick={() => {
            // ลิงก์อาจหมดอายุ (b2_403) — ขอลิงก์ใหม่แล้วโหลดอีกครั้ง
            void queryClient.invalidateQueries({ queryKey: signedFileKey(file.asset_id, 'view') })
            void blob.refetch()
          }}
        >
          {copy.retry}
        </Button>
      </p>
    )
  }
  if (!blob.data) {
    return (
      <p role="status" className={styles.muted}>
        {copy.loading}
      </p>
    )
  }
  return <img ref={imgRef} alt={copy.imageAlt(owner, file.file_name)} />
}
