import { lazy, Suspense } from 'react'
import { th } from '../copy/th'

// หน้าแสดงคอมโพเนนต์เฉพาะโหมดพัฒนา — ไม่ถูกรวมใน build จริง (P1-04 ขยายต่อ)
const DevGallery = import.meta.env.DEV ? lazy(() => import('./DevGallery')) : null

export default function App() {
  return (
    <>
      <h1 className="sr-only">{th.appName}</h1>
      {DevGallery && (
        <Suspense fallback={null}>
          <DevGallery />
        </Suspense>
      )}
    </>
  )
}
