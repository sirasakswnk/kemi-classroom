/** ตัวอักษรในวงกลมรูปแทนตัว: ข้ามคำว่า “ครู” ที่ขึ้นต้นชื่อ (แบบ v2 ใช้ “อ” ของ “ครูอิงฟ้า”) */
export function initialOfTeacher(name: string): string {
  const rest = name.replace(/^ครู\s*/, '')
  return Array.from(rest || name)[0] ?? ''
}
