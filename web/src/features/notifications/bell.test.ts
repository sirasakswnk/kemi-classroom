import { describe, expect, it } from 'vitest'
import { th } from '../../copy/th'
import type { NotificationItem } from './api'
import { bellTime, studentBellRow, teacherBellRow } from './bellState'

const NOW = new Date('2026-10-24T08:00:00Z') // 24 ต.ค. 15:00 น. เวลาไทย
const POST = '80480000-0000-4000-8000-000000000001'
const ROOM = '70480000-0000-4000-8000-000000000001'

const item = (over: Partial<NotificationItem>): NotificationItem => ({
  id: '90480000-0000-4000-8000-0000000000d1',
  kind: 'post_published',
  at: '2026-10-22T05:00:00Z',
  read: false,
  relevant: true,
  submitted: null,
  post_id: POST,
  post_kind: 'homework',
  title: 'สมดุลเคมี',
  classroom_id: ROOM,
  classroom_name: 'ม.5/1',
  due_at: '2026-10-25T13:00:00Z',
  comment_id: null,
  comment_retracted: null,
  student_id: null,
  student_name: null,
  pending_count: null,
  level: null,
  ...over,
})

describe('C01 กระดิ่งนักเรียน — แสดงตามสถานะปัจจุบัน', () => {
  it('งานใหม่ไป S03 · ประกาศใหม่ไปแท็บโพสต์ทั่วไปของห้อง', () => {
    const work = studentBellRow(item({}), NOW)
    expect(work).toMatchObject({
      icon: 'newWork',
      title: th.bell.newWork,
      detail: 'สมดุลเคมี',
      href: `/w/${POST}`,
      unread: true,
      faded: null,
    })
    const ann = studentBellRow(item({ post_kind: 'announcement', due_at: null }), NOW)
    expect(ann).toMatchObject({
      icon: 'announcement',
      title: th.bell.newAnnouncement,
      href: `/c/${ROOM}?tab=general`,
    })
  })

  it('เตือนใกล้ส่งยังไม่ส่ง: บอกกำหนดและดึงความสนใจ', () => {
    const row = studentBellRow(item({ kind: 'due_reminder', submitted: false }), NOW)
    expect(row).toMatchObject({
      icon: 'reminder',
      title: th.bell.dueReminder,
      detail: 'สมดุลเคมี · 25 ต.ค. 20:00 น.',
      unread: true,
      faded: null,
    })
  })

  it('เตือนใกล้ส่งที่ส่งแล้ว/ปิดรับแล้ว: จาง ไม่นับยังไม่อ่าน แม้ยังไม่เคยเปิด', () => {
    const sent = studentBellRow(
      item({ kind: 'due_reminder', relevant: false, submitted: true }),
      NOW,
    )
    expect(sent).toMatchObject({ faded: th.bell.fadedSubmitted, unread: false })
    const closed = studentBellRow(
      item({ kind: 'due_reminder', relevant: false, submitted: false }),
      NOW,
    )
    expect(closed).toMatchObject({ faded: th.bell.fadedClosed, unread: false })
  })

  it('ความคิดเห็นที่ยกเลิก → “ข้อความนี้ถูกยกเลิก” และไม่มีเนื้อข้อความ', () => {
    const live = studentBellRow(
      item({
        kind: 'teacher_comment',
        comment_id: 'c0480000-0000-4000-8000-000000000001',
        comment_retracted: false,
      }),
      NOW,
    )
    expect(live).toMatchObject({
      icon: 'comment',
      title: th.bell.teacherComment,
      detail: 'สมดุลเคมี',
      faded: null,
      unread: true,
    })
    const gone = studentBellRow(
      item({
        kind: 'teacher_comment',
        comment_id: 'c0480000-0000-4000-8000-000000000002',
        comment_retracted: true,
        relevant: false,
      }),
      NOW,
    )
    expect(gone).toMatchObject({ faded: th.bell.retracted, unread: false, href: `/w/${POST}` })
  })

  it('เปลี่ยนกำหนดแสดงกำหนดปัจจุบันของงาน · ชนิดอื่นไปงานนั้น', () => {
    expect(studentBellRow(item({ kind: 'due_changed' }), NOW)?.detail).toBe(
      'สมดุลเคมี → 25 ต.ค. 20:00 น.',
    )
    expect(studentBellRow(item({ kind: 'intake_closed' }), NOW)).toMatchObject({
      icon: 'closed',
      title: th.bell.intakeClosed,
    })
    expect(studentBellRow(item({ kind: 'revision_opened' }), NOW)?.icon).toBe('revision')
    expect(studentBellRow(item({ kind: 'solution_published' }), NOW)).toMatchObject({
      icon: 'solution',
      href: `/w/${POST}`,
    })
  })

  it('อ่านแล้ว → ไม่เน้น · ชนิดของครูไม่อยู่ในกระดิ่งนักเรียน', () => {
    expect(studentBellRow(item({ read: true }), NOW)?.unread).toBe(false)
    expect(studentBellRow(item({ kind: 'pending_review', pending_count: 2 }), NOW)).toBeNull()
    expect(
      studentBellRow(item({ kind: 'storage_threshold', post_id: null, level: 90 }), NOW),
    ).toBeNull()
  })

  it('เวลา: วันนี้บอกเวลา วันอื่นบอกวันที่ (เวลาไทย)', () => {
    expect(bellTime('2026-10-24T01:30:00Z', NOW)).toBe('08:30 น.')
    expect(bellTime('2026-10-23T17:30:00Z', NOW)).toBe('00:30 น.') // 24 ต.ค. 00:30 น. ไทย
    expect(bellTime('2026-10-23T16:30:00Z', NOW)).toBe('23 ต.ค.')
    expect(bellTime('2025-10-23T05:00:00Z', NOW)).toBe('23 ต.ค. 2568')
  })
})

describe('T11 กระดิ่งครู — แสดงตามสถานะปัจจุบัน', () => {
  const STUDENT = '60480000-0000-4000-8000-000000000001'

  it('งานรอตรวจรวมต่องาน: ชื่องาน — ห้อง + จำนวนรอตรวจปัจจุบัน → T03 สถานะการส่ง', () => {
    const row = teacherBellRow(
      item({ kind: 'pending_review', at: '2026-10-24T03:10:00Z', pending_count: 7 }),
      NOW,
    )
    expect(row).toMatchObject({
      icon: 'pending',
      title: 'สมดุลเคมี — ม.5/1',
      detail: th.bell.teacher.pendingCount(7),
      href: `/t/w/${POST}`,
      unread: true,
      faded: null,
      today: true,
      time: '10:10 น.',
    })
  })

  it('ตรวจครบแล้ว: จาง ไม่นับยังไม่อ่าน ไม่บอกจำนวน', () => {
    const row = teacherBellRow(
      item({ kind: 'pending_review', relevant: false, pending_count: 0 }),
      NOW,
    )
    expect(row).toMatchObject({ detail: '', faded: th.bell.teacher.pendingDone, unread: false })
  })

  it('ความคิดเห็นจากนักเรียน: ชื่อ + งาน ไม่มีเนื้อข้อความ → หน้าของนักเรียนคนนั้น (แม้ยังไม่ส่ง)', () => {
    const row = teacherBellRow(
      item({ kind: 'student_comment', student_id: STUDENT, student_name: 'อนุชา อินทร์แก้ว' }),
      NOW,
    )
    expect(row).toMatchObject({
      icon: 'comment',
      title: 'อนุชา อินทร์แก้ว เขียนความคิดเห็น',
      detail: 'ในงาน สมดุลเคมี',
      href: `/t/w/${POST}/u/${STUDENT}`,
      today: false,
      time: '22 ต.ค. 12:00 น.',
    })
    const retracted = teacherBellRow(
      item({ kind: 'student_comment', student_id: STUDENT, comment_retracted: true }),
      NOW,
    )
    expect(retracted).toMatchObject({ faded: th.bell.retracted, unread: false })
  })

  it('พื้นที่เก็บไฟล์ → T07 · เต็มกับ 90% ใช้ถ้อยคำต่างกัน', () => {
    const full = teacherBellRow(item({ kind: 'storage_threshold', level: 100 }), NOW)
    expect(full).toMatchObject({
      icon: 'storage',
      title: th.bell.teacher.storageFull,
      href: '/t/term',
    })
    const ninety = teacherBellRow(item({ kind: 'storage_threshold', level: 90 }), NOW)
    expect(ninety?.title).toBe(th.bell.teacher.storageUsed(90))
  })

  it('วันนี้/ก่อนหน้าตัดตามวันไทย · ชนิดของนักเรียนไม่อยู่ในกระดิ่งครู', () => {
    expect(
      teacherBellRow(item({ kind: 'pending_review', at: '2026-10-23T17:30:00Z' }), NOW)?.today,
    ).toBe(true)
    expect(
      teacherBellRow(item({ kind: 'pending_review', at: '2026-10-23T16:59:00Z' }), NOW)?.today,
    ).toBe(false)
    expect(teacherBellRow(item({ kind: 'post_published' }), NOW)).toBeNull()
    expect(teacherBellRow(item({ kind: 'due_reminder' }), NOW)).toBeNull()
  })
})
