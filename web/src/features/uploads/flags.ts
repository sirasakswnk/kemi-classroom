// ช่องไฟล์ใน T02 เปิดเฉพาะ dev server (npm run dev) จนกว่า P3-06b จะผูกไฟล์กับโพสต์ได้
// preview/production เป็น build จริง (import.meta.env.DEV = false) จึงไม่เห็นปุ่มที่ยังใช้งานไม่ได้
export const FILE_FIELD_ENABLED = import.meta.env.DEV
