// ตัวแปร build ของหน้าเว็บ (ค่าไม่ลับเท่านั้น) — ตัวอย่างใน web/.env.example
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string
  readonly VITE_SUPABASE_PUBLISHABLE_KEY: string
  /** 'prod' = ระบบใช้จริง (ซ่อนแถบระบบทดสอบ); ค่าอื่นหรือไม่ตั้ง = ระบบทดสอบ */
  readonly VITE_DEPLOY_ENV?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
