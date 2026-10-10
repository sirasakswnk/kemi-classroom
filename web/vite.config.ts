/// <reference types="vitest/config" />
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
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

// แจ้งสัญญาอนุญาตของไลบรารีภายนอกที่ไปกับหน้าเว็บ (dist/third-party-licenses.txt) — TECHNICAL_BUILD_PLAN ส่วน 1
// รายการจาก package-lock.json เฉพาะ dependency ที่ไม่ใช่ dev พร้อมข้อความสัญญาฉบับเต็มของแต่ละแพ็กเกจ
// libheif-js (LGPL-3.0) อยู่ในไฟล์ assets/heic.worker-*.js แบบไม่แก้ไข — ระบุแหล่งซอร์สให้ดาวน์โหลดได้
const LICENSE_FILE = /^(licen[cs]e|copying|notice)(\.(md|txt))?$/i
const SOURCE_NOTE: Record<string, string> = {
  'libheif-js':
    'ใช้ใน assets/heic.worker-*.js (ถอดรูป HEIC บนเครื่องผู้ใช้) โดยไม่แก้ไขซอร์ส · ' +
    'ซอร์ส: https://github.com/catdad-experiments/libheif-js (ห่อ libheif https://github.com/strukturag/libheif ' +
    'และ libde265 https://github.com/strukturag/libde265) — แทนที่ด้วยรุ่นอื่นได้โดย build ใหม่จาก repo นี้',
}

function licenseFiles(dir: string): string[] {
  // ไฟล์สัญญาที่ราก และในโฟลเดอร์ย่อยหนึ่งชั้น (เช่น libheif-js/libheif/LICENSE)
  const found: string[] = []
  for (const name of readdirSync(dir)) {
    const full = resolve(dir, name)
    if (LICENSE_FILE.test(name) && statSync(full).isFile()) found.push(full)
    else if (name !== 'node_modules' && statSync(full).isDirectory())
      for (const sub of readdirSync(full))
        if (LICENSE_FILE.test(sub) && statSync(resolve(full, sub)).isFile())
          found.push(resolve(full, sub))
  }
  return found
}

export function thirdPartyLicenses(root: string): string {
  const lock = JSON.parse(readFileSync(resolve(root, 'package-lock.json'), 'utf8')) as {
    packages: Record<string, { version?: string; license?: string; dev?: boolean }>
  }
  const parts = [
    'ห้องเคมี — สัญญาอนุญาตของซอฟต์แวร์ภายนอก (Third-party software licenses)',
    'สร้างอัตโนมัติตอน build จาก package-lock.json (เฉพาะ dependency ที่ใช้ในหน้าเว็บ)',
    '',
  ]
  const entries = Object.entries(lock.packages)
    .filter(([key, info]) => key.startsWith('node_modules/') && !info.dev)
    .sort(([a], [b]) => a.localeCompare(b))
  for (const [key, info] of entries) {
    const name = key.replace(/^.*node_modules\//, '')
    const dir = resolve(root, key)
    parts.push('='.repeat(78), `${name} ${info.version ?? ''} — ${info.license ?? 'ไม่ระบุ'}`)
    if (SOURCE_NOTE[name]) parts.push(SOURCE_NOTE[name])
    const files = existsSync(dir) ? licenseFiles(dir) : []
    if (files.length === 0) parts.push('(แพ็กเกจไม่มีไฟล์สัญญาแยก — ดูสัญญาตามชื่อที่ระบุ)')
    for (const file of files) parts.push('-'.repeat(78), readFileSync(file, 'utf8').trim())
    parts.push('')
  }
  return parts.join('\n')
}

function licensesFile(): Plugin {
  return {
    name: 'kemi-third-party-licenses',
    apply: 'build',
    generateBundle() {
      this.emitFile({
        type: 'asset',
        fileName: 'third-party-licenses.txt',
        source: thirdPartyLicenses(import.meta.dirname),
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, import.meta.dirname, 'VITE_')
  return {
    plugins: [react(), supabaseCspHeaders(env.VITE_SUPABASE_URL), licensesFile()],
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
