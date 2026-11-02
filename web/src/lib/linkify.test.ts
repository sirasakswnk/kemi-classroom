import { describe, expect, it } from 'vitest'
import { linkify } from './linkify'

const text = (text: string) => ({ kind: 'text', text })
const link = (url: string) => ({ kind: 'link', text: url, href: url })
const links = (input: string) => linkify(input).filter((s) => s.kind === 'link')

describe('linkify', () => {
  it('ไม่มีลิงก์หรือข้อความว่าง', () => {
    expect(linkify('ทำข้อ 1 ถึง 5')).toEqual([text('ทำข้อ 1 ถึง 5')])
    expect(linkify('')).toEqual([])
  })

  it('ลิงก์ปกติ http และ https พร้อมข้อความรอบข้าง', () => {
    expect(linkify('ดูที่ https://example.com/a?b=1&c=2#d นะ')).toEqual([
      text('ดูที่ '),
      link('https://example.com/a?b=1&c=2#d'),
      text(' นะ'),
    ])
    expect(linkify('http://example.com')).toEqual([link('http://example.com')])
    expect(linkify('HTTPS://Example.com')).toEqual([link('HTTPS://Example.com')])
  })

  it('เฉพาะ http(s) — javascript: data: และอื่น ๆ ไม่เป็นลิงก์', () => {
    for (const input of [
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      "javascript:alert('https://evil.example')",
      'data:text/html,<script>alert(1)</script>',
      'data:text/html,https://evil.example',
      'vbscript:msgbox(1)',
      'ftp://example.com',
      'www.example.com',
      'xhttps://example.com',
      'https://',
      'https://...',
    ]) {
      expect(linkify(input)).toEqual([text(input)])
    }
  })

  it('คำว่า data: ที่เป็นป้ายหน้าลิงก์ยังเป็นลิงก์', () => {
    expect(links('Data:https://example.com/sheet')).toEqual([link('https://example.com/sheet')])
  })

  it('ตัดวรรคตอนท้ายลิงก์ออกไปเป็นข้อความ', () => {
    for (const mark of ['.', ',', ';', ':', '!', '?', "'", ')', ']', ').', '...', '”', '”.']) {
      expect(linkify(`https://example.com/a${mark}`)).toEqual([
        link('https://example.com/a'),
        text(mark),
      ])
    }
    expect(linkify('(ดู https://example.com/a)')).toEqual([
      text('(ดู '),
      link('https://example.com/a'),
      text(')'),
    ])
    expect(linkify('“https://example.com/a”')).toEqual([
      text('“'),
      link('https://example.com/a'),
      text('”'),
    ])
  })

  it('คงวรรคตอนและวงเล็บที่เป็นส่วนของลิงก์', () => {
    for (const url of [
      'https://en.wikipedia.org/wiki/Acid_(chemistry)',
      'https://example.com/a.b,c;d/e',
      'https://example.com/?u=https://other.example',
    ]) {
      expect(linkify(url)).toEqual([link(url)])
    }
    expect(linkify('https://en.wikipedia.org/wiki/Acid_(chemistry)).')).toEqual([
      link('https://en.wikipedia.org/wiki/Acid_(chemistry)'),
      text(').'),
    ])
  })

  it('ข้อความไทยติดกับลิงก์ทั้งสองด้าน', () => {
    expect(linkify('ดูที่นี่https://example.com/abcแล้วทำข้อ 1')).toEqual([
      text('ดูที่นี่'),
      link('https://example.com/abc'),
      text('แล้วทำข้อ 1'),
    ])
    expect(linkify('ลิงก์:https://example.com')).toEqual([
      text('ลิงก์:'),
      link('https://example.com'),
    ])
  })

  it('หลายลิงก์ในบรรทัดเดียว', () => {
    expect(linkify('ก https://a.example ข http://b.example/c. ค')).toEqual([
      text('ก '),
      link('https://a.example'),
      text(' ข '),
      link('http://b.example/c'),
      text('. ค'),
    ])
    expect(linkify('https://a.example,https://b.example;https://c.example')).toEqual([
      link('https://a.example'),
      text(','),
      link('https://b.example'),
      text(';'),
      link('https://c.example'),
    ])
  })

  it('ตัวห้อย/ตัวยกและการขึ้นบรรทัดคงเดิมในส่วนข้อความ', () => {
    expect(linkify('H₂O\nhttps://example.com/a\nFe³⁺')).toEqual([
      text('H₂O\n'),
      link('https://example.com/a'),
      text('\nFe³⁺'),
    ])
    expect(linkify('https://example.com/aH₂O')).toEqual([
      link('https://example.com/aH'),
      text('₂O'),
    ])
  })

  it('อักขระที่ใช้ทำ HTML ไม่อยู่ในลิงก์', () => {
    expect(linkify('https://example.com/"><img')).toEqual([
      link('https://example.com/'),
      text('"><img'),
    ])
  })
})
