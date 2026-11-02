// sameRules() กับค่าที่ B2 อ่านกลับมาจริงตอนรัน apply-settings.mjs กับ kemi-dev-files (5 ต.ค. 2026)
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { sameRules } from './rules.mjs'

const here = (name) => new URL(name, import.meta.url)
const cors = JSON.parse(readFileSync(here('cors.json'), 'utf8'))
const lifecycle = JSON.parse(readFileSync(here('lifecycle.json'), 'utf8'))

const readBackCors = [
  {
    allowedHeaders: ['content-type', 'content-length'],
    allowedOperations: ['s3_head', 's3_put', 's3_get'],
    allowedOrigins: [
      'https://kemi-classroom.pages.dev',
      'https://*.kemi-classroom.pages.dev',
      'http://localhost:5173',
    ],
    corsRuleName: 'kemi-web',
    exposeHeaders: ['etag', 'x-amz-version-id'],
    maxAgeSeconds: 3600,
  },
]
const readBackLifecycle = [
  {
    daysFromHidingToDeleting: 1,
    daysFromStartingToCancelingUnfinishedLargeFiles: null,
    daysFromUploadingToHiding: null,
    fileNamePrefix: 'files/',
  },
  {
    daysFromHidingToDeleting: 1,
    daysFromStartingToCancelingUnfinishedLargeFiles: null,
    daysFromUploadingToHiding: 1,
    fileNamePrefix: 'staging/',
  },
  {
    daysFromHidingToDeleting: 1,
    daysFromUploadingToHiding: 1,
    fileNamePrefix: 'restore-test/',
  },
]

test('ค่าที่ B2 อ่านกลับ (เรียงใหม่, etag ตัวเล็ก, คีย์เพิ่ม) นับว่าตรงกับไฟล์', () => {
  assert.equal(sameRules(cors, readBackCors, 'corsRuleName'), true)
  assert.equal(sameRules(lifecycle, readBackLifecycle, 'fileNamePrefix'), true)
})

test('ค่าที่ต่างจริงนับว่าไม่ตรง', () => {
  const extraOrigin = [{ ...readBackCors[0], allowedOrigins: ['*'] }]
  assert.equal(sameRules(cors, extraOrigin, 'corsRuleName'), false)
  const longerAge = [{ ...readBackCors[0], maxAgeSeconds: 86400 }]
  assert.equal(sameRules(cors, longerAge, 'corsRuleName'), false)
  const noStaging = readBackLifecycle.slice(0, 1)
  assert.equal(sameRules(lifecycle, noStaging, 'fileNamePrefix'), false)
  const keepHidden = [
    readBackLifecycle[0],
    { ...readBackLifecycle[1], daysFromHidingToDeleting: 30 },
    readBackLifecycle[2],
  ]
  assert.equal(sameRules(lifecycle, keepHidden, 'fileNamePrefix'), false)
  assert.equal(sameRules(cors, undefined, 'corsRuleName'), false)
})
