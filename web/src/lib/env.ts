// สภาพแวดล้อมของ build — ตัวแปร build ของ Cloudflare Pages (TECHNICAL_BUILD_PLAN ส่วน 3)
// แถบ “ระบบทดสอบ” แสดงเสมอ เว้นแต่ตั้ง VITE_DEPLOY_ENV=prod ตรงตัว:
// ลืมตั้งหรือสะกดผิดแล้วแถบยังขึ้น ไม่ใช่หายไปเงียบ ๆ
export function isTestDeployment(
  deployEnv: string | undefined = import.meta.env.VITE_DEPLOY_ENV,
): boolean {
  return deployEnv !== 'prod'
}
