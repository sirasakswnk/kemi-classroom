import { PenLine, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { LinkifiedText } from '../../ui'
import { useTeacher } from '../teacher/teacherContext'
import { AttachmentList } from '../uploads/AttachmentList'
import type { Post } from './api'
import { DeletePostDialog } from './DeletePostDialog'
import styles from './posts.module.css'

// ประกาศของห้อง ใช้ร่วมกันใน S02 (นักเรียน) และ T08 (ครู) — แบบ v2 .post; ไฟล์แนบเปิดดู/ดาวน์โหลดได้ (P3-06b)
// การบ้าน: S02 ใช้ work/StudentWorkList (P3-08), T08 ใช้ review/TeacherWorkList (P3-09)
// ครู: ปุ่มแก้ไขบนการ์ดประกาศ (ถาวรตาม UX 9) — ปุ่มแก้ไขการบ้านอยู่ที่การ์ดโจทย์ของ T03

type Heading = 'h2' | 'h3'

/** ปุ่ม “ลบ” บนการ์ดประกาศของครู + หน้าต่างยืนยันสั้น (N4) — ต่อจากปุ่มแก้ไข */
function DeleteAnnouncement({ post }: { post: Post }) {
  const copy = th.deletePost
  const { adminMode } = useTeacher()
  const [open, setOpen] = useState(false)
  return (
    <>
      <button
        type="button"
        className={styles.cardDelete}
        aria-label={copy.openAnnouncementAria(post.title)}
        onClick={() => setOpen(true)}
      >
        <Trash2 aria-hidden="true" />
        <span aria-hidden="true">{copy.openAnnouncement}</span>
      </button>
      {open && (
        <DeletePostDialog
          open
          onClose={() => setOpen(false)}
          postId={post.id}
          adminMode={adminMode}
        />
      )}
    </>
  )
}

/** ประกาศ: ผู้โพสต์ เวลา หัวข้อ และข้อความ (คงการขึ้นบรรทัด) — กว้างไม่เกิน 760 px เพื่อให้อ่านง่าย (UX 13) */
export function AnnouncementList({
  posts,
  teacherName,
  heading = 'h3',
  editable = false,
}: {
  posts: Post[]
  teacherName: string
  heading?: Heading
  /** ครู: ปุ่ม “แก้ไข” บนการ์ดประกาศ (UX 9 [ยืนยัน N4]) */
  editable?: boolean
}) {
  const Title = heading
  const copy = th.posts.list
  return (
    <ul className={styles.postList} aria-label={copy.announcementListAria}>
      {posts.map((post) => (
        <li key={post.id}>
          <article className={styles.post}>
            <div className={styles.postHead}>
              <span className={styles.avatar} aria-hidden="true">
                {initialOf(teacherName)}
              </span>
              <span>
                <b>{teacherName}</b>
                <time dateTime={post.published_at}>
                  {thaiDate(post.published_at)} · {thaiTime(post.published_at)} น.
                </time>
              </span>
              {editable && (
                <Link
                  to={`/t/w/${post.id}/edit`}
                  className={styles.cardAction}
                  aria-label={copy.editAria(post.title)}
                >
                  <PenLine aria-hidden="true" />
                  <span aria-hidden="true">{copy.edit}</span>
                </Link>
              )}
              {editable && <DeleteAnnouncement post={post} />}
            </div>
            <Title className={styles.postTitle}>{post.title}</Title>
            {post.body && (
              <p className={styles.postBody}>
                <LinkifiedText text={post.body} />
              </p>
            )}
            {post.files.length > 0 && <AttachmentList files={post.files} />}
          </article>
        </li>
      ))}
    </ul>
  )
}
