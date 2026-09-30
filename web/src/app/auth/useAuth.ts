import { useContext } from 'react'
import { AuthContext, type AuthContextValue } from './authContext'

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth ต้องอยู่ใต้ <AuthProvider>')
  return value
}
