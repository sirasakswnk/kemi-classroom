import { th } from '../../copy/th'
import { bangkokParts, thaiDate, thaiTime } from '../../lib/thaiTime'
import type { NotificationItem } from './api'

// แปลงรายการกระดิ่งของนักเรียน (C01) เป็นสิ่งที่แสดง — ตามสถานะปัจจุบันจากเซิร์ฟเวอร์ ไม่ใช่ข้อความที่เก็บไว้ตอนเกิดเหตุ
// (แบบ v2 NOTIFS/sNotif; UX 12) · ชนิดของครู (T11) ไม่อยู่ในกระดิ่งนักเรียน → null

export type BellIcon =
  | 'newWork'
  | 'announcement'
  | 'reminder'
  | 'comment'
  | 'revision'
  | 'dueChanged'
  | 'closed'
  | 'solution'

export type BellRow = {
  id: string
  icon: BellIcon
  title: string
  detail: string
  /** ปลายทางเมื่อกด: S03 ของงาน หรือแท็บโพสต์ทั่วไปของห้อง (ประกาศ) */
  href: string
  /** ยังไม่อ่าน และยังเกี่ยวข้อง — รายการที่จางไม่ดึงความสนใจแม้ยังไม่อ่าน */
  unread: boolean
  /** หมดความเกี่ยวข้องแล้ว: บอกเหตุผลสั้น ๆ (ส่งแล้ว / ปิดรับแล้ว / ข้อความนี้ถูกยกเลิก) */
  faded: string | null
  at: string
  time: string
}

const dueText = (dueAt: string | null, now: Date) =>
  dueAt ? th.bell.due(thaiDate(dueAt, now), thaiTime(dueAt)) : ''

/** เวลาของรายการ: วันนี้ → “14:30 น.” · วันอื่น → “28 ก.ย.” */
export function bellTime(at: string, now: Date): string {
  return bangkokParts(at).date === bangkokParts(now).date
    ? th.bell.today(thaiTime(at))
    : thaiDate(at, now)
}

export function studentBellRow(item: NotificationItem, now: Date): BellRow | null {
  const copy = th.bell
  const title = item.title ?? ''
  const work = `/w/${item.post_id}`
  const base = { id: item.id, at: item.at, time: bellTime(item.at, now), href: work, detail: title }
  let row: Omit<BellRow, 'unread' | 'faded'>
  let faded: string | null = null
  switch (item.kind) {
    case 'post_published':
      row =
        item.post_kind === 'announcement'
          ? {
              ...base,
              icon: 'announcement',
              title: copy.newAnnouncement,
              href: `/c/${item.classroom_id}?tab=general`,
            }
          : { ...base, icon: 'newWork', title: copy.newWork }
      break
    case 'due_reminder':
      row = {
        ...base,
        icon: 'reminder',
        title: copy.dueReminder,
        detail: copy.withDue(title, dueText(item.due_at, now)),
      }
      if (!item.relevant) faded = item.submitted ? copy.fadedSubmitted : copy.fadedClosed
      break
    case 'teacher_comment':
      row = { ...base, icon: 'comment', title: copy.teacherComment }
      if (item.comment_retracted) faded = copy.retracted
      break
    case 'revision_opened':
      row = { ...base, icon: 'revision', title: copy.revisionOpened }
      break
    case 'due_changed':
      row = {
        ...base,
        icon: 'dueChanged',
        title: copy.dueChanged,
        detail: copy.newDue(title, dueText(item.due_at, now)),
      }
      break
    case 'intake_closed':
      row = { ...base, icon: 'closed', title: copy.intakeClosed }
      break
    case 'solution_published':
      row = { ...base, icon: 'solution', title: copy.solutionPublished }
      break
    default:
      return null
  }
  // relevant = false ที่ไม่มีเหตุผลเฉพาะ (ไม่ควรเกิดกับชนิดของนักเรียน) ก็ยังจาง
  if (!faded && !item.relevant) faded = copy.fadedClosed
  return { ...row, faded, unread: !item.read && !faded }
}

export type TeacherBellIcon = 'pending' | 'comment' | 'storage'

export type TeacherBellRow = Omit<BellRow, 'icon'> & {
  icon: TeacherBellIcon
  /** เหตุการณ์ล่าสุดเกิดวันนี้ (เวลาไทย) → กลุ่ม “วันนี้” ไม่งั้น “ก่อนหน้า” */
  today: boolean
}

/**
 * T11 กระดิ่งครู (แบบ v2 tNotifRow) — งานรอตรวจแสดงจำนวนรอตรวจปัจจุบัน ไม่ใช่ตอนเกิดเหตุ
 * ความคิดเห็นบอกชื่อนักเรียนและงานโดยไม่มีเนื้อข้อความ → หน้าของนักเรียนคนนั้นพร้อมช่องความคิดเห็น (แม้ยังไม่ส่ง)
 * ชนิดของนักเรียนไม่อยู่ในกระดิ่งครู → null
 */
export function teacherBellRow(item: NotificationItem, now: Date): TeacherBellRow | null {
  const copy = th.bell
  const t = copy.teacher
  const title = item.title ?? ''
  const today = bangkokParts(item.at).date === bangkokParts(now).date
  const time = today
    ? copy.today(thaiTime(item.at))
    : t.earlierTime(thaiDate(item.at, now), thaiTime(item.at))
  const base = { id: item.id, at: item.at, time, today }
  let row: Omit<TeacherBellRow, 'unread' | 'faded'>
  let faded: string | null = null
  switch (item.kind) {
    case 'pending_review':
      row = {
        ...base,
        icon: 'pending',
        title: t.pending(title, item.classroom_name ?? ''),
        detail: item.relevant ? t.pendingCount(item.pending_count ?? 0) : '',
        href: `/t/w/${item.post_id}`,
      }
      if (!item.relevant) faded = t.pendingDone
      break
    case 'student_comment':
      row = {
        ...base,
        icon: 'comment',
        title: t.studentComment(item.student_name ?? ''),
        detail: t.inWork(title),
        href: `/t/w/${item.post_id}/u/${item.student_id}`,
      }
      if (item.comment_retracted) faded = copy.retracted
      break
    case 'storage_threshold':
      row =
        item.level === 100
          ? {
              ...base,
              icon: 'storage',
              title: t.storageFull,
              detail: t.storageFullDetail,
              href: '/t/term',
            }
          : {
              ...base,
              icon: 'storage',
              title: t.storageUsed(item.level ?? 0),
              detail: t.storageUsedDetail,
              href: '/t/term',
            }
      break
    default:
      return null
  }
  return { ...row, faded, unread: !item.read && !faded }
}
