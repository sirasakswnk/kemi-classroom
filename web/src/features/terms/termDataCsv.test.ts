import { describe, expect, it } from 'vitest'
import { BOM } from '../gradebook/gradeCsv'
import type { TermData, TermDataRow } from './api'
import { csvTime, termDataCsv, termDataFileName } from './termDataCsv'

const row = (over: Partial<TermDataRow> = {}): TermDataRow => ({
  classroom_name: 'เคมี 5/4',
  post_id: '00000000-0000-4000-8000-000000000001',
  post_title: 'สมดุลเคมี',
  full_score: 10,
  due_at: '2026-10-24T13:00:00Z',
  student_code: '01234',
  display_name: 'อนุชา ทดสอบ',
  group_name: '5/4',
  roll_number: 3,
  member: true,
  first_submitted_at: null,
  last_submitted_at: null,
  content_revision: null,
  graded_current: null,
  raw_score: null,
  passed: null,
  timing: null,
  applied_penalty_pct: null,
  net_score: null,
  graded_at: null,
  comments: [],
  ...over,
})

const data = (rows: TermDataRow[]): TermData => ({
  term_id: '00000000-0000-4000-8000-0000000000aa',
  term_name: 'ภาคเรียนที่ 2/2569',
  fingerprint: 'f'.repeat(32),
  count: rows.length,
  bytes: 0,
  rows,
})

const lines = (csv: string) => csv.slice(BOM.length).split('\r\n')

describe('termDataCsv', () => {
  it('ขึ้นต้นด้วย BOM + หัวตาราง และนับบรรทัดข้อมูลเท่าจำนวนแถว', () => {
    const { csv, count } = termDataCsv(data([row(), row({ student_code: '02' })]))
    expect(csv.startsWith(BOM)).toBe(true)
    expect(csv.endsWith('\r\n')).toBe(true)
    expect(lines(csv)[0]).toBe(
      'ห้อง,งาน,คะแนนเต็ม,กำหนดส่ง,ห้องในรายชื่อ,เลขที่,รหัสนักเรียน,ชื่อ-นามสกุล,สถานะในห้อง,ส่งครั้งแรก,ส่งล่าสุด,ฉบับที่,ผลตรวจ,คะแนนดิบ,ส่งทัน/สาย,หักสาย (%),คะแนนสุทธิ,ผ่าน,ตรวจเมื่อ,ความคิดเห็น',
    )
    expect(count).toBe(2)
    expect(lines(csv)).toHaveLength(4) // หัว + 2 แถว + บรรทัดว่างท้าย
  })

  it('ยังไม่ส่ง: ช่องเวลาส่ง/คะแนนว่าง เวลาเป็นเวลาไทย รหัสคงศูนย์นำหน้า', () => {
    const { csv } = termDataCsv(data([row()]))
    expect(lines(csv)[1]).toBe(
      'เคมี 5/4,สมดุลเคมี,10,2026-10-24 20:00,5/4,3,01234,อนุชา ทดสอบ,อยู่ในห้อง,,,,ยังไม่ส่ง,,,,,,,',
    )
  })

  it('ตรวจแล้ว ส่งสาย และคนที่ออกจากห้องแล้ว', () => {
    const { csv } = termDataCsv(
      data([
        row({
          member: false,
          group_name: null,
          roll_number: null,
          first_submitted_at: '2026-10-24T17:30:00Z',
          last_submitted_at: '2026-10-25T01:05:00Z',
          content_revision: 2,
          graded_current: true,
          raw_score: 8,
          passed: true,
          timing: 'late',
          applied_penalty_pct: 50,
          net_score: 4,
          graded_at: '2026-10-26T02:00:00Z',
        }),
      ]),
    )
    expect(lines(csv)[1]).toBe(
      'เคมี 5/4,สมดุลเคมี,10,2026-10-24 20:00,,,01234,อนุชา ทดสอบ,ออกจากห้องแล้ว,2026-10-25 00:30,2026-10-25 08:05,2,ตรวจแล้ว,8,สาย,50,4,ผ่าน,2026-10-26 09:00,',
    )
  })

  it('รอตรวจ (ส่งแก้หลังตรวจ) ยังแสดงคะแนนครั้งก่อน และตรวจแล้วไม่มีคะแนน', () => {
    const waiting = termDataCsv(
      data([
        row({
          graded_current: false,
          raw_score: 7,
          net_score: 7,
          passed: false,
          timing: 'on_time',
        }),
      ]),
    ).csv
    expect(lines(waiting)[1]).toContain(',รอตรวจ,7,ทัน,,7,ไม่ผ่าน,')
    const noScore = termDataCsv(data([row({ graded_current: true, passed: true })])).csv
    expect(lines(noScore)[1]).toContain(',ตรวจแล้ว (ไม่มีคะแนน),')
  })

  it('ความคิดเห็นรวมในช่องเดียว บรรทัดละข้อความ ที่ยกเลิกไม่มีเนื้อความ', () => {
    const { csv } = termDataCsv(
      data([
        row({
          comments: [
            {
              author: 'teacher',
              created_at: '2026-10-24T03:00:00Z',
              retracted: false,
              body: 'ดีมาก "เยี่ยม"',
            },
            // กันพลาด: ถึงจะมีเนื้อความติดมา ที่ยกเลิกแล้วต้องไม่เขียนลงไฟล์
            {
              author: 'student',
              created_at: '2026-10-24T04:00:00Z',
              retracted: true,
              body: 'ความลับ',
            },
          ],
        }),
      ]),
    )
    expect(csv).not.toContain('ความลับ')
    expect(csv).toContain(
      '"2026-10-24 10:00 ครู: ดีมาก ""เยี่ยม""\n2026-10-24 11:00 นักเรียน: (ข้อความนี้ถูกยกเลิก)"\r\n',
    )
  })

  it('กันสูตรในชื่องาน ชื่อห้อง และชื่อนักเรียน', () => {
    const { csv } = termDataCsv(
      data([
        row({ classroom_name: '@ห้อง', post_title: '=HYPERLINK("x")', display_name: '+66 ชื่อ' }),
      ]),
    )
    expect(lines(csv)[1].startsWith(`'@ห้อง,"'=HYPERLINK(""x"")",10,`)).toBe(true)
    expect(lines(csv)[1]).toContain(",'+66 ชื่อ,")
  })

  it('ชื่อไฟล์บอกภาคเรียนและตัดอักขระต้องห้าม', () => {
    expect(termDataFileName('ภาคเรียนที่ 2/2569')).toBe('คะแนน_ทุกห้อง_ภาคเรียนที่ 2 2569.csv')
    expect(csvTime(null)).toBeNull()
  })
})
