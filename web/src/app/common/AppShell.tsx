import { Outlet } from 'react-router'
import styles from './AppShell.module.css'
import { EnvBanner } from './EnvBanner'

// โครงของทุกหน้า: แถบระบบทดสอบ (ถ้ามี) แล้วตามด้วยเนื้อหาที่ยืดเต็มความสูงที่เหลือ
export function AppShell() {
  return (
    <div className={styles.shell}>
      <EnvBanner />
      <div className={styles.content}>
        <Outlet />
      </div>
    </div>
  )
}
