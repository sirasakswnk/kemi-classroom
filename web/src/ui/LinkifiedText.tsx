import { linkify } from '../lib/linkify'
import styles from './LinkifiedText.module.css'

export type LinkifiedTextProps = {
  text: string
}

/** ข้อความที่ผู้ใช้พิมพ์ โดย http(s):// กดเปิดในแท็บใหม่ได้ — ใส่ใน element ที่กำหนด white-space เอง */
export function LinkifiedText({ text }: LinkifiedTextProps) {
  return (
    <>
      {linkify(text).map((segment, i) =>
        segment.kind === 'link' ? (
          <a
            key={i}
            className={styles.link}
            href={segment.href}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            {segment.text}
          </a>
        ) : (
          segment.text
        ),
      )}
    </>
  )
}
