import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Archive, Lock, TriangleAlert } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router'
import { th } from '../../copy/th'
import { initialOf } from '../../lib/initial'
import { appErrorOf } from '../../lib/request'
import { useTabParam } from '../../lib/useTabParam'
import { Button, Chip, Tabs } from '../../ui'
import { ClassBanner } from '../classrooms/ClassBanner'
import { roomTermQuery } from '../classrooms/api'
import { RoomEyebrow } from '../classrooms/RoomTerm'
import { useRoomTerm } from '../classrooms/useRoomTerm'
import { postsQuery } from '../posts/api'
import { RoomPosts } from '../posts/RoomPosts'
import { StudentWorkList } from '../work/StudentWorkList'
import { useAuth } from '../../app/auth/useAuth'
import { classroomViewQuery, myClassroomsQuery } from './api'
import {
  hasNewAnnouncement,
  latestAnnouncement,
  markSeen,
  readSeen,
  seenKey,
} from './seenAnnouncements'
import styles from './student.module.css'
import { MemberCharm } from '../rewards/MemberCharm'
import { useCharmImages } from '../charms/charmImages'

const TABS = ['general', 'work', 'members'] as const

// S02 ห้องเรียนของนักเรียน: หัวห้อง + สามแท็บ (งานของคุณครู · โพสต์ทั่วไป · สมาชิก)
// เปิดที่ “โพสต์งานของคุณครู” เสมอ (UX 5 [ยืนยัน 6 ต.ค. 2026]) — ลิงก์ที่ระบุ ?tab= ใช้แท็บนั้น
// ป้าย “ใหม่” บน “โพสต์ทั่วไป”: ประกาศที่โพสต์ภายใน 7 วันและยังไม่เคยเห็น (seenAnnouncements) — เข้าแท็บแล้วจดว่าเห็น
// ตรวจ membership ทุกครั้งที่โหลด (classroom_view) — ถูกครูเอาออกแล้วเห็นข้อความ not_member (UX 7.1)
export default function StudentClassroom() {
  const { classId = '' } = useParams()
  const view = useQuery(classroomViewQuery(classId))
  const roomTerm = useQuery(roomTermQuery(classId))
  const { past } = useRoomTerm(roomTerm.data?.term_id)
  // รูปเครื่องรางที่สมาชิกเลือกแสดง — ขอลิงก์รวมครั้งเดียวต่อหน้าจอ
  const charmImages = useCharmImages(view.data?.members.map((m) => m.charm?.image_asset_id) ?? [])
  const classes = useQuery(myClassroomsQuery)
  const posts = useQuery({ ...postsQuery(classId), enabled: view.isSuccess })
  const [now] = useState(() => Date.now())
  const [tab, selectTab] = useTabParam(TABS, 'work')
  const { state } = useAuth()
  const seen = state.status === 'ready' ? seenKey(state.account.account_id, classId) : null
  // อยู่ในแท็บประกาศ = เห็นแล้ว (รวมประกาศที่เข้ามาใหม่ระหว่างเปิดอยู่) — ไม่ขึ้นป้ายบนแท็บที่กำลังดู
  useEffect(() => {
    if (tab !== 'general' || !seen || !posts.data) return
    const latest = latestAnnouncement(posts.data)
    if (latest) markSeen(seen, latest)
  }, [tab, seen, posts.data])
  const newBadge =
    tab !== 'general' &&
    !!posts.data &&
    hasNewAnnouncement(posts.data, seen ? readSeen(seen) : null, now)
  const queryClient = useQueryClient()
  const error = view.isError ? appErrorOf(view.error) : null
  const notMember = error?.code === 'not_member'

  // ถูกเอาออก: ให้หน้าแรกโหลดรายการห้องใหม่ (ห้องนี้หายไป)
  useEffect(() => {
    if (notMember) void queryClient.invalidateQueries({ queryKey: ['my-classrooms'] })
  }, [notMember, queryClient])

  const back = (
    <Link to="/" className={styles.back}>
      <ArrowLeft aria-hidden="true" />
      {th.student.room.backHome}
    </Link>
  )

  if (view.isPending) {
    return (
      <main className={styles.page}>
        {back}
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </main>
    )
  }
  if (error) {
    return (
      <main className={styles.page} data-width="narrow">
        {back}
        <div className={styles.empty} role="alert">
          {notMember ? <Lock aria-hidden="true" /> : <TriangleAlert aria-hidden="true" />}
          <b>{error.message}</b>
          {error.ref && <span>{th.errors.reference(error.ref)}</span>}
          {notMember ? (
            <Link to="/" className={styles.softLink}>
              {th.student.room.goHome}
            </Link>
          ) : (
            <Button size="sm" variant="soft" onClick={() => void view.refetch()}>
              {th.teacher.retry}
            </Button>
          )}
        </div>
      </main>
    )
  }

  const c = view.data
  if (!c) return null
  const tone = Math.max(
    0,
    (classes.data ?? []).findIndex((x) => x.id === c.id),
  )
  const copy = th.student.room
  return (
    <main className={styles.page}>
      {back}
      <section className={styles.hero} aria-label={c.name}>
        <ClassBanner
          tone={tone}
          size="hero"
          level={1}
          eyebrow={roomTerm.data ? <RoomEyebrow termId={roomTerm.data.term_id} /> : c.term_name}
          title={c.name}
        >
          <span className={styles.teacherLine}>
            <span className={styles.bannerAvatar} aria-hidden="true">
              {initialOf(c.teacher_name)}
            </span>
            {[th.student.classMeta(c.teacher_name, c.member_count + 1), c.description]
              .filter(Boolean)
              .join(' · ')}
          </span>
        </ClassBanner>
      </section>
      {past && (
        <p className={styles.note} data-tone="purple" role="note">
          <Archive aria-hidden="true" />
          <span>{th.classrooms.pastRoomStudent}</span>
        </p>
      )}
      <Tabs
        label={th.classrooms.room.tabsLabel}
        tabs={TABS.map((key) => ({
          key,
          label: th.classrooms.room.tabs[key],
          badge: key === 'general' && newBadge ? th.work.newBadge : undefined,
        }))}
        selected={tab}
        onSelect={selectTab}
      >
        {tab === 'members' ? (
          <>
            <div className={styles.members}>
              <p className={styles.mGroup}>{copy.teacherGroup}</p>
              <div className={styles.mRow}>
                <span className={styles.mAvatar} aria-hidden="true">
                  {initialOf(c.teacher_name)}
                </span>
                <b className={styles.mName}>{c.teacher_name}</b>
              </div>
              <p className={styles.mGroup}>{copy.studentsGroup(c.members.length)}</p>
              <ul className={styles.memGrid}>
                {c.members.map((m, i) => (
                  <li key={`${i}${m.display_name}`} className={styles.mRow} data-me={m.is_me}>
                    <span className={styles.mNo}>{m.roll_number ?? '–'}</span>
                    <span className={styles.mName}>{m.display_name}</span>
                    {m.is_me && <Chip tone="purple">{copy.me}</Chip>}
                    {m.charm && (
                      <MemberCharm
                        charm={m.charm}
                        image={
                          m.charm.image_asset_id
                            ? charmImages.get(m.charm.image_asset_id)
                            : undefined
                        }
                      />
                    )}
                  </li>
                ))}
              </ul>
            </div>
            <p className={styles.muted}>{copy.membersNote}</p>
          </>
        ) : tab === 'work' ? (
          // สถานะส่วนตัวต่องานจาก RPC my_work (สมาชิกขณะนี้) — การ์ดกดเข้า S03
          <StudentWorkList classroomId={c.id} />
        ) : (
          // อ่านโพสต์ผ่าน RLS (สมาชิกขณะนี้) — ถูกเอาออกแล้ว classroom_view ด้านบนตอบ not_member ก่อน
          <RoomPosts
            classroomId={c.id}
            kind="announcement"
            audience="student"
            teacherName={c.teacher_name}
          />
        )}
      </Tabs>
    </main>
  )
}
