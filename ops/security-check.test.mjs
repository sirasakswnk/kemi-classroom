// unit test ของ ops/security-check.mjs — ไม่เรียกฐานข้อมูลหรือเครือข่าย
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { buildSql, scanText, signaturesOf } from './security-check.mjs'

const tests = readFileSync(
  new URL('../supabase/tests/function_privileges.test.sql', import.meta.url),
  'utf8',
)

test('ดึงรายการจาก function_privileges.test.sql ครบ แม้คอมเมนต์ในรายการมี ;', () => {
  const sample = `insert into t values
  -- คอมเมนต์ที่มี ; อยู่ข้างใน
  ('public.a(uuid,boolean)'),
  ('private.b()');
insert into other values ('public.c()');`
  assert.deepEqual(signaturesOf(sample, 't'), ['public.a(uuid,boolean)', 'private.b()'])
  const block = (name) => {
    const start = tests.indexOf(`insert into ${name} values`)
    const end = tests.indexOf("');\n", start)
    return (tests.slice(start, end).match(/^ {2}\('/gm) ?? []).length + 0
  }
  for (const name of ['expected_authenticated', 'expected_service_only', 'postgres_only']) {
    assert.equal(signaturesOf(tests, name).length, block(name), name)
  }
  assert.ok(
    signaturesOf(tests, 'expected_authenticated').includes('public.export_term_data(uuid,boolean)'),
  )
})

test('แทนรายการลง SQL ตรงตำแหน่ง values และไม่มีตัวยึดเหลือ', () => {
  const sql = buildSql(readFileSync(new URL('./security/checks.sql', import.meta.url), 'utf8'), {
    auth: ['public.x(text)'],
    service: ['public.ping()'],
    pgOnly: ['private.backup_start()'],
  })
  assert.match(sql, /exp_auth\(fn\) as \(values \('public\.x\(text\)'\)\)/)
  assert.match(sql, /pg_only\(fn\) as \(values \('private\.backup_start\(\)'\)\)/)
  assert.doesNotMatch(sql, /\/\*(AUTH|SERVICE|PGONLY)\*\//)
})

test('ค้น build: เจอ service role / sb_secret_ / JWT / กุญแจ B2 แต่ publishable key ผ่าน', () => {
  assert.deepEqual(scanText('const k = "sb_publishable_kpY6n1jpQSDKeqLBXZPAYQ_LY_pyyYR"'), [])
  assert.deepEqual(scanText('role: "service_role"'), ['service_role'])
  assert.deepEqual(scanText('x="sb_secret_abcdefghijkl"'), ['sb_secret_'])
  assert.deepEqual(scanText('a="eyJhbGciOiJIUzI1NiIsInR5cCI6"'), ['JWT (legacy anon/service key)'])
  assert.deepEqual(scanText('k="K003abcdefghijklmnopqrstuvwxyz0"'), ['B2 application key'])
})
