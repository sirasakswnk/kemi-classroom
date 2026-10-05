import { Award, CalendarX, FilePen, Paperclip, PenLine, Sparkles } from 'lucide-react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Chip } from '../../ui'
import { AttachmentList } from '../uploads/AttachmentList'
import type { Post } from './api'
import styles from './posts.module.css'

// รายการโพสต์ของห้อง ใช้ร่วมกันใน S02 (นักเรียน) และ T08 (ครู) — แบบ v2 .work-card / .post
// ยังไม่มีหน้างาน S03/T03 (P3-08/P3-09) การ์ดจึงยังไม่เป็นลิงก์ และยังไม่มีสถานะส่ง/ตรวจจริง
// ครู: ปุ่มแก้ไขบนการ์ด (ประกาศ = ถาวรตาม UX 9; การบ้าน = ชั่วคราว ย้ายไปการ์ดโจทย์ของ T03 ใน P3-09)
// ไฟล์ (P3-06b): ประกาศแสดงรายการไฟล์แนบที่เปิดดู/ดาวน์โหลดได้ · การบ้านบอกแค่จำนวนไฟล์โจทย์ (ไฟล์อยู่หน้า S03/T03)

type Heading = 'h2' | 'h3'

/** การบ้าน: ชื่อ กำหนดส่ง (เวลาไทย) และป้ายสถานะ/รางวัล — จอกว้าง ≥ 960 px แสดง 2 คอลัมน์ (UX 13) */
export function HomeworkList({
  posts,
  audience,
  heading = 'h3',
}: {
  posts: Post[]
  audience: 'student' | 'teacher'
  heading?: Heading
}) {
  const copy = th.posts.list
  const Title = heading
  return (
    <ul
      className={styles.workList}
      data-columns={audience === 'student' ? '2' : undefined}
      aria-label={copy.homeworkListAria}
    >
      {posts.map((post) => {
        const a = post.assignment
        return (
          <li key={post.id}>
            <article className={styles.workCard} data-action={audience === 'teacher' || undefined}>
              <span className={styles.wIc} aria-hidden="true">
                <FilePen />
              </span>
              <div className={styles.workText}>
                <Title className={styles.workTitle}>{post.title}</Title>
                {a && (
                  <span className={styles.meta}>
                    {copy.due(thaiDate(a.due_at), thaiTime(a.due_at))}
                  </span>
                )}
                <span className={styles.chips}>
                  {audience === 'student' ? (
                    <Chip tone="amber" icon={<FilePen />}>
                      {copy.notSubmitted}
                    </Chip>
                  ) : (
                    a && (
                      <Chip tone="plain" icon={<Award />}>
                        {copy.fullScore(a.full_score)}
                      </Chip>
                    )
                  )}
                  {post.files.length > 0 && (
                    <Chip tone="plain" icon={<Paperclip />}>
                      {th.files.homeworkCount(post.files.length)}
                    </Chip>
                  )}
                  {a && a.reward_tokens > 0 && (
                    <Chip tone="gold" icon={<Sparkles />}>
                      {copy.reward(a.reward_tokens)}
                    </Chip>
                  )}
                  {audience === 'teacher' && a && (
                    <Chip tone="plain" icon={<CalendarX />}>
                      {a.close_at
                        ? copy.closeAt(thaiDate(a.close_at), thaiTime(a.close_at))
                        : copy.noClose}
                    </Chip>
                  )}
                </span>
              </div>
              {audience === 'teacher' && (
                <Link
                  to={`/t/w/${post.id}/edit`}
                  className={styles.cardAction}
                  aria-label={copy.editAria(post.title)}
                >
                  <PenLine aria-hidden="true" />
                  <span aria-hidden="true">{copy.editHomework}</span>
                </Link>
              )}
            </article>
          </li>
        )
      })}
    </ul>
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
            </div>
            <Title className={styles.postTitle}>{post.title}</Title>
            {post.body && <p className={styles.postBody}>{post.body}</p>}
            {post.files.length > 0 && <AttachmentList files={post.files} />}
          </article>
        </li>
      ))}
    </ul>
  )
}
