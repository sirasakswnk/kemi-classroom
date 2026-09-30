// ตัวอย่างคอมโพเนนต์สำหรับตรวจหน้าตาตอนพัฒนาเท่านั้น (ข้อความตัวอย่างไม่ใช่ข้อความจริงของระบบ)
import {
  ArrowRight,
  CalendarClock,
  CalendarRange,
  CircleCheck,
  Clock,
  Coins,
  Hourglass,
  ListChecks,
  Plus,
  Sparkles,
  TriangleAlert,
  Upload,
} from 'lucide-react'
import { useState } from 'react'
import {
  Button,
  Card,
  Chip,
  Field,
  Input,
  Modal,
  Sheet,
  Stepper,
  Steps,
  Textarea,
  useToast,
} from '../ui'
import styles from './DevGallery.module.css'

export default function DevGallery() {
  const [name, setName] = useState('')
  const [reward, setReward] = useState(3)
  const [delta, setDelta] = useState(0)
  const [dialog, setDialog] = useState<'none' | 'sheet' | 'pick' | 'modal'>('none')
  const close = () => setDialog('none')
  const toast = useToast()
  const balance = 5

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

        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Stepper</h3>
          <div className={styles.between}>
            <span>โทเคนรางวัล (0–10)</span>
            <Stepper label="โทเคน" value={reward} onChange={setReward} min={0} max={10} />
          </div>
          <div className={styles.between}>
            <span>
              ปรับยอด (มีอยู่ <span className="num">{balance}</span>)
            </span>
            <Stepper
              label="โทเคน"
              value={delta}
              onChange={setDelta}
              min={-balance}
              max={20}
              format={(v) => (v > 0 ? `+${v}` : String(v))}
            />
          </div>
          <div className={styles.between}>
            <span>ปิดใช้งาน</span>
            <Stepper label="โทเคน" value={2} onChange={() => {}} disabled />
          </div>
        </Card>

        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Steps</h3>
          <Steps
            label="ขั้นตอนของงานนี้"
            steps={[
              { label: 'ส่งงาน', state: 'done' },
              { label: 'ครูตรวจ', state: 'now', icon: <Hourglass /> },
              { label: 'งานครบถ้วน', state: 'todo', icon: <ListChecks /> },
              { label: 'ได้โทเคน', state: 'todo', icon: <Sparkles /> },
            ]}
          />
          <Steps
            label="ขั้นตอนของงานนี้ (ตรวจแล้ว)"
            steps={[
              { label: 'ส่งงาน', state: 'done' },
              { label: 'ครูตรวจ', state: 'done' },
              { label: 'งานครบถ้วน', state: 'done' },
              { label: 'ได้โทเคน', state: 'done', gold: true },
            ]}
          />
          <Steps
            label="ขั้นตอนนำเข้า"
            steps={[
              { label: 'เลือกไฟล์', state: 'done' },
              { label: 'จับคู่คอลัมน์', state: 'done' },
              { label: 'ตรวจรายการ', state: 'now', icon: <ListChecks /> },
              { label: 'ยืนยันนำเข้า', state: 'todo', icon: <Upload /> },
            ]}
          />
          <Steps
            label="ขั้นตอนของงานนี้ (ไม่ได้รางวัล)"
            steps={[
              { label: 'ส่งงาน', state: 'done' },
              { label: 'ครูตรวจ', state: 'done' },
              { label: 'งานครบถ้วน', state: 'done' },
              { label: 'ได้โทเคน', state: 'skip' },
            ]}
          />
        </Card>

        <Card as="section" className={styles.stack}>
          <h3 className={styles.h3}>Sheet · Modal · Toast</h3>
          <div className={styles.row}>
            <Button variant="soft" onClick={() => setDialog('sheet')}>
              เปิด Sheet
            </Button>
            <Button variant="soft" onClick={() => setDialog('pick')}>
              เปิด Sheet ปิดเองไม่ได้ (A02)
            </Button>
            <Button variant="soft" onClick={() => setDialog('modal')}>
              เปิด Modal
            </Button>
            <Button variant="ghost" onClick={() => toast('บันทึกแล้ว')}>
              แสดง Toast
            </Button>
          </div>
          <p className={styles.muted}>Toast ใช้แจ้งผลสำเร็จเท่านั้น ข้อผิดพลาดแสดงใกล้จุดที่เกิด</p>
        </Card>
      </div>

      <Sheet
        open={dialog === 'sheet'}
        onClose={close}
        title="ได้รับเครื่องราง!"
        description="เครื่องรางชิ้นนี้ถูกเก็บเข้าตู้สะสมของคุณแล้ว"
      >
        <Button block onClick={close}>
          เก็บเข้าตู้
        </Button>
      </Sheet>

      <Sheet
        open={dialog === 'pick'}
        onClose={close}
        dismissible={false}
        align="start"
        title="เลือกชื่อของคุณ"
        description="ค้นด้วยเลขประจำตัวเต็ม หรือชื่อ-นามสกุลเต็ม"
      >
        <Field label="เลขประจำตัวหรือชื่อ-นามสกุล">
          <Input placeholder="เช่น 04863" autoComplete="off" />
        </Field>
        <Button
          block
          onClick={() => {
            close()
            toast('เชื่อมบัญชีเรียบร้อย')
          }}
        >
          ยืนยันว่าเป็นฉัน
        </Button>
      </Sheet>

      <Modal
        open={dialog === 'modal'}
        onClose={close}
        icon={<CalendarClock />}
        title="เปลี่ยนกำหนดส่ง"
        description="งานนี้มีนักเรียนส่งแล้ว 12 คน"
        footer={
          <>
            <Button variant="ghost" onClick={close}>
              ยกเลิก
            </Button>
            <Button
              onClick={() => {
                close()
                toast('บันทึกแล้ว')
              }}
            >
              บันทึก
            </Button>
          </>
        }
      >
        <Field label="กำหนดส่งใหม่">
          <Input type="date" defaultValue="2026-10-07" />
        </Field>
      </Modal>
    </div>
  )
}
