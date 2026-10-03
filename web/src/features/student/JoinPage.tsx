import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import { Link, useNavigate, useParams } from 'react-router'
import { th } from '../../copy/th'
import { useToast } from '../../ui'
import { termQuery } from '../classrooms/api'
import { JoinClass } from './JoinClass'
import styles from './student.module.css'

// /join/:code ลิงก์เชิญ: มาถึงหน้านี้หลังล็อกอินและเลือกชื่อแล้ว (StudentLayout) — แสดงชื่อห้องให้ตรวจ
// แล้วนักเรียนกดเข้าร่วมเอง ไม่เข้าอัตโนมัติ (TECHNICAL_BUILD_PLAN 6, UX 4)
export default function JoinPage() {
  const { code = '' } = useParams()
  const term = useQuery(termQuery)
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const toast = useToast()

  return (
    <main className={styles.page} data-width="narrow">
      <Link to="/" className={styles.back}>
        <ArrowLeft aria-hidden="true" />
        {th.student.invite.backHome}
      </Link>
      <div className={styles.greet}>
        <span className={styles.eyebrow}>{th.student.invite.eyebrow}</span>
        <h1>{th.student.invite.title}</h1>
        <p>{th.student.invite.body}</p>
      </div>
      <JoinClass
        key={code}
        initialCode={code}
        autoSearch
        invite
        termName={term.data?.name ?? ''}
        onJoined={(c) => {
          toast(th.student.join.joined(c.name), { tone: 'success' })
          void queryClient.invalidateQueries({ queryKey: ['my-classrooms'] })
          navigate(`/c/${c.id}`, { replace: true })
        }}
      />
    </main>
  )
}
