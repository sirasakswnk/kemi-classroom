import { Link } from 'react-router'
import { th } from '../../copy/th'
import { BrandLogo } from '../common/brand'
import styles from './PrivacyPage.module.css'

// /privacy นโยบายความเป็นส่วนตัว (P7-05b) — หน้าสาธารณะ ไม่ต้องล็อกอิน
// Google ใช้เป็น privacy policy URL ของแอปล็อกอินและแอป rclone (โดเมน kemi-classroom.pages.dev)
export function PrivacyPage() {
  const p = th.privacy
  return (
    <div className={styles.page}>
      <header className={styles.head}>
        <BrandLogo className={styles.logo} />
        <p className={styles.app}>{th.appName}</p>
        <h1>{p.title}</h1>
        <p className={styles.updated}>{p.updated}</p>
      </header>
      <main className={styles.body}>
        <p className={styles.intro}>{p.intro}</p>
        {p.sections.map((s) => (
          <section key={s.heading} className={styles.section}>
            <h2>{s.heading}</h2>
            <ul>
              {s.items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </section>
        ))}
        <Link to="/login" className={styles.back}>
          {p.back}
        </Link>
      </main>
    </div>
  )
}
