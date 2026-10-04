// node --test ops/ — ตัวกันรัน pgTAP กับฐานข้อมูลนอกเครื่องยอมเฉพาะ kemi-dev
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { DEV_PROJECT, checkLinkedProject } from './check-dev-db.mjs'

const linked = (ref, name) => {
  const dir = mkdtempSync(join(tmpdir(), 'kemi-link-'))
  if (ref !== undefined) writeFileSync(join(dir, 'project-ref'), `${ref}\n`)
  if (name !== undefined) writeFileSync(join(dir, 'linked-project.json'), JSON.stringify({ ref, name }))
  return dir
}

test('ผูกกับ kemi-dev → ผ่าน', () => {
  assert.equal(checkLinkedProject(linked(DEV_PROJECT.ref, DEV_PROJECT.name)), null)
})

test('ผูกกับโปรเจกต์อื่น (เช่น prod) → ปฏิเสธ', () => {
  assert.match(checkLinkedProject(linked('aaaaaaaaaaaaaaaaaaaa', 'kemi-prod')), /ไม่ใช่ kemi-dev/)
})

test('ref ถูกแต่ชื่อไม่ใช่ kemi-dev → ปฏิเสธ', () => {
  assert.match(checkLinkedProject(linked(DEV_PROJECT.ref, 'kemi-prod')), /ไม่ใช่ kemi-dev/)
})

test('ยังไม่ได้ผูกโปรเจกต์ → ปฏิเสธ', () => {
  assert.match(checkLinkedProject(linked(undefined, undefined)), /ยังไม่ได้ผูกโปรเจกต์/)
})
