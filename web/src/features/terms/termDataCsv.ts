import { th } from '../../copy/th'
import { bangkokParts } from '../../lib/thaiTime'
import { BOM, csvField, csvFileName } from '../gradebook/gradeCsv'
import type { TermData, TermDataRow } from './api'

// CSV คะแนน เวลาส่ง และความคิดเห็นของภาคเรียนเก่า (P6-05a2; SYSTEM_SPEC ข้อ 62, J9.3)
// กฎเดียวกับ CSV ตารางคะแนน: UTF-8 BOM + กันสูตรด้วย ' นำหน้า (csvField)
// หนึ่งบรรทัดต่อ (งาน, นักเรียน) ตามลำดับที่เซิร์ฟเวอร์ส่ง — จำนวนบรรทัดข้อมูลคือ count ที่ส่งกลับตอนบันทึกว่าดาวน์โหลดครบ
// ความคิดเห็นรวมในช่องเดียว บรรทัดละข้อความ; ที่ยกเลิกแล้วเซิร์ฟเวอร์ไม่ส่งเนื้อความ จึงเขียนแค่ “(ข้อความนี้ถูกยกเลิก)”

/** เวลาไทย “YYYY-MM-DD HH:mm” (ปี ค.ศ.) — เรียงตามตัวอักษรได้ถูกและ Excel อ่านเป็นวันเวลา */
export function csvTime(when: string | null): string | null {
  if (!when) return null
  const { date, time } = bangkokParts(when)
  return `${date} ${time}`
}

function resultText(row: TermDataRow): string {
  const g = th.gradebook.csv
  if (row.graded_current === null) return g.notSubmitted
  if (!row.graded_current) return g.waiting
  return row.net_score === null ? g.noScore : th.terms.dataCsv.graded
}

function commentsText(row: TermDataRow): string {
  const copy = th.terms.dataCsv
  return row.comments
    .map((c) => {
      const who = c.author === 'student' ? copy.student : copy.teacher
      const text = c.retracted || c.body === null ? copy.retracted : c.body
      return `${csvTime(c.created_at)} ${who}: ${text}`
    })
    .join('\n')
}

export function termDataCsv(data: TermData): { csv: string; count: number } {
  const copy = th.terms.dataCsv
  const g = th.gradebook.csv
  const lines = [copy.head.map(csvField).join(',')]
  for (const r of data.rows) {
    lines.push(
      [
        r.classroom_name,
        r.post_title,
        r.full_score,
        csvTime(r.due_at),
        r.group_name,
        r.roll_number,
        // ไฟล์เก็บรหัสตามจริง (ศูนย์นำหน้าอยู่ครบ) แต่ Excel ที่เปิด CSV ตรง ๆ อาจตัดศูนย์นำหน้าตอนแสดง
        r.student_code,
        r.display_name,
        r.member ? g.member : g.left,
        csvTime(r.first_submitted_at),
        csvTime(r.last_submitted_at),
        r.content_revision,
        resultText(r),
        r.raw_score,
        r.timing === null ? null : r.timing === 'late' ? copy.late : copy.onTime,
        r.applied_penalty_pct,
        r.net_score,
        r.passed === null ? null : r.passed ? copy.pass : copy.fail,
        csvTime(r.graded_at),
        commentsText(r) || null,
      ]
        .map(csvField)
        .join(','),
    )
  }
  return { csv: `${BOM}${lines.join('\r\n')}\r\n`, count: data.rows.length }
}

export const termDataFileName = (termName: string) =>
  csvFileName(th.terms.dataCsv.fileRoom, termName)
