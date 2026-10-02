import { z } from 'zod'

// CSP ของเว็บห้าม eval (script-src 'self'): ปิดตัวเร่งแบบ JIT ของ zod
// ไม่งั้น zod จะลองเรียก Function('') ทุกครั้งที่เปิดหน้า ซึ่งถูกบล็อกและขึ้นรายงาน CSP violation
// ทุกไฟล์ในเว็บ import z จากไฟล์นี้ ไม่ import จาก 'zod' ตรง ๆ
z.config({ jitless: true })

export { z }
