import { createBrowserRouter, Navigate, type RouteObject } from 'react-router'
import { AuthCallback } from './auth/AuthCallback'
import { LoginPage } from './auth/LoginPage'
import { RequireRole } from './auth/RequireRole'
import { FullPageStatus } from './common/FullPageStatus'
import { RoleHome } from './home/RoleHome'

// เส้นทางระยะ 1 (TECHNICAL_BUILD_PLAN ส่วน 6) — หน้าแรกตามบทบาท: นักเรียน /, ครู /t, ผู้ดูแล /admin
const devRoutes: RouteObject[] = import.meta.env.DEV
  ? [
      {
        // หน้าแสดงคอมโพเนนต์ เฉพาะโหมดพัฒนา — ไม่อยู่ใน build จริง
        path: '/dev/ui',
        lazy: async () => ({ Component: (await import('./DevGallery')).default }),
        hydrateFallbackElement: <FullPageStatus />,
      },
    ]
  : []

export const router = createBrowserRouter([
  { path: '/login', element: <LoginPage /> },
  { path: '/auth/callback', element: <AuthCallback /> },
  {
    path: '/',
    element: (
      <RequireRole roles={['student']}>
        <RoleHome role="student" />
      </RequireRole>
    ),
  },
  {
    path: '/t',
    element: (
      <RequireRole roles={['teacher']}>
        <RoleHome role="teacher" />
      </RequireRole>
    ),
  },
  {
    path: '/admin',
    element: (
      <RequireRole roles={['admin']}>
        <RoleHome role="admin" />
      </RequireRole>
    ),
  },
  ...devRoutes,
  { path: '*', element: <Navigate to="/" replace /> },
])
