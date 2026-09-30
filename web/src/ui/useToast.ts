import { useContext } from 'react'
import { ToastContext, type ShowToast } from './toastContext'

export function useToast(): ShowToast {
  const show = useContext(ToastContext)
  if (!show) throw new Error('useToast ต้องอยู่ใต้ <ToastProvider>')
  return show
}
