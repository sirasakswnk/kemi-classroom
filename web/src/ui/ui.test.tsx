import { Plus } from 'lucide-react'
import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { Button, Chip, Field, Input, Textarea } from '.'

// ค่า attribute แรกของแท็กที่ระบุ
const attr = (html: string, tag: string, name: string) =>
  html.match(new RegExp(`<${tag}\\b[^>]*\\s${name}="([^"]*)"`))?.[1]

describe('Button', () => {
  it('ค่าเริ่มต้นเป็น type="button" กันส่งฟอร์มโดยไม่ตั้งใจ', () => {
    expect(attr(renderToString(<Button>ส่ง</Button>), 'button', 'type')).toBe('button')
  })

  it('คง type="submit" เมื่อระบุ', () => {
    expect(attr(renderToString(<Button type="submit">ส่ง</Button>), 'button', 'type')).toBe(
      'submit',
    )
  })

  it('ไอคอนถูกซ่อนจากเครื่องอ่านหน้าจอ', () => {
    const html = renderToString(<Button icon={<Plus />}>สร้าง</Button>)
    expect(attr(html, 'span', 'aria-hidden')).toBe('true')
    expect(html).toContain('สร้าง')
  })
})

describe('Chip', () => {
  it('แสดงคำพร้อมไอคอนที่ซ่อนจากเครื่องอ่านหน้าจอ', () => {
    const html = renderToString(
      <Chip tone="green" icon={<Plus />}>
        ส่งแล้ว
      </Chip>,
    )
    expect(html).toContain('ส่งแล้ว')
    expect(html).toMatch(/<span[^>]*aria-hidden="true"[^>]*><svg/)
  })
})

describe('Field', () => {
  it('ผูก label กับช่องกรอก และคำอธิบายด้วย aria-describedby', () => {
    const html = renderToString(
      <Field label="ชื่อชั้นเรียน" hint="แสดงในหน้าแรก">
        <Input />
      </Field>,
    )
    const id = attr(html, 'input', 'id')
    expect(id).toBeTruthy()
    expect(attr(html, 'label', 'for')).toBe(id)
    const describedBy = attr(html, 'input', 'aria-describedby')
    expect(describedBy).toBeTruthy()
    expect(attr(html, 'p', 'id')).toBe(describedBy)
    expect(attr(html, 'input', 'aria-invalid')).toBeUndefined()
  })

  it('มีข้อผิดพลาด: aria-invalid และอ้างถึงทั้งคำอธิบายและข้อความผิดพลาด', () => {
    const html = renderToString(
      <Field label="เปอร์เซ็นต์หัก" hint="0–100" error="ใส่จำนวนเต็ม 0–100">
        <Input />
      </Field>,
    )
    expect(attr(html, 'input', 'aria-invalid')).toBe('true')
    const ids = attr(html, 'input', 'aria-describedby')?.split(' ') ?? []
    expect(ids).toHaveLength(2)
    for (const id of ids) expect(html).toContain(`id="${id}"`)
    expect(html).toContain('ใส่จำนวนเต็ม 0–100')
  })

  it('ช่องไม่บังคับต่อท้ายว่า ไม่บังคับ และใช้กับ Textarea ได้', () => {
    const html = renderToString(
      <Field label="รายละเอียด" optional id="desc">
        <Textarea />
      </Field>,
    )
    expect(html).toContain('ไม่บังคับ')
    expect(attr(html, 'textarea', 'id')).toBe('desc')
    expect(attr(html, 'label', 'for')).toBe('desc')
  })
})
