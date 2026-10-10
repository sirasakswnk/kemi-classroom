import { ChevronDown, ChevronUp, Pencil } from 'lucide-react'
import { useId, useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import type { Post } from '../posts/api'
import { AttachmentList } from '../uploads/AttachmentList'
import { when } from '../work/workState'
import styles from './review.module.css'

// T03 การ์ด “โจทย์และไฟล์” (UX 9 [ยืนยัน N]; แบบ v2 probCard): รายละเอียด ไฟล์โจทย์ (เปิดดู/ดาวน์โหลด) “แก้ไขล่าสุด …”
// ปุ่ม “แก้ไขงาน” (T02 โหมดแก้ไข → กลับ T03) และพับเก็บได้ — ปุ่ม “ลบงาน” มากับ N4 ในระยะ 4 (P4-09)
export function ProblemCard({ post }: { post: Post }) {
  const [open, setOpen] = useState(true)
  const bodyId = useId()
  const copy = th.review
  return (
    <section className={styles.card} aria-labelledby={`${bodyId}h`}>
      <div className={styles.cardHead}>
        <h2 id={`${bodyId}h`}>{copy.problemCard}</h2>
        <span className={styles.cardAct}>
          <Link to={`/t/w/${post.id}/edit`} className={styles.link}>
            <Pencil aria-hidden="true" />
            {copy.editWork}
          </Link>
          <button
            type="button"
            className={styles.toggle}
            aria-expanded={open}
            aria-controls={bodyId}
            aria-label={open ? copy.collapse : copy.expand}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <ChevronUp aria-hidden="true" /> : <ChevronDown aria-hidden="true" />}
          </button>
        </span>
      </div>
      <div id={bodyId} hidden={!open} className={styles.page}>
        {post.body ? (
          <p className={styles.prose}>{post.body}</p>
        ) : (
          <p className={styles.muted}>{copy.noBody}</p>
        )}
        {post.files.length > 0 ? (
          <AttachmentList files={post.files} />
        ) : (
          <p className={styles.muted}>{copy.noFiles}</p>
        )}
        {post.content_updated_at && (
          <p className={styles.edited}>
            <Pencil aria-hidden="true" />
            {copy.edited(when(post.content_updated_at))}
          </p>
        )}
      </div>
    </section>
  )
}
