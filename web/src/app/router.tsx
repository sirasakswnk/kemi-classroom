import { createBrowserRouter, Navigate, type RouteObject } from 'react-router'
import { AuthCallback } from './auth/AuthCallback'
import { LoginPage } from './auth/LoginPage'
import { RequireRole } from './auth/RequireRole'
import { AppShell } from './common/AppShell'
import { FullPageStatus } from './common/FullPageStatus'
import { StudentHome } from '../features/identity/StudentHome'
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
  {
    // ทุกหน้าอยู่ใต้ AppShell เพื่อให้แถบ “ระบบทดสอบ” ขึ้นทุกหน้า
    element: <AppShell />,
    children: [
      { path: '/login', element: <LoginPage /> },
      { path: '/auth/callback', element: <AuthCallback /> },
      {
        path: '/',
        element: (
          // ยังไม่ผูกชื่อ → A02 เลือกชื่อ (UX 4)
          <RequireRole roles={['student']}>
            <StudentHome />
          </RequireRole>
        ),
      },
      {
        // หน้าครู T01/T08/T09 (+ T10 ใน T08) — ครู หรือผู้ดูแลในโหมดผู้ดูแล (L6)
        path: '/t',
        lazy: async () => ({
          Component: (await import('../features/teacher/TeacherRoute')).default,
        }),
        hydrateFallbackElement: <FullPageStatus />,
        children: [
          {
            index: true,
            lazy: async () => ({
              Component: (await import('../features/teacher/pages')).TeacherOverview,
            }),
          },
          {
            path: 'classes/new',
            lazy: async () => ({
              Component: (await import('../features/teacher/pages')).CreateClassroom,
            }),
          },
          {
            path: 'classes/:id',
            lazy: async () => ({
              Component: (await import('../features/teacher/pages')).ClassroomPage,
            }),
          },
        ],
      },
      {
        path: '/admin',
        element: (
          <RequireRole roles={['admin']}>
            <RoleHome role="admin" />
          </RequireRole>
        ),
      },
      {
        // T05 นำเข้ารายชื่อจาก Excel [ข้อเสนอ เส้นทาง] — โหลดแยกจาก bundle หลัก
        path: '/t/roster/import',
        lazy: async () => ({
          Component: (await import('../features/roster/RosterImportRoute')).default,
        }),
        hydrateFallbackElement: <FullPageStatus />,
      },
      ...devRoutes,
      { path: '*', element: <Navigate to="/" replace /> },
    ],
  },
])
