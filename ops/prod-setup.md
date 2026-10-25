# ตั้งค่าระบบใช้จริง (P7-06, P7-05b, P7-08) — ขั้นตอนฝั่งผู้ใช้

ใช้กับ `kemi-prod` + bucket `kemi-files` · อ้างอิง TECHNICAL_BUILD_PLAN ส่วน 3, 7, 8 และส่วน 10 “แผนเปิดใช้เร็ว” ข้อ 5–7 · งานฝั่ง Claude (migration, deploy, seed, สคริปต์) ทำเมื่อผู้ใช้อนุญาตทีละขั้นตาม CLAUDE.md ส่วน 4

> **กติกาความลับ:** พิมพ์หรือวางค่าลับเองในหน้าเว็บของบริการหรือ terminal ของตัวเองเท่านั้น — **ห้ามวางในแชต** ห้ามเขียนลงไฟล์ใน repo
> ค่าลับในงานนี้: รหัสผ่านฐานข้อมูล prod, กุญแจ B2 ทุกตัว (รวมกุญแจหลัก), client secret ของ Google, secret key ของ Supabase (`sb_secret_…`), เนื้อไฟล์ `rclone.conf`, รหัส crypt + salt ชุดใหม่, Ping URL ของ Healthchecks
> ค่าที่**ไม่ใช่**ความลับ บอก Claude ในแชตได้: project ref, URL โปรเจกต์, publishable key (`sb_publishable_…`), host/user ของ Session pooler, ชื่อ bucket, keyID ของ B2 (ไม่ต้องบอกก็ได้)

**ลำดับ:** ข้อ 1–4 ทำได้ทุกเมื่อ (ยังไม่มีข้อมูลจริง) · ข้อ 5 สลับหน้าเว็บ ทำเมื่อ Claude แจ้งว่าฐานข้อมูล prod พร้อม · ข้อ 6 เผยแพร่ล็อกอิน ทำหลังหน้า `/privacy` ขึ้นจริง (P7-05b) · ข้อ 7–8 สำรอง ทำก่อนนำเข้ารายชื่อจริง — **ไม่ข้าม** เพราะแผนฟรีของ Supabase ไม่มีชุดสำรองให้กู้

## 1. โปรเจกต์ Supabase `kemi-prod`

1. https://supabase.com/dashboard → **New project** · Organization เดียวกับ `kemi-dev`
   - Name `kemi-prod` · Region **Southeast Asia (Singapore)** · Plan **Free** (ห้ามเลือกแผนเสียเงิน)
   - Database password: กด **Generate a password** → เก็บใน password manager ทันที (ใช้กับงานสำรองข้อ 8)
2. รอสร้างเสร็จ แล้วส่งค่าที่ไม่ใช่ความลับให้ Claude:
   - Project Settings → General → **Project ID** (ref)
   - Project Settings → API Keys → **Publishable key** (`sb_publishable_…`)
   - ปุ่ม **Connect** → **Session pooler** → host และ user (`postgres.<ref>`)
3. **Authentication → Sign In / Providers:**
   - **Email: ปิด** (prod ไม่มีบัญชีทดสอบแบบอีเมล — BUILD_PLAN ส่วน 9) · Phone: ปิด · **Allow anonymous sign-ins: ปิด**
   - Google: เปิดในข้อ 2.3
4. **Authentication → URL Configuration:**
   - Site URL `https://kemi-classroom.pages.dev`
   - Redirect URLs: `https://kemi-classroom.pages.dev/auth/callback` **อย่างเดียว** (ไม่ใส่ localhost หรือ `*.kemi-classroom.pages.dev` ของ preview)
5. **ห้ามปิด legacy API keys** (Project Settings → API Keys) — Edge Functions ยังใช้ `SUPABASE_SERVICE_ROLE_KEY` แบบ legacy (BUILD_PLAN ส่วน 3)
6. ส่วนขยาย `pg_cron`, `pg_net` ไม่ต้องเปิดเอง — migration เปิดให้ตอน Claude `db push` (ถ้าแจ้งว่าไม่มีให้ ค่อยเปิดที่ Database → Extensions)
7. แจ้ง Claude → Claude (ขออนุญาตก่อนทุกขั้น) push migration ทั้งหมด, deploy Edge Functions (`uploads`, `files`, `process-jobs`), ตั้งรหัสลับของ `process-jobs` (`ops/jobs/set-secret.mjs` ต้องเพิ่มโหมด prod ก่อน), seed — **ชื่อภาคเรียนแรกตามภาคเรียนจริง (ถามครู)**, allowlist อีเมลครู, `storage_settings.quota_bytes` = 9,500,000,000 แล้วผูก CLI กลับ `kemi-dev`

## 2. Google ล็อกอินของ prod

ใช้โปรเจกต์ Google Cloud เดิมที่มี OAuth client `kemi-dev`

1. https://console.cloud.google.com → เลือกโปรเจกต์นั้น → **Google Auth Platform → Clients → Create client**
   - Application type **Web application** · Name `kemi-prod`
   - Authorized redirect URIs: `https://<ref ของ kemi-prod>.supabase.co/auth/v1/callback`
   - Create → Client ID + Client secret แสดงขึ้น — เปิดค้างไว้
2. **Audience → Test users:** เพิ่มอีเมลที่จะลองบน prod ก่อนเผยแพร่ (ครู, ผู้พัฒนา) — แอปยังเป็น Testing จนถึงข้อ 6
3. Supabase `kemi-prod` → Authentication → Sign In / Providers → **Google** → Enable → วาง Client ID และ Client secret → Save

## 3. Backblaze B2: bucket `kemi-files`

1. **Caps & Alerts:** ตรวจว่าเพดานรายวันของ storage, download, Class B, Class C ยังเป็น **$0** (เพดานใช้ทั้งบัญชี ตั้งไว้ตั้งแต่ระยะ 0)
2. **Buckets → Create a Bucket:**
   - Bucket Unique Name `kemi-files` · Files in Bucket are: **Private** · Default Encryption: **Disable** (เหมือน `kemi-dev-files`) · Object Lock: **Disable**
   - Create
3. **ยังไม่สร้าง Application Key จากหน้าเว็บ** — หน้าเว็บสร้างได้แค่ Read and Write ที่มีสิทธิ์จัดการ bucket ติดมาด้วย (รั่วแล้วเปลี่ยน bucket เป็นสาธารณะหรือแก้ CORS ได้ — BUILD_PLAN ส่วน 7 ข้อ 5) จึงทำข้อ 4 ด้วยสคริปต์
4. **CORS + lifecycle + กุญแจสิทธิ์แคบ (สคริปต์ที่ Claude เตรียมในงาน P7-06 แบบเดียวกับ `ops/b2/apply-settings.mjs`):**
   - รันใน terminal ของตัวเอง ใส่ **Master Application Key** แบบซ่อนตัวอักษร (หน้า Application Keys → Master Application Key → Generate New Master Application Key ถ้าไม่มีค่าเดิม — การสร้างใหม่ทำให้ค่าเดิมใช้ไม่ได้ แต่ไม่กระทบกุญแจอื่น) — สคริปต์ใช้แค่ตั้งค่าและสร้างกุญแจ ไม่เก็บ ไม่พิมพ์กุญแจหลัก
   - สคริปต์ตั้ง CORS เฉพาะ `https://kemi-classroom.pages.dev` (ไม่มี preview/localhost) + lifecycle ของ `files/` และ `staging/` ตาม `ops/b2/lifecycle.json`
   - สร้างกุญแจ 2 ตัว เฉพาะ bucket `kemi-files`:
     - `kemi-edge` — `readFiles`, `writeFiles`, `deleteFiles` (+ `listFiles` สำหรับงานเทียบยอดพื้นที่) → ใช้ในข้อ 4
     - `kemi-backup-ro` — `readFiles` เฉพาะ prefix `files/` → ใช้ในข้อ 7
   - keyID/applicationKey แสดง **ใน terminal ของผู้ใช้ครั้งเดียว** — คัดลอกไปใส่ข้อ 4 และ 7 ทันที ไม่บันทึกลงไฟล์
5. พื้นที่ 10 GB และงบดาวน์โหลด 1 GB/วันใช้ร่วมกับ `kemi-dev-files` — อย่าใช้ `kemi-files` ลองไฟล์สมมติ

## 4. Supabase secrets ของ Edge Functions (`kemi-prod`)

Dashboard `kemi-prod` → **Edge Functions → Secrets** → Add new secret (หรือ Claude ให้คำสั่ง `npx supabase secrets set --project-ref <ref> …` แล้วผู้ใช้พิมพ์ค่าเอง):

| ชื่อ | ค่า |
| --- | --- |
| `B2_KEY_ID` | keyID ของ `kemi-edge` (ข้อ 3.4) |
| `B2_APP_KEY` | applicationKey ของ `kemi-edge` |
| `B2_BUCKET` | `kemi-files` |
| `B2_ENDPOINT` | `https://s3.eu-central-003.backblazeb2.com` |
| `WEB_ORIGINS` | `https://kemi-classroom.pages.dev` (production อย่างเดียว) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` มีให้อัตโนมัติ ไม่ต้องใส่ · รหัสลับที่ `pg_cron` ใช้เรียก `process-jobs` สคริปต์สุ่มและใส่เอง ผู้ใช้ไม่ต้องคัดลอก

## 5. Cloudflare Pages: สลับ Production ไป `kemi-prod`

ทำเมื่อ Claude แจ้งว่าฐานข้อมูล prod พร้อมแล้วเท่านั้น (ก่อนนั้นเว็บ production ยังชี้ `kemi-dev` และมีแถบ “ระบบทดสอบ”)

1. Cloudflare → Workers & Pages → `kemi-classroom` → **Settings → Variables and Secrets** → แท็บ **Production** เท่านั้น:
   - `VITE_SUPABASE_URL` = `https://<ref ของ kemi-prod>.supabase.co`
   - `VITE_SUPABASE_PUBLISHABLE_KEY` = publishable key ของ `kemi-prod`
   - เพิ่ม `VITE_DEPLOY_ENV` = `prod`
   - **แท็บ Preview ไม่แตะ** (ยังชี้ `kemi-dev` — ใช้สาธิต 3 หลังสลับแล้ว)
2. **Deployments → production ล่าสุด → Retry deployment** (ตัวแปรใหม่มีผลกับ build ใหม่เท่านั้น)
3. Supabase **`kemi-dev`** → Authentication → URL Configuration:
   - **ลบ** `https://kemi-classroom.pages.dev/auth/callback` ออกจาก Redirect URLs (เหลือ `http://localhost:5173/auth/callback` และ `https://*.kemi-classroom.pages.dev/auth/callback`)
   - Site URL เปลี่ยนเป็น `http://localhost:5173`
4. แจ้ง Claude → ตรวจว่า `https://kemi-classroom.pages.dev` ไม่มีแถบ “ระบบทดสอบ”, CSP `connect-src` ชี้ `kemi-prod` และล็อกอินบัญชีใน Test users ได้ (BUILD_PLAN 10 ระยะ 7 ตรวจรับข้อ 3)

## 6. เผยแพร่ล็อกอิน Google (P7-05b — หลังหน้าแรกและ `/privacy` ขึ้นบน production แล้ว)

1. Google Cloud (โปรเจกต์ของ OAuth client ล็อกอิน) → **Google Auth Platform → Branding:**
   - Application home page `https://kemi-classroom.pages.dev`
   - Application privacy policy link `https://kemi-classroom.pages.dev/privacy`
   - Authorized domains: `kemi-classroom.pages.dev` · ไม่ใส่โลโก้ (ใส่แล้วต้องส่งตรวจ) → Save
2. **Data Access:** มีเฉพาะ `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`
3. **Audience → Publish app → Confirm** → สถานะ **In production** (scope พื้นฐานไม่ต้องส่งตรวจ) — หลังจากนี้นักเรียนทุกคนล็อกอินได้โดยไม่ต้องอยู่ใน Test users
4. แจ้ง Claude → ลองล็อกอินด้วยบัญชีที่ไม่อยู่ใน Test users บน production

## 7. rclone: remote ชุดใหม่ของ prod (เครื่องผู้ใช้)

**ห้ามใช้ `gcrypt:` เดิมของ dev** — สำรอง dev กับ prod ต้องไม่ปนโฟลเดอร์ Drive เดียวกัน · ใช้บัญชี Google สำรองและ OAuth client `rclone` (Desktop) เดิมจาก `ops/backup-setup.md` ข้อ 2 ได้ (In production อยู่แล้ว)

1. ถ้ามี `rclone.conf` เดิมในเครื่อง (`rclone config file` บอกที่อยู่) ให้ย้ายไปเก็บที่อื่นก่อน — ชุด prod เป็นไฟล์ใหม่ทั้งไฟล์ ชื่อ remote ซ้ำกับของ dev ได้เพราะเป็นคนละไฟล์
2. `rclone config` → `n` — **remote `gdrive`**: Storage `drive` → client_id / client_secret ของ OAuth client `rclone` (ดูได้ที่ Google Cloud โปรเจกต์ `kemi-backup` → Clients) → scope **`drive.file`** → ล็อกอินบัญชีสำรอง (ทำแบบเดียวกับ backup-setup ข้อ 3.3)
3. `n` — **remote `gcrypt`**: Storage `crypt` → remote **`gdrive:kemi-backup-prod`** (โฟลเดอร์ใหม่ **ไม่ใช่** `kemi-backup`)
   - filename_encryption `standard` · directory_name_encryption `true`
   - password: `g` → `256` → `y` · password2 (salt): `g` → `256` → `y` — **รหัสชุดใหม่ ไม่ใช้ของ dev**
   - ⚠️ จดรหัส crypt + salt ของ prod ไว้สองที่แยกกัน (password manager + สำเนาออฟไลน์) และ**ติดป้ายว่า “prod”** — ทำหาย = สำรองของข้อมูลนักเรียนจริงเปิดไม่ได้ และ Claude ช่วยกู้ไม่ได้
   - จด**ค่าจริงที่ rclone แสดงตอนสุ่ม (ยาว 43 ตัว)** ไม่ใช่ค่าใน `rclone.conf` / `rclone config show` (ค่า obscured ยาว ~79 ตัว ใช้ได้เฉพาะกับ rclone ผ่านตัวแปรสภาพแวดล้อม — พบตอน P7-02a 25 ต.ค.) — ถ้าจดค่า obscured ไว้แล้ว ให้รัน `rclone reveal` ในเทอร์มินัลตัวเองแล้วจดค่าจริงเพิ่ม พร้อมป้ายบอกว่าแบบไหน
4. `n` — **remote `b2ro`**: Storage `b2` → account = keyID ของ `kemi-backup-ro` (ข้อ 3.4) → key = applicationKey → hard_delete `false` → advanced `n` → Keep `y` → `q`
   - ชื่อ remote ต้องเป็น `gdrive` / `gcrypt` / `b2ro` เหมือนของ dev — สคริปต์สำรองเรียกด้วยชื่อนี้
5. ตรวจ: `rclone mkdir gcrypt:` แล้ว `rclone lsd gdrive:` ต้องเห็น `kemi-backup-prod` (และ `kemi-backup` ของ dev ถ้ายังไม่ลบ)
6. **ทดสอบถอดรหัสจากสำเนาออฟไลน์ทันที ก่อนใส่ secret ข้อ 8** (กันกรณีสำเนาจดผิด — สำรองจะเปิดไม่ได้โดยไม่มีใครรู้จนวันที่ต้องกู้):
   - `rclone copyto <ไฟล์เล็กในเครื่อง เช่น test.txt> gcrypt:probe/test.txt` (เขียนไฟล์ทดสอบ 1 ไฟล์ลงโฟลเดอร์ prod ใหม่ซึ่งยังว่าง)
   - เปิด PowerShell **หน้าต่างใหม่** → ทำตาม `ops/restore-manual.md` ข้อ 1–3 แต่ให้ `RCLONE_CONFIG_GCRYPT_REMOTE` = `gdrive:kemi-backup-prod` และวางรหัส/salt **จากสำเนาออฟไลน์** (ถ้าจดค่าจริง 43 ตัว ให้แปลงก่อนด้วย `rclone obscure` ในหน้าต่างนั้น หรือใช้ `rclone config` แบบ “type in my own password”)
   - `rclone cat gcrypt:probe/test.txt` ต้องได้เนื้อไฟล์เดิม → ลบ config/ตัวแปรของหน้าต่างทดสอบ (restore-manual ข้อ 5) แล้วกลับหน้าต่างแรก `rclone purge gcrypt:probe`
   - ไม่ผ่าน = สำเนาไม่ตรง → แก้สำเนาจากค่าใน config ของหน้าต่างแรก (`rclone reveal`) แล้วทดสอบซ้ำ **ห้ามข้ามไปข้อ 8 จนกว่าจะผ่าน**

## 8. Healthchecks.io + GitHub Secrets ชุด prod

1. https://healthchecks.io → **Add Check** `kemi-backup-prod` · Simple · Period **12 hours** · Grace **6 hours** · เปิด Email ถึงผู้พัฒนา → คัดลอก **Ping URL**
2. Supabase `kemi-prod` → Project Settings → **API Keys → Secret keys → New secret key** ชื่อ `github_backup` → คัดลอก (`sb_secret_…`) — ใช้เรียก `ping()` กันโปรเจกต์หลับช่วงปิดเทอม
3. GitHub repo → **Settings → Secrets and variables → Actions → New repository secret** — ชื่อชุด prod แยกจากชุด dev (Claude ยืนยันชื่อสุดท้ายในงาน P7-08 ก่อนผู้ใช้ใส่ ชื่อด้านล่างเป็นข้อเสนอ):

| ชื่อ (ข้อเสนอ) | ค่า |
| --- | --- |
| `PROD_BACKUP_DB_PASSWORD` | รหัสผ่านฐานข้อมูล `kemi-prod` (ข้อ 1.1) |
| `PROD_RCLONE_CONFIG` | เนื้อไฟล์ `rclone.conf` ชุด prod ทั้งไฟล์ (`rclone config file` → เปิดด้วย Notepad คัดลอกทั้งหมด) |
| `PROD_HC_PING_URL` | Ping URL ของ `kemi-backup-prod` |
| `PROD_SUPABASE_PING_KEY` | secret key `github_backup` ของ `kemi-prod` |

4. หลังใส่ `PROD_RCLONE_CONFIG` แล้ว **ลบ `rclone.conf` ชุด prod ในเครื่อง** หรือย้ายไปเก็บในที่ปลอดภัย (มี token ของ Drive, กุญแจ B2 และรหัส crypt แบบถอดกลับได้)
5. แจ้ง Claude → Claude แก้ `backup.yml` / `ops/backup.sh` ให้ชี้ prod (ตัวกัน project ref และ bucket ของ prod), รันรอบแรกด้วยมือ → ผู้ใช้ดู `kemi-backup-prod` ใน Healthchecks เป็นสีเขียว → **หยุดสำรอง dev** และกด Pause ที่ check `kemi-backup` (เพราะใช้เพดานรายวันของ B2 ก้อนเดียวกับ prod)

## 9. หลังตั้งครบ

- Claude จดค่าที่ไม่ใช่ความลับของ prod (ref, URL, publishable key, host pooler) ใน “สถานะล่าสุด” ของ `PROGRESS.md`
- ตรวจรายการความปลอดภัย BUILD_PLAN ส่วน 11 ข้อที่อ้าง prod (P7-04) ก่อนนำเข้ารายชื่อจริง
- นำเข้ารายชื่อห้องนำร่องบน prod ได้หลังสาธิต 3 + go/no-go ผ่าน (แผนเปิดใช้เร็ว ข้อ 8–9)
