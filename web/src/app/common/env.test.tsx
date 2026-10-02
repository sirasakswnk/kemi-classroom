import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { isTestDeployment } from '../../lib/env'
import { EnvBanner } from './EnvBanner'

const TEXT = 'ระบบทดสอบ · ใช้ข้อมูลสมมติเท่านั้น'

describe('isTestDeployment', () => {
  it.each([undefined, '', 'dev', 'preview', 'production', 'PROD', ' prod'])(
    'ค่า %j = ระบบทดสอบ (แสดงแถบ)',
    (value) => {
      expect(isTestDeployment(value as string | undefined)).toBe(true)
    },
  )

  it("เฉพาะ 'prod' ตรงตัวเท่านั้นที่เป็นระบบใช้จริง", () => {
    expect(isTestDeployment('prod')).toBe(false)
  })

  it('ไม่ส่งค่า = อ่านจากตัวแปร build (ในเทสต์ไม่ได้ตั้ง จึงเป็นระบบทดสอบ)', () => {
    expect(isTestDeployment()).toBe(true)
  })
})

describe('EnvBanner', () => {
  it('ค่าเริ่มต้น (ไม่ได้ตั้ง VITE_DEPLOY_ENV): แสดงแถบ', () => {
    const html = renderToString(<EnvBanner />)
    expect(html).toContain(TEXT)
    expect(html).toContain('role="note"')
  })

  it('ค่าที่ไม่ใช่ prod: แสดงแถบ', () => {
    expect(renderToString(<EnvBanner deployEnv="preview" />)).toContain(TEXT)
    expect(renderToString(<EnvBanner deployEnv="" />)).toContain(TEXT)
  })

  it('VITE_DEPLOY_ENV=prod: ไม่แสดงแถบ', () => {
    expect(renderToString(<EnvBanner deployEnv="prod" />)).toBe('')
  })
})
