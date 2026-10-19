// บันทึก Blob เป็นไฟล์ในเครื่องผู้ใช้ผ่านลิงก์ชั่วคราว (ไม่ผ่านเซิร์ฟเวอร์ — ข้อมูลอยู่ในหน้านี้อยู่แล้ว)
// ใช้กับ CSV ตารางคะแนน (T04) และ PDF รวมของงานส่ง (T03)
export function downloadBlob(fileName: string, blob: Blob) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = fileName
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}
