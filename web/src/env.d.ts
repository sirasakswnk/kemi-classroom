// ตัวแปร build ของหน้าเว็บ (ค่าไม่ลับเท่านั้น) — ตัวอย่างใน web/.env.example
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string
  readonly VITE_SUPABASE_PUBLISHABLE_KEY: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
