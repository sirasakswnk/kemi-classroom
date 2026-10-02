import { Plus } from 'lucide-react'
import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { Button, Chip, Field, Input, Modal, Sheet, Stepper, Steps, Textarea } from '.'

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

describe('Stepper', () => {
  const html = (value: number) =>
    renderToString(<Stepper label="โทเคน" value={value} onChange={() => {}} min={0} max={10} />)

  it('ปุ่มมี aria-label และกลุ่มมีชื่อ', () => {
    const h = html(3)
    expect(attr(h, 'div', 'role')).toBe('group')
    expect(attr(h, 'div', 'aria-label')).toBe('โทเคน')
    expect(h).toContain('aria-label="ลดโทเคน"')
    expect(h).toContain('aria-label="เพิ่มโทเคน"')
    expect(h).not.toContain('aria-disabled')
  })

  it('ถึงขอบเขตแล้วปิดปุ่มฝั่งนั้นด้วย aria-disabled (ยังรับโฟกัสได้)', () => {
    expect(html(0)).toMatch(/aria-label="ลดโทเคน" aria-disabled="true"/)
    expect(html(10)).toMatch(/aria-label="เพิ่มโทเคน" aria-disabled="true"/)
    expect(html(0)).not.toMatch(/\sdisabled=""/)
  })

  it('ค่าอยู่ใน live region พร้อมชื่อสำหรับเครื่องอ่านหน้าจอ', () => {
    const h = html(3)
    expect(attr(h, 'output', 'aria-live')).toBe('polite')
    expect(h).toMatch(/<output[^>]*>.*โทเคน.*3<\/output>/)
  })
})

describe('Steps', () => {
  it('ขั้นปัจจุบันเท่านั้นที่มี aria-current="step" และบอกสถานะให้เครื่องอ่านหน้าจอ', () => {
    const h = renderToString(
      <Steps
        label="ขั้นตอนของงานนี้"
        steps={[
          { label: 'ส่งงาน', state: 'done' },
          { label: 'ครูตรวจ', state: 'now' },
          { label: 'งานครบถ้วน', state: 'todo' },
          { label: 'ได้โทเคน', state: 'skip' },
        ]}
      />,
    )
    expect(attr(h, 'ol', 'aria-label')).toBe('ขั้นตอนของงานนี้')
    expect(h.match(/aria-current="step"/g)).toHaveLength(1)
    expect(h).toMatch(/<li[^>]*aria-current="step"[^>]*>.*?ครูตรวจ/)
    expect(h).toContain('เสร็จแล้ว')
    expect(h).toContain('ข้ามขั้นนี้')
  })
})

describe('Sheet / Modal', () => {
  it('Sheet ปิดได้มีปุ่ม ปิด และผูกหัวเรื่องกับ aria-labelledby', () => {
    const h = renderToString(
      <Sheet open onClose={() => {}} title="ได้รับเครื่องราง!" description="เก็บเข้าตู้แล้ว">
        <p>เนื้อหา</p>
      </Sheet>,
    )
    expect(h).toContain('aria-label="ปิด"')
    expect(attr(h, 'h2', 'id')).toBe(attr(h, 'dialog', 'aria-labelledby'))
    expect(h).toContain(`id="${attr(h, 'dialog', 'aria-describedby')}"`)
  })

  it('Sheet ปิดเองไม่ได้ (A02) ไม่มีปุ่ม ปิด', () => {
    const h = renderToString(
      <Sheet open onClose={() => {}} dismissible={false} title="เลือกชื่อของคุณ">
        <p>ค้นชื่อ</p>
      </Sheet>,
    )
    expect(h).not.toContain('aria-label="ปิด"')
    expect(h).toContain('เลือกชื่อของคุณ')
  })

  it('Modal แสดงหัวเรื่อง เนื้อหา และปุ่มท้าย; ปิดอยู่ไม่แสดงเนื้อหา', () => {
    const open = renderToString(
      <Modal open onClose={() => {}} title="เปลี่ยนกำหนดส่ง" footer={<button>บันทึก</button>}>
        <p>เนื้อหา</p>
      </Modal>,
    )
    expect(open).toContain('เปลี่ยนกำหนดส่ง')
    expect(open).toContain('บันทึก')
    const closed = renderToString(
      <Modal open={false} onClose={() => {}} title="เปลี่ยนกำหนดส่ง">
        <p>เนื้อหา</p>
      </Modal>,
    )
    expect(closed).not.toContain('เนื้อหา')
  })
})
