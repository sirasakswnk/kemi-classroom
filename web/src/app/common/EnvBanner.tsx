import { FlaskConical } from 'lucide-react'
import { th } from '../../copy/th'
import { isTestDeployment } from '../../lib/env'
import styles from './AppShell.module.css'

// แถบบนสุดของทุกหน้าในระบบทดสอบ — อยู่ในลำดับเนื้อหาปกติ (ไม่ลอยทับ) จึงไม่บังเนื้อหาหรือปุ่ม
export function EnvBanner({ deployEnv }: { deployEnv?: string }) {
  const show = deployEnv === undefined ? isTestDeployment() : isTestDeployment(deployEnv)
  if (!show) return null
  return (
    <p className={styles.banner} role="note">
      <FlaskConical aria-hidden="true" />
      <span>{th.env.testBanner}</span>
    </p>
  )
}
