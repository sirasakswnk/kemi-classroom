import js from '@eslint/js'
import { defineConfig, globalIgnores } from 'eslint/config'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default defineConfig([
  globalIgnores(['dist', 'coverage']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: { globals: globals.browser },
  },
  {
    // zod ต้องผ่าน src/lib/zod.ts ที่ปิด JIT ไว้ให้เข้ากับ CSP (script-src 'self' ห้าม eval)
    files: ['src/**/*.{ts,tsx}'],
    ignores: ['src/lib/zod.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        { paths: [{ name: 'zod', message: 'ใช้ import { z } จาก src/lib/zod แทน' }] },
      ],
    },
  },
])
