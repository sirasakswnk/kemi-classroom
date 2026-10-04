/** ตัวอักษรในวงกลมรูปแทนตัว (ครูและนักเรียน): ข้ามคำว่า “ครู” ที่ขึ้นต้นชื่อ (แบบ v2 ใช้ “อ” ของ “ครูอิงฟ้า”) และสระหน้า เ แ โ ใ ไ */
export function initialOf(name: string): string {
  const rest = name.replace(/^ครู\s*/, '') || name
  const chars = Array.from(rest.replace(/^[เแโใไ]/, ''))
  return chars[0] ?? Array.from(rest)[0] ?? ''
}
