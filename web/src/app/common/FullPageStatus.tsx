import type { ReactNode } from 'react'
import { th } from '../../copy/th'
import { Card } from '../../ui'
import styles from './FullPageStatus.module.css'

// หน้าเต็มจอสำหรับสถานะรอโหลด/ข้อผิดพลาดของทั้งแอป
export function FullPageStatus({ children }: { children?: ReactNode }) {
  return (
    <main className={styles.page}>
      {children ?? (
        <p className={styles.loading} role="status">
          {th.common.loading}
        </p>
      )}
    </main>
  )
}

export function FullPageCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <FullPageStatus>
      <Card as="section" padding="lg" className={styles.card}>
        <h1 className={styles.title}>{title}</h1>
        {children}
      </Card>
    </FullPageStatus>
  )
}
