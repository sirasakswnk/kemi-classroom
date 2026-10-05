// เทียบกฎ CORS/lifecycle ที่ตั้งกับที่ B2 อ่านกลับมา
// B2 เรียงคีย์และรายการใหม่ เปลี่ยนชื่อ header เป็นตัวเล็ก (ETag → etag) และเติมคีย์ที่ไม่ได้ส่ง (เช่น
// daysFromStartingToCancelingUnfinishedLargeFiles: null) จึงเทียบเฉพาะคีย์ที่เราส่ง รายการเทียบแบบไม่สนลำดับ/ตัวพิมพ์
const norm = (v) => (Array.isArray(v) ? v.map((x) => String(x).toLowerCase()).sort() : v)

/** กฎแต่ละข้อจับคู่ด้วยชื่อ (corsRuleName) หรือ prefix (fileNamePrefix) */
export function sameRules(sent, actual, idKey) {
  if (!Array.isArray(actual) || actual.length !== sent.length) return false
  return sent.every((rule) => {
    const got = actual.find((r) => r[idKey] === rule[idKey])
    return (
      got !== undefined &&
      Object.keys(rule).every((k) => JSON.stringify(norm(rule[k])) === JSON.stringify(norm(got[k])))
    )
  })
}
