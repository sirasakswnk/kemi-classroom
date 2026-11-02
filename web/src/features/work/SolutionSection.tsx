import { useQuery } from '@tanstack/react-query'
import { Pencil, TriangleAlert } from 'lucide-react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Chip, LinkifiedText } from '../../ui'
import { solutionQuery } from '../review/assignmentApi'
import { AttachmentList } from '../uploads/AttachmentList'
import { when } from './workState'
import styles from './work.module.css'

// S03 เฉลย (UX 6, 8): เห็นหลังเผยแพร่เท่านั้น (RLS solutions_select ส่งแถวให้สมาชิกเมื่อ published_at ไม่ว่าง)
// แสดงเวลาแก้ไขล่าสุดเมื่อครูแก้หลังเผยแพร่ · ไฟล์เฉลยเปิดด้วยแถวไฟล์เดียวกับไฟล์โจทย์
export function SolutionSection({ postId }: { postId: string }) {
  const copy = th.work.solution
  const q = useQuery({ ...solutionQuery(postId), staleTime: 0 })
  const solution = q.data
  if (q.isPending) return null
  if (q.isError) {
    return (
      <section className={styles.section} aria-labelledby="workSolution">
        <div className={styles.sectionHead}>
          <h2 id="workSolution">{copy.title}</h2>
        </div>
        <p className={styles.error} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{appErrorOf(q.error).message || copy.loadFailed}</span>
        </p>
      </section>
    )
  }
  if (!solution?.publishedAt) return null
  const edited = Date.parse(solution.updatedAt) > Date.parse(solution.publishedAt)

  return (
    <section className={styles.section} aria-labelledby="workSolution">
      <div className={styles.sectionHead}>
        <h2 id="workSolution">{copy.title}</h2>
        <Chip tone="green">{copy.published(when(solution.publishedAt))}</Chip>
      </div>
      <div className={styles.card}>
        {solution.body ? (
          <p className={styles.prose}>
            <LinkifiedText text={solution.body} />
          </p>
        ) : (
          <p className={styles.muted}>{copy.filesOnly}</p>
        )}
        {solution.files.length > 0 && <AttachmentList files={solution.files} />}
        {edited && (
          <p className={styles.edited}>
            <Pencil aria-hidden="true" />
            {copy.edited(when(solution.updatedAt))}
          </p>
        )}
      </div>
    </section>
  )
}
