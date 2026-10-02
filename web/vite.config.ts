/// <reference types="vitest/config" />
import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv, type Plugin } from 'vite'

// ใส่ origin ของ Supabase ลง CSP ใน dist/_headers ตอน build (ต้นแบบ: public/_headers)
// ไม่มี VITE_SUPABASE_URL = build ล้ม เพื่อไม่ให้ปล่อยหน้าเว็บที่ตั้งค่าไม่ครบ
function supabaseCspHeaders(supabaseUrl: string | undefined): Plugin {
  let outDir = 'dist'
  return {
    name: 'kemi-csp-headers',
    apply: 'build',
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir)
    },
    closeBundle() {
      let origin: string
      try {
        origin = new URL(supabaseUrl ?? '').origin
      } catch {
        throw new Error('ต้องตั้งตัวแปร build VITE_SUPABASE_URL (ดู web/.env.example)')
      }
      const file = resolve(outDir, '_headers')
      const template = readFileSync(file, 'utf8')
      if (!template.includes('__SUPABASE_ORIGIN__')) {
        throw new Error('public/_headers ไม่มี __SUPABASE_ORIGIN__')
      }
      writeFileSync(file, template.replaceAll('__SUPABASE_ORIGIN__', origin))
    },
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, import.meta.dirname, 'VITE_')
  return {
    plugins: [react(), supabaseCspHeaders(env.VITE_SUPABASE_URL)],
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
  }
})
