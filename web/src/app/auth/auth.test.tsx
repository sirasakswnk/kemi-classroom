import { renderToString } from 'react-dom/server'
import { MemoryRouter } from 'react-router'
import { describe, expect, it } from 'vitest'
import { AccountSchema, homeFor } from './account'
import { AuthContext, type AuthState } from './authContext'
import { LoginPage } from './LoginPage'
import { PrivacyPage } from './PrivacyPage'

describe('ผลของ ensure_account()', () => {
  const ok = {
    account_id: '30000000-0000-4000-8000-000000000001',
    role: 'teacher',
    email: 't1@example.com',
    teacher_id: '10000000-0000-4000-8000-000000000001',
  }

  it('อ่านผลที่ถูกต้องได้', () => {
    expect(AccountSchema.parse(ok)).toEqual(ok)
  })

  it.each([
    { ...ok, role: 'superuser' },
    { ...ok, account_id: 'not-a-uuid' },
    { role: 'student' },
    null,
  ])('ปฏิเสธผลที่ผิดรูปแบบ %#', (value) => {
    expect(AccountSchema.safeParse(value).success).toBe(false)
  })

  it('หน้าแรกตามบทบาท', () => {
    expect(homeFor('student')).toBe('/')
    expect(homeFor('teacher')).toBe('/t')
    expect(homeFor('admin')).toBe('/admin')
  })
})

describe('A01 LoginPage', () => {
  const render = (state: AuthState, locationState?: unknown) =>
    renderToString(
      <MemoryRouter initialEntries={[{ pathname: '/login', state: locationState }]}>
        <AuthContext value={{ state, signOut: async () => {}, reloadAccount: () => {} }}>
          <LoginPage />
        </AuthContext>
      </MemoryRouter>,
    )

  it('แสดงปุ่ม Google ข้อความแนะนำ และสามขั้นตอนเริ่มใช้', () => {
    const html = render({ status: 'signed_out' })
    expect(html).toContain('ลงชื่อเข้าใช้ด้วย Google')
    expect(html).toContain('ใช้ได้ทั้งบัญชี Google ส่วนตัวและบัญชีของโรงเรียน')
    expect(html).toContain('เลือกชื่อตัวเอง')
    expect(html).toContain('ไม่มีปุ่มสมัครเป็นครู')
    expect(html).not.toContain('role="alert"')
  })

  it('เข้าไม่สำเร็จ: บอกว่าบัญชีโรงเรียนอาจไม่อนุญาตเว็บภายนอก', () => {
    const html = render({ status: 'signed_out' }, { failed: true })
    expect(html).toContain('role="alert"')
    expect(html).toContain('เข้าสู่ระบบไม่สำเร็จ')
    expect(html).toContain('บัญชีโรงเรียนนี้อาจไม่อนุญาตให้ใช้กับเว็บภายนอก')
  })

  it('ข้อความแจ้งจากการออกจากระบบให้ (เช่น provider_not_allowed)', () => {
    const html = render({ status: 'signed_out', notice: 'เข้าสู่ระบบได้ด้วยบัญชี Google เท่านั้น' })
    expect(html).toContain('เข้าสู่ระบบได้ด้วยบัญชี Google เท่านั้น')
  })
})

describe('/privacy (P7-05b)', () => {
  const html = renderToString(
    <MemoryRouter initialEntries={['/privacy']}>
      <PrivacyPage />
    </MemoryRouter>,
  )

  it('แสดงหัวข้อครบ 6 หัวข้อ และไม่ต้องล็อกอิน (ไม่ใช้ AuthContext)', () => {
    for (const heading of [
      'ข้อมูลที่เก็บ',
      'ใช้ข้อมูลเพื่ออะไร',
      'ใครเห็นข้อมูล',
      'เก็บข้อมูลที่ไหน',
      'เก็บนานเท่าไร',
      'ติดต่อและขอแก้ไขข้อมูล',
    ]) {
      expect(html).toContain(`<h2>${heading}</h2>`)
    }
  })

  it('ระบุที่เก็บและอายุข้อมูลตาม SYSTEM_SPEC (สิงคโปร์ · เนเธอร์แลนด์ · 60 วัน · 1 ปี · 7 วัน)', () => {
    expect(html).toContain('สิงคโปร์')
    expect(html).toContain('เนเธอร์แลนด์')
    expect(html).toContain('60 วัน')
    expect(html).toContain('1 ปี')
    expect(html).toContain('7 วัน')
    expect(html).toContain('href="/login"')
  })
})

describe('A01 ลิงก์นโยบายความเป็นส่วนตัว', () => {
  it('หน้าเข้าสู่ระบบมีลิงก์ไป /privacy', () => {
    const html = renderToString(
      <MemoryRouter initialEntries={['/login']}>
        <AuthContext
          value={{
            state: { status: 'signed_out' },
            signOut: async () => {},
            reloadAccount: () => {},
          }}
        >
          <LoginPage />
        </AuthContext>
      </MemoryRouter>,
    )
    expect(html).toContain('href="/privacy"')
    expect(html).toContain('นโยบายความเป็นส่วนตัว')
  })
})
