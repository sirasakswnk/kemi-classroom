import type { Session } from '@supabase/supabase-js'
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase, toAppError, type AppError } from '../../lib/supabase'
import { AccountSchema, type Account } from './account'
import { AuthContext, type AuthContextValue, type AuthState } from './authContext'

type AccountResult =
  | { userId: string; reloadKey: number; account: Account }
  | { userId: string; reloadKey: number; error: AppError }

// ติดตาม session ของ Supabase แล้วเรียก ensure_account() เพื่อรู้บทบาทจากฐานข้อมูล (TECHNICAL_DESIGN 3.1)
// บทบาทไม่อ่านจาก JWT หรือ user_metadata
export function AuthProvider({ children }: { children: ReactNode }) {
  // undefined = ยังไม่รู้ (กำลังอ่าน session ที่เก็บไว้)
  const [session, setSession] = useState<Session | null | undefined>(undefined)
  const [result, setResult] = useState<AccountResult | null>(null)
  const [notice, setNotice] = useState<string | undefined>()
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let active = true
    supabase.auth.getSession().then(({ data }) => {
      if (active) setSession(data.session)
    })
    // ห้ามเรียกคำสั่ง Supabase อื่นใน callback นี้ (คำแนะนำของ supabase-js) — แค่เก็บ session
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next))
    return () => {
      active = false
      data.subscription.unsubscribe()
    }
  }, [])

  const userId = session?.user.id

  // เรียกใหม่เมื่อเปลี่ยนผู้ใช้หรือสั่งโหลดใหม่เท่านั้น (ไม่ใช่ทุกครั้งที่ต่ออายุ token)
  useEffect(() => {
    if (!userId) return
    let active = true
    supabase.rpc('ensure_account').then(async ({ data, error }) => {
      if (!active) return
      if (error) {
        const appError = toAppError(error)
        if (appError.action === 'sign_out' || appError.action === 'relogin') {
          // provider_not_allowed: ออกจากระบบให้; not_authenticated: เซสชันใช้ไม่ได้แล้ว
          setNotice(appError.message)
          await supabase.auth.signOut({ scope: 'local' })
          return
        }
        setResult({ userId, reloadKey, error: appError })
        return
      }
      const parsed = AccountSchema.safeParse(data)
      if (parsed.success) {
        setNotice(undefined)
        setResult({ userId, reloadKey, account: parsed.data })
      } else {
        setResult({ userId, reloadKey, error: toAppError({ name: 'InvalidAccount' }) })
      }
    })
    return () => {
      active = false
    }
  }, [userId, reloadKey])

  const state = useMemo<AuthState>(() => {
    if (session === undefined) return { status: 'loading' }
    if (session === null) return { status: 'signed_out', notice }
    if (!result || result.userId !== session.user.id || result.reloadKey !== reloadKey) {
      return { status: 'loading' }
    }
    return 'account' in result
      ? { status: 'ready', session, account: result.account }
      : { status: 'error', session, error: result.error }
  }, [session, result, notice, reloadKey])

  const signOut = useCallback(async () => {
    setNotice(undefined)
    await supabase.auth.signOut({ scope: 'local' })
  }, [])

  const reloadAccount = useCallback(() => setReloadKey((k) => k + 1), [])

  const value = useMemo<AuthContextValue>(
    () => ({ state, signOut, reloadAccount }),
    [state, signOut, reloadAccount],
  )

  return <AuthContext value={value}>{children}</AuthContext>
}
