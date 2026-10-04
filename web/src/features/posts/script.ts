// ปุ่มตัวห้อย/ตัวยกใน T02 (SYSTEM_SPEC ส่วน 3): แปลงตัวเลขและ + − ที่เลือกเป็นอักขระ Unicode เก็บเป็นข้อความธรรมดา
// เช่น H2O → H₂O, Fe3+ → Fe³⁺ (แบบ v2 แปลงเฉพาะตัวเลขและเครื่องหมาย ตัวอื่นคงเดิม)

export type ScriptKind = 'sub' | 'sup'

const SUB: Record<string, string> = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
  '+': '₊',
  '-': '₋',
  '−': '₋',
}
const SUP: Record<string, string> = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '+': '⁺',
  '-': '⁻',
  '−': '⁻',
}

/** แปลงตัวเลขและ + − ในข้อความเป็นตัวห้อยหรือตัวยก */
export function toScript(text: string, kind: ScriptKind): string {
  const map = kind === 'sub' ? SUB : SUP
  return text.replace(/[0-9+\-−]/g, (ch) => map[ch] ?? ch)
}

/** แปลงเฉพาะช่วงที่เลือกในช่องข้อความ — ไม่ได้เลือกอะไรคืน null (หน้าเว็บบอกให้เลือกก่อน) */
export function applyScript(
  value: string,
  start: number,
  end: number,
  kind: ScriptKind,
): { value: string; start: number; end: number } | null {
  if (start === end) return null
  const mid = toScript(value.slice(start, end), kind)
  return { value: value.slice(0, start) + mid + value.slice(end), start, end: start + mid.length }
}
