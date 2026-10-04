import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { ToastProvider } from '../ui'
import { AuthProvider } from './auth/AuthProvider'
import { QueryReset } from './auth/QueryReset'
import { router } from './router'

// ข้อมูลจากเซิร์ฟเวอร์ (TanStack Query): ไม่ทำ optimistic update กับโทเคน การสุ่ม และคะแนน (BUILD_PLAN 1)
const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000, retry: 1 } },
})

export default function App() {
  return (
    <ToastProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <QueryReset />
          <RouterProvider router={router} />
        </AuthProvider>
      </QueryClientProvider>
    </ToastProvider>
  )
}
