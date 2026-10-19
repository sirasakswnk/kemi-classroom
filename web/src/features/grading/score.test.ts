/// <reference types="node" />
// ชุดสูตรคะแนนเดียวกับ pgTAP (BUILD_PLAN ส่วน 9): ไฟล์ JSON ร่วม + ตรวจว่าชุดที่ฝังใน 0025_grading.test.sql ตรงกัน
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { netScore } from './score'

type ScoreCase = { raw: number; pct: number; net: number; note: string }

const TESTS = resolve(process.cwd(), '../supabase/tests')
const casesText = readFileSync(resolve(TESTS, 'fixtures/score_cases.json'), 'utf8')
const cases = JSON.parse(casesText) as ScoreCase[]

describe('netScore', () => {
  it.each(cases)('($raw, $pct%) → $net · $note', ({ raw, pct, net }) => {
    expect(netScore(raw, pct)).toBe(net)
  })

  it('ชุดใน pgTAP ตรงกับไฟล์ร่วม', () => {
    const sql = readFileSync(resolve(TESTS, '0025_grading.test.sql'), 'utf8')
    const embedded = /\$cases\$([\s\S]*?)\$cases\$/.exec(sql)?.[1]
    expect(embedded).toBeDefined()
    expect(JSON.parse(embedded ?? 'null')).toEqual(cases)
  })
})
