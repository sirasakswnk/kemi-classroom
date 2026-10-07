# ตั้งค่าสำรองข้อมูล (P3-11) — ขั้นตอนฝั่งผู้ใช้

ใช้กับ `kemi-dev` + bucket `kemi-dev-files` เท่านั้นจนถึงระยะ 7 (`ops/backup.sh` กันไว้) · อ้างอิง TECHNICAL_BUILD_PLAN ส่วน 7–8, TECHNICAL_DESIGN ส่วน 12

> **กติกาความลับ:** พิมพ์หรือวางค่าลับเองในหน้าเว็บของบริการหรือ terminal ของตัวเองเท่านั้น — **ห้ามวางในแชต** ห้ามเขียนลงไฟล์ใน repo
> ค่าลับในงานนี้: client secret ของ Google, รหัส crypt + salt, กุญแจ B2, เนื้อไฟล์ `rclone.conf`, รหัสผ่านฐานข้อมูล, URL ping ของ Healthchecks, secret key ของ Supabase

## 1. Google Drive ของบัญชีสำรอง

1. ใช้บัญชี Google แยกของโปรเจกต์ (เปิดยืนยันสองขั้นแล้ว)
2. **ไม่ต้องสร้างโฟลเดอร์ `kemi-backup` เอง** — rclone ใช้สิทธิ์ `drive.file` ซึ่งเห็นเฉพาะไฟล์/โฟลเดอร์ที่ rclone สร้างเอง ถ้าสร้างไว้แล้วจากหน้าเว็บ Drive ให้ลบโฟลเดอร์ว่างนั้นทิ้ง (ไม่งั้นจะมีสองโฟลเดอร์ชื่อซ้ำกัน) — rclone จะสร้าง `kemi-backup` ให้ในข้อ 3.5 และไม่แชร์ให้ใคร

## 2. โปรเจกต์ Google Cloud + OAuth client ของ rclone (ล็อกอินด้วยบัญชีสำรอง)

1. https://console.cloud.google.com → เลือกโปรเจกต์ (มุมซ้ายบน) → **New project** ชื่อ `kemi-backup` → Create แล้วสลับไปโปรเจกต์นั้น
2. เมนู **APIs & Services → Library** → ค้น `Google Drive API` → **Enable**
3. เมนู **Google Auth Platform** (หรือ APIs & Services → OAuth consent screen) → **Get started**
   - App name `kemi-backup rclone`, User support email = อีเมลบัญชีสำรอง → Next
   - Audience: **External** → Next → Contact email = อีเมลบัญชีสำรอง → ยอมรับนโยบาย → Create
4. **Data Access → Add or remove scopes** → ติ๊กเฉพาะ `.../auth/drive.file` → Update → Save
5. **Branding** (ต้องกรอกก่อน — ตั้งแต่ปลาย ส.ค. 2026 Google ไม่ให้กด Publish app จนกว่าจะมี homepage + privacy policy URL; BUILD_PLAN ส่วน 7):
   - Application home page `https://kemi-classroom.pages.dev`
   - Application privacy policy link `https://kemi-classroom.pages.dev/privacy` (หน้าจริงสร้างใน P7-06)
   - Authorized domains → Add domain `kemi-classroom.pages.dev`
   - Developer contact information = อีเมลบัญชีสำรอง
   - **ไม่ใส่โลโก้** (ใส่แล้วต้องส่งตรวจ) → Save

   แล้ว **Audience → Publish app → Confirm** ให้สถานะเป็น **In production** (โหมด Testing ทำให้ token หมดอายุใน 7 วัน — BUILD_PLAN 13 ข้อ 14) — `drive.file` ไม่ต้องส่งตรวจ (verification)
6. **Clients → Create client** → Application type **Desktop app** → ชื่อ `rclone` → Create
   - หน้าต่างจะแสดง Client ID และ Client secret — เปิดค้างไว้เพื่อคัดลอกไปวางใน `rclone config` ข้อ 3.2 (ไม่ต้องเก็บที่อื่น)

## 3. กุญแจ B2 แบบอ่านอย่างเดียว + `rclone config` บนเครื่องผู้ใช้

1. **กุญแจ B2 ใหม่:** เว็บ Backblaze → **Application Keys → Add a New Application Key**
   - Name `kemi-backup-ro-dev` · Allow access to Bucket(s): **`kemi-dev-files`** · Type of Access: **Read Only** · File name prefix: `files/` · ไม่ติ๊ก List All Bucket Names · Duration ว่าง
   - กด Create แล้ว **keyID กับ applicationKey แสดงครั้งเดียว** — เปิดค้างไว้เพื่อวางใน `rclone config` ข้อ 3.4
2. ติดตั้ง rclone (PowerShell): `winget install Rclone.Rclone` แล้วเปิด PowerShell ใหม่ ตรวจด้วย `rclone version`
   - **ห้ามตั้งรหัสผ่านให้ไฟล์ config** (ข้อ `s) Set configuration password`) — สคริปต์บน GitHub เปิดไม่ได้; ไฟล์ทั้งไฟล์ถูกเก็บเป็น GitHub secret แทน
3. `rclone config` → `n` (New remote) — **remote ที่ 1 `gdrive`**
   - name `gdrive` → Storage: `drive` → client_id: วาง Client ID → client_secret: วาง Client secret
   - scope: เลือกข้อ **`drive.file`** → service_account_file: Enter (ว่าง) → Edit advanced config: `n`
   - Use web browser to automatically authenticate: `y` → เบราว์เซอร์เปิด → **ล็อกอินด้วยบัญชีสำรอง** → Allow (ถ้าขึ้น “Google hasn’t verified this app” ให้กด Advanced → Go to kemi-backup rclone)
   - Configure this as a Shared Drive: `n` → Keep this remote: `y`
4. `n` อีกครั้ง — **remote ที่ 2 `gcrypt`** (เข้ารหัสทั้งชื่อไฟล์และเนื้อหา)
   - name `gcrypt` → Storage: `crypt` → remote: `gdrive:kemi-backup`
   - filename_encryption: `standard` → directory_name_encryption: `true`
   - password: `g` (ให้ rclone สุ่ม) → ความยาว `256` → `y` ใช้ค่านี้ — **จดรหัสที่แสดงทันที**
   - password2 (salt): `g` → `256` → `y` — **จดเช่นกัน**
   - Edit advanced config: `n` → Keep: `y`
   - ⚠️ **จดรหัส crypt และ salt ไว้สองที่แยกกัน** (เช่น password manager + กระดาษ/USB เก็บในที่ปลอดภัย) — **ทำหาย = ไฟล์สำรองทั้งหมดเปิดไม่ได้** และ Claude ช่วยกู้ไม่ได้
5. `n` อีกครั้ง — **remote ที่ 3 `b2ro`**
   - name `b2ro` → Storage: `b2` → account: วาง keyID → key: วาง applicationKey → hard_delete: `false` (Enter) → advanced: `n` → Keep: `y`
   - กด `q` ออกจาก `rclone config`
6. ตรวจ (ใช้แค่ Drive ไม่ใช้คำขอ B2):
   - `rclone mkdir gcrypt:` → สร้างโฟลเดอร์ `kemi-backup` ใน Drive บัญชีสำรอง
   - `rclone lsd gdrive:` → ต้องเห็น `kemi-backup` (ใน Drive ชื่อข้างในจะเป็นตัวอักษรสุ่มเพราะเข้ารหัส)
   - ถ้าจดรหัส crypt ไม่ทัน: `rclone config show gcrypt` แล้ว `rclone reveal <ค่า password>` / `rclone reveal <ค่า password2>` พิมพ์ค่าจริงใน terminal ของตัวเองเพื่อจด (อย่าคัดลอกมาในแชต)

## 4. Healthchecks.io

1. https://healthchecks.io → **Add Check** → Name `kemi-backup`
2. Schedule: **Simple** · Period **12 hours** · Grace Time **3 hours** → Save
3. Integrations: ให้เปิดช่องทาง **Email** ถึงอีเมลผู้พัฒนาไว้ (มีให้ตั้งแต่สมัคร)
4. คัดลอก **Ping URL** (`https://hc-ping.com/...`) ไปใส่ GitHub secret ในข้อ 6 — URL นี้เป็นความลับ (ใครมี URL ก็ส่งสัญญาณแทนได้)

## 5. ค่าจาก Supabase (kemi-dev)

1. **รหัสผ่านฐานข้อมูล:** ใช้รหัสที่ตั้งตอนสร้างโปรเจกต์ ถ้าจำไม่ได้ → Dashboard → Project Settings → Database → **Reset database password** (หน้าเว็บ/Edge Function ไม่ใช้รหัสนี้ และ CLI ใช้ login role ชั่วคราว จึงไม่กระทบระบบ)
2. **ตรวจ host ของ Session pooler:** Dashboard → ปุ่ม **Connect** → Session pooler → host ต้องเป็น `aws-0-ap-southeast-1.pooler.supabase.com` และ user `postgres.igchlnmxbghsigyziomk` (ตามที่ใส่ใน `backup.yml`) — ถ้าไม่ตรงให้บอก Claude (host/user ไม่ใช่ความลับ บอกในแชตได้)
3. **secret key สำหรับ `ping()` (ไม่บังคับ แต่แนะนำ):** Project Settings → **API Keys → Secret keys → New secret key** ชื่อ `github_backup` (ช่องชื่อรับเฉพาะตัวพิมพ์เล็ก ตัวเลข และ `_`) → คัดลอกค่า (`sb_secret_...`) — ใช้เรียก `public.ping()` ผ่าน Data API ทุกรอบเพื่อกันโปรเจกต์หลับ (BUILD_PLAN ส่วน 8 ข้อ 9); ลบ/เปลี่ยนแยกจาก key อื่นได้

## 6. GitHub Secrets (หน้าเว็บ)

repo → **Settings → Secrets and variables → Actions → New repository secret** — ใส่ 4 ตัว ชื่อต้องตรงตัวพิมพ์:

| ชื่อ | ค่า |
| --- | --- |
| `BACKUP_DB_PASSWORD` | รหัสผ่านฐานข้อมูลจากข้อ 5.1 |
| `RCLONE_CONFIG` | เนื้อไฟล์ `rclone.conf` ทั้งไฟล์ — หาที่อยู่ไฟล์ด้วย `rclone config file` แล้วเปิดด้วย Notepad คัดลอกทั้งหมด |
| `HC_PING_URL` | Ping URL จากข้อ 4.4 |
| `SUPABASE_PING_KEY` | secret key จากข้อ 5.3 (ไม่ใส่ก็ได้ — รอบสำรองยังทำงาน แต่ขึ้นคำเตือนว่าไม่ได้เรียก `ping()`) |

หลังใส่ `RCLONE_CONFIG` แล้ว **ลบ `rclone.conf` ในเครื่อง หรือย้ายไปเก็บในที่ปลอดภัย** — ไฟล์นี้มี token ของ Drive, กุญแจ B2 และรหัส crypt แบบถอดกลับได้ (`rclone reveal`); ถ้าต้องใช้ rclone ภายหลังสร้าง config ใหม่ได้ด้วยรหัส crypt + salt ที่จดไว้

## 7. แจ้ง Claude ว่าตั้งครบแล้ว

Claude จะรัน workflow `backup` ด้วยมือกับ kemi-dev: รอบปกติ 2 รอบ (รอบสองต้องไม่คัดลอกไฟล์เดิมซ้ำ) และรอบล้มโดยตั้งใจ 1 รอบ (`simulate_failure`) — **ผู้ใช้ตรวจกล่องอีเมลว่าได้อีเมลจาก Healthchecks.io** ว่า `kemi-backup` เป็น DOWN (พิสูจน์ BUILD_PLAN 13 ข้อ 5) แล้วรอบปกติถัดไปจะส่งอีเมลว่ากลับมา UP

ตารางเวลา (02:30 / 14:30 น.) เริ่มทำงานเองหลัง merge `phase-3` เข้า `main` เท่านั้น — ก่อนหน้านั้น Healthchecks จะเตือนว่าไม่มีสัญญาณทุก ~15 ชม. หลังรอบที่รันด้วยมือ ถ้าไม่อยากได้อีเมลช่วงนี้ให้กด **Pause** ที่ check หลังทดสอบเสร็จ (รอบถัดไปที่ ping จะเปิดเอง)
