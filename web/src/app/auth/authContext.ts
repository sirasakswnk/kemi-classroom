import type { Session } from '@supabase/supabase-js'
import { createContext } from 'react'
import type { AppError } from '../../lib/supabase'
import type { Account } from './account'

export type AuthState =
  | { status: 'loading' }
  /** notice = ข้อความบน A01 เช่น “กรุณาเข้าสู่ระบบอีกครั้ง” */
  | { status: 'signed_out'; notice?: string }
  | { status: 'ready'; session: Session; account: Account }
  | { status: 'error'; session: Session; error: AppError }

export interface AuthContextValue {
  state: AuthState
  signOut: () => Promise<void>
  /** เรียก ensure_account() ใหม่ เช่นหลังได้ forbidden หรือกดลองอีกครั้ง */
  reloadAccount: () => void
}

export const AuthContext = createContext<AuthContextValue | null>(null)
