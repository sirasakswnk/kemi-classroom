import { RouterProvider } from 'react-router/dom'
import { ToastProvider } from '../ui'
import { AuthProvider } from './auth/AuthProvider'
import { router } from './router'

export default function App() {
  return (
    <ToastProvider>
      <AuthProvider>
        <RouterProvider router={router} />
      </AuthProvider>
    </ToastProvider>
  )
}
