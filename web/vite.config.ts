/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // พอร์ตคงที่ให้ตรง Redirect URL ของ Supabase (http://localhost:5173/auth/callback)
    port: 5173,
    strictPort: true,
  },
  build: {
    // รองรับ Safari 15 ขึ้นไป — [ข้อเสนอ] TECHNICAL_BUILD_PLAN ส่วน 1
    target: ['es2021', 'safari15'],
  },
  test: {
    environment: 'node',
    // ค่าหลอกให้สร้าง Supabase client ได้ในเทสต์ (ไม่มีการเรียกเครือข่าย)
    env: {
      VITE_SUPABASE_URL: 'http://127.0.0.1:54321',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'test-publishable-key',
    },
  },
})
