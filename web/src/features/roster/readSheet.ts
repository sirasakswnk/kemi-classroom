import type { Range } from 'xlsx'

// ขีดจำกัดกันเบราว์เซอร์ค้าง [ข้อเสนอ] — ไฟล์จริงของครูราว 10 KB และไม่เกิน 50 คนต่อห้อง
export const ROSTER_LIMITS = {
  /** ขนาดไฟล์สูงสุด */
  maxFileBytes: 2 * 1024 * 1024,
  /** อ่านจากไฟล์ไม่เกินจำนวนแถวนี้ (หัวตาราง + รายชื่อ) */
  maxScanRows: 400,
  /** อ่านไม่เกินจำนวนคอลัมน์นี้ (ใช้แค่หาหัวตารางและ 5 ช่อง) */
  maxScanCols: 40,
  /** รายชื่อต่อการนำเข้า 1 ครั้ง — ตรงกับเพดานของ RPC (0003_roster) */
  maxStudents: 300,
  /** หาแถวหัวตาราง “เลขที่” ในกี่แถวแรก */
  headerSearchRows: 10,
} as const

export interface SheetCell {
  /** s = ข้อความ, n = ตัวเลข, b = จริง/เท็จ, d = วันที่, e = ข้อผิดพลาด, z = ว่าง */
  t: string
  v: unknown
}

export interface SheetData {
  grid: (SheetCell | undefined)[][]
  merges: Range[]
  sheetCount: number
  /** แถวในไฟล์มากกว่าที่อ่าน */
  truncated: boolean
}

// อ่าน .xlsx ในเบราว์เซอร์ (ไฟล์ไม่ถูกอัปโหลด) — โหลด SheetJS เฉพาะตอนเรียก จึงไม่อยู่ใน bundle หลัก
// อ่านเฉพาะชีตแรก ไม่อ่านสูตร/สไตล์/HTML และตัดที่ maxScanRows แถว × maxScanCols คอลัมน์
export async function readSheet(data: ArrayBuffer): Promise<SheetData> {
  const XLSX = await import('xlsx')
  const workbook = XLSX.read(data, {
    type: 'array',
    dense: true,
    sheetRows: ROSTER_LIMITS.maxScanRows + 1,
    cellFormula: false,
    cellHTML: false,
    cellStyles: false,
    cellText: false,
    cellDates: false,
  })
  const sheet = workbook.Sheets[workbook.SheetNames[0]]
  const rows = (sheet?.['!data'] ?? []) as ({ t: string; v: unknown } | undefined)[][]
  // แถว/เซลล์ว่างใน !data เป็นช่องโหว่ของ array — สร้างใหม่แบบไม่มีช่องโหว่ (Array.from) ให้ map/spread ทำงานถูก
  const grid = Array.from({ length: Math.min(rows.length, ROSTER_LIMITS.maxScanRows) }, (_, r) => {
    const row = rows[r] ?? []
    return Array.from({ length: Math.min(row.length, ROSTER_LIMITS.maxScanCols) }, (_, c) => {
      const cell = row[c]
      return cell ? { t: cell.t, v: cell.v } : undefined
    })
  })
  return {
    grid,
    merges: sheet?.['!merges'] ?? [],
    sheetCount: workbook.SheetNames.length,
    truncated: rows.length > ROSTER_LIMITS.maxScanRows,
  }
}
