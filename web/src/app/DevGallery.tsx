// ตัวอย่างคอมโพเนนต์สำหรับตรวจหน้าตาตอนพัฒนาเท่านั้น (ข้อความตัวอย่างไม่ใช่ข้อความจริงของระบบ)
import {
  ArrowRight,
  CalendarRange,
  CircleCheck,
  Clock,
  Coins,
  Plus,
  Sparkles,
  TriangleAlert,
  Upload,
} from 'lucide-react'
import { useState } from 'react'
import { Button, Card, Chip, Field, Input, Textarea } from '../ui'
import styles from './DevGallery.module.css'

export default function DevGallery() {
  const [name, setName] = useState('')

  return (
    <div className={styles.page}>
      <header className={styles.head}>
        <p className={styles.eyebrow}>DEV · คอมโพเนนต์พื้นฐาน</p>
        <h2 className={styles.title}>ห้องเคมี — ตัวอย่าง UI</h2>
      </header>

      <div className={styles.grid}>
        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Button</h3>
          <div className={styles.row}>
            <Button icon={<Plus />}>สร้างชั้นเรียน</Button>
            <Button variant="soft">ดูรายละเอียด</Button>
            <Button variant="ghost">ยกเลิก</Button>
          </div>
          <div className={styles.row}>
            <Button variant="gold" icon={<Sparkles />}>
              สุ่มเครื่องราง
            </Button>
            <Button variant="danger">ลบงาน</Button>
            <Button disabled>ส่งงาน</Button>
          </div>
          <div className={styles.row}>
            <Button size="sm" variant="soft">
              ขนาดเล็ก
            </Button>
            <Button size="sm" variant="ghost" icon={<ArrowRight />}>
              ถัดไป
            </Button>
          </div>
          <Button block icon={<Upload />}>
            ส่งงาน
          </Button>
        </Card>

        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Chip</h3>
          <div className={styles.row}>
            <Chip tone="green" icon={<CircleCheck />}>
              ส่งแล้ว
            </Chip>
            <Chip tone="amber" icon={<Clock />}>
              รอตรวจ
            </Chip>
            <Chip tone="red" icon={<TriangleAlert />}>
              ส่งช้า
            </Chip>
            <Chip tone="gold" icon={<Coins />}>
              +3 โทเคน
            </Chip>
            <Chip tone="purple" icon={<CalendarRange />}>
              ภาคเรียน 2/2569
            </Chip>
            <Chip tone="plain">ยังไม่ส่ง</Chip>
            <Chip tone="outline">ไม่บังคับ</Chip>
          </div>
        </Card>

        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Field</h3>
          <Field label="ชื่อชั้นเรียน" hint="แสดงให้นักเรียนเห็นในหน้าแรก">
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="เช่น เคมี ม.5/4"
              maxLength={60}
              autoComplete="off"
            />
          </Field>
          <Field label="รายละเอียด" optional>
            <Textarea placeholder="เช่น คาบวันจันทร์และพฤหัสบดี ห้อง 305" />
          </Field>
          <Field label="เปอร์เซ็นต์หัก" error="ใส่จำนวนเต็ม 0–100">
            <Input inputMode="numeric" defaultValue="120" />
          </Field>
          <Field label="ปิดใช้งาน">
            <Input disabled defaultValue="แก้ไม่ได้" />
          </Field>
        </Card>

        <Card as="section" padding="lg" raised className={styles.stack}>
          <h3 className={styles.h3}>Card</h3>
          <p>การ์ดยืดตามความกว้างของพื้นที่ ระยะในปรับตามความกว้างจอ</p>
          <Card>
            <p className={styles.muted}>การ์ดซ้อน padding md</p>
          </Card>
          <p className={styles.muted}>
            คะแนน <span className="num">7/10</span> · 23:59 น.
          </p>
        </Card>
      </div>
    </div>
  )
}
