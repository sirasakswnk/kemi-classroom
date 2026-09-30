/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // รองรับ Safari 15 ขึ้นไป — [ข้อเสนอ] TECHNICAL_BUILD_PLAN ส่วน 1
    target: ['es2021', 'safari15'],
  },
  test: {
    environment: 'node',
  },
})
