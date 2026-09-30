import { useEffect } from 'react'
import { useNavigate } from 'react-router'
import { supabase } from '../../lib/supabase'
import { takeNextPath } from '../../lib/redirect'
import { FullPageStatus } from '../common/FullPageStatus'
import { th } from '../../copy/th'

// แลก code (PKCE) เป็น session ครั้งเดียวต่อ code — StrictMode ในโหมดพัฒนาเรียก effect สองรอบ
const exchanges = new Map<string, Promise<boolean>>()

function exchangeOnce(code: string): Promise<boolean> {
  let p = exchanges.get(code)
  if (!p) {
    p = supabase.auth.exchangeCodeForSession(code).then(({ error }) => !error)
    exchanges.set(code, p)
  }
  return p
}

// /auth/callback?code=… (สำเร็จ) หรือ ?error=…&error_description=… (ผู้ใช้ยกเลิก/บัญชีถูกบล็อก)
export function AuthCallback() {
  const navigate = useNavigate()

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const code = params.get('code')
    const failed = () => navigate('/login', { replace: true, state: { failed: true } })

    if (!code || params.has('error')) {
      failed()
      return
    }
    exchangeOnce(code).then((ok) => {
      if (!ok) failed()
      // หน้าเดิมที่จำไว้ (ตรวจแล้วว่าเป็น path ภายในเว็บ) ไม่งั้นหน้าแรก แล้ว RequireRole พาไปหน้าของบทบาท
      else navigate(takeNextPath() ?? '/', { replace: true })
    })
  }, [navigate])

  return (
    <FullPageStatus>
      <p role="status">{th.login.signingIn}</p>
    </FullPageStatus>
  )
}
