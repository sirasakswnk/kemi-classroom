# เช็กลิสต์เปิดบัญชีบริการ (ระยะ 0) — ห้องเคมี

อัปเดต 30 ก.ย. 2026 · ชื่อเว็บ: **kemi-classroom** → `https://kemi-classroom.pages.dev` · อ้างอิง `TECHNICAL_BUILD_PLAN.md` ส่วน 3 และ 7, `SYSTEM_SPEC.md` ส่วน 12
ชื่อเมนูในหน้าเว็บของแต่ละบริการอาจต่างจากที่เขียนไว้เล็กน้อย ถ้าหาไม่เจอให้ค้นชื่อหัวข้อในหน้านั้น

## กฎร่วมทุกบริการ

- [ ] ใช้ตัวจัดการรหัสผ่าน (เช่น Bitwarden แผนฟรี) เก็บรหัสผ่าน รหัสฐานข้อมูล และ recovery codes ของทุกบัญชี
- เปิด **ยืนยันตัวตนสองขั้น (2FA)** ทุกบัญชี และเก็บ recovery codes
- **ห้ามใส่บัตรหรือเปิด billing** และห้ามกดทดลองใช้ฟรีแบบที่ต้องใส่บัตร (J10.4–J10.5) — ถ้าบริการไหนบังคับใส่บัตร ให้หยุดและกลับมาคุยก่อน
- **ห้ามส่งรหัสผ่าน key หรือ secret ให้ Claude** ส่งได้เฉพาะค่าในตาราง “ค่าที่แชร์ได้” ท้ายไฟล์

## ลำดับที่แนะนำ

| # | บริการ | ทำเมื่อ |
| --- | --- | --- |
| 1 | ตัวจัดการรหัสผ่าน | ตอนนี้ |
| 2 | GitHub repo | ตอนนี้ |
| 3 | Node.js + Git บนเครื่อง | ตอนนี้ (ก่อนเปิด Claude Code) |
| 4 | Google Cloud — หน้าขอสิทธิ์ล็อกอิน | ตอนนี้ (ส่วน OAuth client ทำหลังข้อ 5) |
| 5 | Supabase โปรเจกต์ `kemi-dev` | ตอนนี้ |
| 6 | Cloudflare (บัญชีเปล่า) | ตอนนี้ — สร้างโปรเจกต์ Pages ในงาน P1-09 |
| 7 | Backblaze B2 | หลังวัดความเร็วภูมิภาคด้วยสคริปต์งาน P0-01 เท่านั้น |
| 8 | บัญชี Google แยกสำหรับสำรอง | ก่อนงาน P3-11 |
| 9 | Healthchecks.io | ก่อนงาน P3-11 |
| 10 | Supabase โปรเจกต์ `kemi-prod` | ระยะ 7 (งาน P7-06) — ไม่สร้างตอนนี้ เพราะโปรเจกต์ฟรีที่ไม่มีคนใช้ 1 สัปดาห์จะถูกพักไว้ |

## 2. GitHub repo

- [ ] เปิด 2FA ของบัญชี GitHub
- [ ] สร้าง repo ใหม่ (ปุ่ม New repository):
  - Owner: บัญชีของคุณ
  - Repository name: `kemi-classroom`
  - Description: `ห้องเคมี — เว็บส่งการบ้านเคมี ตรวจงาน และสะสมเครื่องราง (React + Supabase + Cloudflare Pages + Backblaze B2)` — ไม่ใส่ชื่อโรงเรียนหรือข้อมูลนักเรียน
  - Visibility: **Private** (เหตุผล: repo สาธารณะถูกปิดงานตั้งเวลาสำรองอัตโนมัติเมื่อไม่มีความเคลื่อนไหว 60 วัน, ใช้ GitHub Actions ฟรี 2,000 นาที/เดือนแบบหยุดเมื่อครบ และไม่เปิดเผยโครงระบบ)
  - Initialize: **ไม่ติ๊ก Add a README, ไม่เลือก .gitignore, License = None** — ให้ repo ว่าง เพราะ Claude Code จะสร้าง git ในโฟลเดอร์ `D:\Vscode\Classroom` แล้ว push ขึ้นมา ถ้า repo มีไฟล์อยู่ก่อนจะชนกัน
- [ ] ตรวจหน้า Billing ของบัญชีว่า **ไม่มีวิธีชำระเงิน** (ทำให้ Actions หยุดเมื่อครบโควตาแทนการเก็บเงิน)
- [ ] (แนะนำ) Settings → Emails → เปิด “Keep my email addresses private” แล้วใช้อีเมลแบบ `…@users.noreply.github.com` เป็นอีเมลของ git เพื่อไม่ให้อีเมลจริงอยู่ในประวัติ commit
- จด: URL ของ repo → ตารางท้ายไฟล์
- การ push ครั้งแรกให้ Claude Code ทำหลังคุณอนุญาต ครั้งแรก Git จะเปิดหน้าเบราว์เซอร์ให้ล็อกอิน GitHub

## 3. Node.js + Git บนเครื่อง Windows

- [ ] ติดตั้ง Node.js **24 LTS** (ตัวติดตั้ง Windows จาก nodejs.org)
- [ ] ติดตั้ง Git for Windows (git-scm.com) ใช้ค่าเริ่มต้นได้
- [ ] เปิด terminal ใหม่ ตรวจ `node -v` และ `git --version`
- [ ] ตั้งชื่อ/อีเมลของ git: `git config --global user.name "…"` และ `git config --global user.email "…"` (ใช้อีเมล noreply จากข้อ 2 ได้)

## 4. Google Cloud — หน้าขอสิทธิ์ล็อกอินด้วย Google

ใช้บัญชี Google หลักของผู้พัฒนา (ไม่ต้องเป็นบัญชีสำรอง)

- [ ] เข้า console.cloud.google.com → สร้างโปรเจกต์ชื่อ `kemi-classroom` (ไม่ต้องมี organization)
- [ ] **ไม่กด Free trial / ไม่เปิด billing** — การสร้างหน้าขอสิทธิ์และ OAuth client ไม่ต้องใช้ billing
- [ ] ไปที่ Google Auth Platform (หรือ APIs & Services → OAuth consent screen):
  - App name: `ห้องเคมี` · User support email: อีเมลของคุณ · Developer contact: อีเมลของคุณ
  - Audience / User type: **External**
  - **ไม่อัปโหลดโลโก้** (ใส่โลโก้แล้วต้องรอ Google ตรวจสอบแอป)
  - Data access / Scopes: เลือกเฉพาะ `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`
  - Publishing status: **ระหว่างพัฒนาใช้ Testing ไปก่อน** แล้วเพิ่มบัญชีที่ใช้ทดสอบใน Audience → Test users (บัญชีผู้ดูแล บัญชีครู บัญชีนักเรียนทดสอบ และบัญชีโรงเรียนที่จะลอง ได้สูงสุด 100 บัญชี) — การกด Publish เป็น In production ต้องมี homepage URL และ privacy policy URL ซึ่งจะทำในงาน P7-06 (อัปเดต 30 ก.ย. 2026 หลังเจอข้อความของ Google)
  - Branding → Authorized domains: เพิ่ม `igchlnmxbghsigyziomk.supabase.co` (ตามคู่มือ Google login ของ Supabase) และภายหลังเพิ่ม `kemi-classroom.pages.dev`
- [ ] **หลังทำข้อ 5 แล้ว** สร้าง OAuth client: Clients → Create client → Application type **Web application** ชื่อ `kemi-dev`
  - Authorized redirect URIs: `https://<project-ref ของ kemi-dev>.supabase.co/auth/v1/callback` (ดูค่า callback ได้ในหน้าตั้งค่า Google ของ Supabase)
  - Authorized JavaScript origins (ใส่ไว้ได้): `https://kemi-classroom.pages.dev`, `http://localhost:5173`
  - คัดลอก Client ID และ Client secret ไปวางใน Supabase → Authentication → Sign In / Providers → Google ของโปรเจกต์ `kemi-dev` **ด้วยตัวเอง** (ไม่ส่งให้ Claude)
- จด: ชื่อโปรเจกต์ Google Cloud และ Client ID (ไม่ใช่ความลับ แต่ไม่จำเป็นต้องส่ง)

## 5. Supabase — โปรเจกต์ `kemi-dev`

- [ ] เข้า supabase.com → Sign in with GitHub
- [ ] สร้าง Organization: ชื่อ `kemi-classroom` · แผน **Free** · ไม่ใส่บัตร
- [ ] เปิด MFA ของบัญชี Supabase (Account → Security)
- [ ] New project:
  - Name: `kemi-dev`
  - Database password: กด Generate แล้ว **เก็บในตัวจัดการรหัสผ่าน** (ไม่ส่งให้ Claude)
  - Region: **Southeast Asia (Singapore)**
  - ตัวเลือกอื่นใช้ค่าเริ่มต้น
- [ ] หลังโปรเจกต์พร้อม จดค่า:
  - Project URL (`https://<ref>.supabase.co`) และ publishable/anon key — หน้า Project Settings → API Keys / Data API
  - รุ่น Postgres: SQL Editor รัน `select version();`
- [ ] Database → Extensions: ค้น `pg_cron` และ `pg_net` ว่ามีในรายการให้เปิดได้ไหม (ยังไม่ต้องเปิด) → ผลตรวจข้อ 2
- [ ] ยืนยันว่าไม่มีหน้าบังคับใส่บัตร → ผลตรวจข้อ 4
- การตั้งค่า Auth อื่น (ปิดอีเมล/รหัสผ่าน, Redirect URLs, rate limit) ทำพร้อม Claude Code ในงาน P1-07/P1-08

## 6. Cloudflare

- [ ] สมัครที่ dash.cloudflare.com ยืนยันอีเมล เปิด 2FA
- [ ] ไม่ต้องเพิ่มโดเมน และไม่ใส่วิธีชำระเงิน
- โปรเจกต์ Pages สร้างในงาน P1-09: Workers & Pages → Create → Pages → Connect to Git → เลือก repo `kemi-classroom` → ชื่อโปรเจกต์ `kemi-classroom`
  - ถ้าชื่อ `kemi-classroom.pages.dev` ถูกใช้ไปแล้ว Cloudflare จะต่อท้ายชื่อให้ ให้จดชื่อจริงที่ได้ เพราะต้องใช้ใน Redirect URLs และ CORS

## 7. Backblaze B2 (หลังงาน P0-01)

- [ ] รันสคริปต์วัดความเร็วจากงาน P0-01 ที่ Wi-Fi โรงเรียนและเน็ตมือถือ แล้วเลือกภูมิภาคที่เร็วสุด — **ภูมิภาคเลือกตอนสมัครและเปลี่ยนภายหลังไม่ได้**
- [ ] สมัคร B2 Cloud Storage เลือกภูมิภาคตามผลวัด ยืนยันอีเมล เปิด 2FA
- [ ] ผลตรวจข้อ 1: ต้องผูกบัตรหรือไม่ — **ถ้าบังคับใส่บัตร หยุดก่อนแล้วกลับมาคุย**
- [ ] หน้า Caps & Alerts: ตั้งเพดานรายวันของ storage, download, Class B และ Class C เป็น **$0** และเปิดอีเมลแจ้งเตือน
- bucket (`kemi-files`, `kemi-dev-files`), CORS, lifecycle และ application key ทำพร้อม Claude Code ในงาน P3-03 — ชื่อ bucket ต้องไม่ซ้ำกับใครทั้งระบบ ถ้าชื่อถูกใช้แล้วให้ต่อท้าย เช่น `kemi-classroom-files` แล้วจดไว้

## 8. บัญชี Google แยกสำหรับสำรอง (ก่อนงาน P3-11)

- [ ] สร้าง Gmail ใหม่สำหรับโปรเจกต์ (เช่น `kemi.classroom.backup@gmail.com` ถ้าว่าง) เปิด 2FA
- [ ] สร้างโฟลเดอร์ `kemi-backup` ใน Drive **ไม่แชร์ให้ใคร**
- โปรเจกต์ Google Cloud ของบัญชีนี้และ OAuth client ของ rclone ทำพร้อม Claude Code ในงาน P3-11

## 9. Healthchecks.io (ก่อนงาน P3-11)

- [ ] สมัครแผนฟรี เปิด 2FA
- check `kemi-backup` สร้างพร้อม Claude Code ในงาน P3-11

## 10. Supabase — โปรเจกต์ `kemi-prod` (ระยะ 7)

- ทำเหมือนข้อ 5 ด้วยชื่อ `kemi-prod` แล้วเพิ่ม OAuth client ของ prod (redirect URI ของ `kemi-prod`) ในข้อ 4

## ค่าที่แชร์ให้ Claude ได้ (กรอกเมื่อได้)

| รายการ | ค่า |
| --- | --- |
| URL ของ GitHub repo | |
| ชื่อเว็บจริงบน Pages | kemi-classroom.pages.dev (ยืนยันใน P1-09) |
| Supabase dev: Project URL | `https://igchlnmxbghsigyziomk.supabase.co` |
| Supabase dev: publishable/anon key | `sb_publishable_kpY6n1jpQSDKeqLBXZPAYQ_LY_pyyYR` |
| Postgres รุ่น | 17.6 |
| B2 ภูมิภาคและ S3 endpoint | |
| ชื่อ bucket จริง | |

**ไม่ส่ง:** รหัสผ่านทุกชนิด, Database password, service role / secret key, Google Client secret, B2 application key, recovery codes

## ผลตรวจตอนสมัคร 8 ข้อ (SYSTEM_SPEC ส่วน 12)

| ข้อ | เรื่อง | ผล | ตรวจเมื่อ |
| --- | --- | --- | --- |
| 1 | B2 ต้องผูกบัตรไหม / ตั้งเพดาน $0 ได้ | | ข้อ 7 |
| 2 | pg_cron (และ pg_net) ใช้ในแผนฟรีได้ | มีในรายการ Extensions ให้เปิดได้ (30 ก.ย. 2026) | ข้อ 5 |
| 3 | บัญชี Google ของโรงเรียนล็อกอินได้ | | หลังงาน P1-08 |
| 4 | Supabase ใช้ฟรีโดยไม่ผูกบัตร | สร้าง `kemi-dev` (Singapore, Postgres 17.6) แผน Free ได้ (30 ก.ย. 2026) | ข้อ 5 |
| 5 | Healthchecks.io ส่งอีเมลเตือนได้ | | งาน P3-11 |
| 6 | B2 lifecycle แยกตาม prefix ได้ | | งาน P3-03 |
| 7 | B2 CORS, ลายเซ็นขนาดไฟล์, CopyObject ระบุเวอร์ชัน, เพดานดาวน์โหลดเดือนแรก | | งาน P3-03–P3-04 |
| 8 | รุ่น Postgres, ต่อ Session pooler จาก Actions, pg_net, rate limit ล็อกอิน | | ข้อ 5 และงาน P1–P3 |
