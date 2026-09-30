import { lazy, Suspense } from 'react'
import { th } from '../copy/th'
import { ToastProvider } from '../ui'

// หน้าแสดงคอมโพเนนต์เฉพาะโหมดพัฒนา — ไม่ถูกรวมใน build จริง
const DevGallery = import.meta.env.DEV ? lazy(() => import('./DevGallery')) : null

export default function App() {
  return (
    <ToastProvider>
      <h1 className="sr-only">{th.appName}</h1>
      {DevGallery && (
        <Suspense fallback={null}>
          <DevGallery />
        </Suspense>
      )}
    </ToastProvider>
  )
}
