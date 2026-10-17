# แผนสร้างและพัฒนาระบบเชิงเทคนิค — ห้องเคมี

อัปเดต 30 กันยายน 2026 · คู่กับ `DEVELOPMENT_PLAN.md` (ภาพรวม) · กติกายึด `SYSTEM_SPEC.md` แบบระบบยึด `TECHNICAL_DESIGN.md` หน้าจอยึด `UX_DESIGN.md` และ `exports/chemistry-design-v2.html`
สถานะ: แผนสำหรับลงมือ ยังไม่มีโค้ดหรือบัญชีบริการจริง ชื่อไฟล์ ชื่อฟังก์ชัน และไลบรารีเป็นข้อเสนอที่ปรับได้โดยไม่ต้องถามผู้ใช้ ยกเว้นเรื่องที่กระทบกติกาในเอกสารหลัก
ป้าย **[ข้อเสนอ]** = ทางเลือกทางเทคนิคที่แนะนำ · **[ต้องพิสูจน์]** = ต้องทดสอบกับบริการจริงก่อนเชื่อ (รวมไว้ในส่วน 13)

## 1. เครื่องมือและไลบรารี

| ส่วน | ใช้ | หมายเหตุ |
| --- | --- | --- |
| ภาษาและ build | TypeScript (strict) + Vite + React (ยืนยัน L1) | Node.js LTS ปัจจุบัน (24.x) และ npm; ตั้ง `build.target` ให้รองรับ Safari 15 ขึ้นไป **[ข้อเสนอ]** ตามรุ่นเบราว์เซอร์ใน DEVELOPMENT_PLAN ส่วน 7 |
| เส้นทางหน้า | React Router | หน้าเดียว (SPA) Cloudflare Pages ส่งทุกเส้นทางไป `index.html` เองเมื่อไม่มี `404.html` |
| ข้อมูลจากเซิร์ฟเวอร์ | `@supabase/supabase-js` v2 + TanStack Query | ไม่ทำ optimistic update กับโทเคน การสุ่ม และคะแนน แสดงผลจากเซิร์ฟเวอร์เท่านั้น |
| ตรวจรูปแบบข้อมูล | zod | ใช้ทั้งหน้าเว็บและ Edge Function |
| หน้าตา | CSS ธรรมดา + CSS variables ย้ายจาก `style.css` ของแบบ v2, CSS Modules รายคอมโพเนนต์, `lucide-react` | ไม่ใช้ UI framework เพื่อให้ตรงแบบ |
| ฟอนต์ | Anuphan และ Mitr ผ่าน `@fontsource` | โฮสต์เอง ไม่เรียก Google Fonts ตอนใช้งาน (เร็วขึ้นและไม่ส่งข้อมูลผู้ใช้ออก); Mali ใช้เฉพาะภาพตัวอย่างในแบบ ไม่ใช้ในระบบจริง (UX_DESIGN ส่วน 13) |
| รูปภาพ | `createImageBitmap` (หมุนตาม EXIF) + canvas ย่อทีละครึ่ง เริ่มด้านยาว 2560 px จนไม่เกิน 2 MB; JPEG/HEIC เข้ารหัสใหม่เป็น JPEG เสมอเพื่อตัด EXIF/GPS, PNG ที่ไม่เกินเพดานคงเดิม; ตัวถอด HEIC = `libheif-js` (LGPL-3.0) เป็นไฟล์ worker แยก same-origin (3.17 MB, gzip 776 KB) โหลดเมื่อพบ HEIC ที่เบราว์เซอร์ถอดเองไม่ได้เท่านั้น — ไม่ใช้ `heic2any`/`heic-to` เพราะสร้าง worker จาก `blob:` ซึ่ง CSP บล็อก (P3-06a) | ไฟล์แจ้งสัญญาอนุญาต `third-party-licenses.txt` สร้างตอน build (25 แพ็กเกจ ข้อความเต็ม รวม LGPL-3.0 ของ libheif-js + แหล่งซอร์ส; P3-06a) — ต้องมีลิงก์จากหน้าเว็บ (UX_DESIGN ส่วน 9) |
| PDF | `pdfjs-dist` แสดงในหน้าตรวจ, `pdf-lib` รวมเป็นไฟล์ดาวน์โหลด | ส่วน 9 ของ TECHNICAL_DESIGN |
| ZIP | `client-zip` แบบ stream + File System Access API บนคอมพิวเตอร์ | ถ้าเบราว์เซอร์ไม่รองรับ แบ่ง ZIP ตามห้อง/งาน **[ข้อเสนอ]** |
| อ่าน Excel | ไลบรารีอ่าน .xlsx ฝั่งเบราว์เซอร์ เช่น SheetJS (ติดตั้งจากแหล่งทางการของ SheetJS เพราะรุ่นบน npm ไม่อัปเดต) | อ่านเลขประจำตัวเป็นข้อความเสมอ |
| Edge Functions | Deno บน Supabase + `aws4fetch` ลงลายเซ็น S3 ของ B2 | TECHNICAL_DESIGN ส่วน 9.2 ข้อ 3 |
| ฐานข้อมูล | Supabase CLI (migration, deploy function, สร้าง type TS) | `supabase gen types typescript` หลังทุก migration |
| ทดสอบ | Vitest (หน่วย), pgTAP (ฐานข้อมูล/สิทธิ์), Playwright (หน้าเว็บ) | ส่วน 9 |
| คุณภาพโค้ด | ESLint + Prettier | รันใน CI |

## 2. โครง repo

repo เดียวแบบ private บน GitHub โดยใช้โฟลเดอร์โปรเจกต์ `D:\Vscode\Classroom` เป็น root (ชื่อ repo บน GitHub **[ข้อเสนอ]** `kemi-classroom`) เอกสาร 5 ฉบับ `CLAUDE.md` และ `PROGRESS.md` อยู่ที่ root; วิธีทำงานทีละขั้นกับ Claude Code อยู่ใน `CLAUDE.md`

```text
Classroom/                     # root ของ repo
  CLAUDE.md  PROGRESS.md       # วิธีทำงานทีละขั้น และบันทึกงาน
  SYSTEM_SPEC.md  TECHNICAL_DESIGN.md  UX_DESIGN.md  DEVELOPMENT_PLAN.md  TECHNICAL_BUILD_PLAN.md
  exports/                     # แบบหน้าจอ (อ้างอิงเฉพาะ chemistry-design-v2.html)
  web/                         # หน้าเว็บ React + TS (Cloudflare Pages root)
    public/_headers            # CSP และ security headers
    src/
      app/                     # router, providers, layout ตามบทบาท, แถบโหมดผู้ดูแล
      ui/                      # Button, Chip, Card, Sheet, Modal, Toast, Field, Stepper ตามแบบ v2
      styles/tokens.css        # สี/ฟอนต์/ระยะจากแบบ v2
      lib/
        supabase.ts            # client + ตัวแปลงรหัสข้อผิดพลาดเป็นข้อความไทย
        time.ts                # แสดงเวลาไทย (Asia/Bangkok) จากค่า UTC
        score.ts               # สูตรคะแนนสำหรับแสดงตัวอย่างเท่านั้น (ต้นฉบับอยู่ในฐานข้อมูล)
        mask.ts                # ชื่อปิดบางส่วนด้วย Intl.Segmenter
        upload/                # ตรวจไฟล์ แปลง HEIC ย่อรูป อัปโหลด PUT พร้อมความคืบหน้า
        pdf/ zip/ csv/         # รวม PDF, ZIP ภาคเรียน, CSV คะแนน (UTF-8 BOM)
      features/                # auth, onboarding, classes, posts, submit, grading, gradebook,
                               # rewards, collection, notifications, terms, roster, charms, admin, storage
  supabase/
    migrations/                # ไฟล์ SQL เรียงตามเวลา (ส่วน 4)
    functions/
      uploads/                 # create batch, complete
      files/                   # sign GET, ไฟล์ของการส่ง, รายการส่งออก
      process-jobs/            # งานเบื้องหลัง
      _shared/                 # b2.ts (aws4fetch), http.ts (CORS/คำตอบ/ข้อผิดพลาด), rpc.ts (เรียก RPC ด้วย JWT ของผู้ใช้)
    tests/                     # pgTAP *.test.sql
    seed.sql                   # ระดับ 60/25/10/5, เครื่องราง 12 ชิ้น, ค่าพื้นที่, ข้อมูลทดสอบ (เฉพาะ dev)
  ops/
    backup.sh  restore-test.sh  manifest.sql  b2/cors.json  b2/lifecycle.json
  tests/e2e/                   # Playwright
  .github/workflows/           # ci.yml, deploy-db.yml, backup.yml, restore-test.yml
```

แบบ HTML v2 ใช้เป็นต้นแบบหน้าตาและข้อความเท่านั้น ไม่คัดลอกโค้ด template แบบ vanilla มาใช้ตรง ๆ

## 3. สภาพแวดล้อม บัญชี และความลับ

| สภาพแวดล้อม | Supabase (สิงคโปร์) | B2 bucket | หน้าเว็บ | ใช้ทำ |
| --- | --- | --- | --- | --- |
| ทดสอบ (dev) | โปรเจกต์ `kemi-dev` | `kemi-dev-files` | preview ของ Pages จาก branch | พัฒนาและทดสอบอัตโนมัติ ด้วยข้อมูลทดสอบเท่านั้น |
| ทดสอบกู้คืน | Supabase ชั่วคราวใน runner ของ GitHub Actions (`supabase start`) | `kemi-dev-files` ใต้ key เดิม แล้วลบในรอบเดียวกัน | — | `restore-test` เท่านั้น ทิ้งทั้งหมดเมื่อจบงาน |
| ใช้จริง (prod) | โปรเจกต์ `kemi-prod` | `kemi-files` | `https://<ชื่อ>.pages.dev` จาก branch `main` | ข้อมูลนักเรียนจริงเท่านั้น |

- **ระยะ 1–6 ยังไม่มี `kemi-prod`:** ตัวแปร Production ของ Pages ชี้ `kemi-dev` ชั่วคราว (ตัดสินใจ 2 ต.ค. 2026) เพื่อให้ `https://<ชื่อ>.pages.dev` ใช้สาธิตได้; หน้าเว็บแสดงแถบ “ระบบทดสอบ · ใช้ข้อมูลสมมติเท่านั้น” ทุกหน้า เว้นแต่ build ตั้ง `VITE_DEPLOY_ENV=prod` (ลืมตั้งแล้วแถบยังขึ้น ไม่ใช่หายไปเงียบ ๆ) และห้ามนำเข้ารายชื่อหรือข้อมูลนักเรียนจริงจนกว่าจะสลับไป prod ในระยะ 7 ซึ่งเป็นช่วงเดียวกับที่เผยแพร่ OAuth (P7-06) ก่อนหน้านั้นมีแค่บัญชีใน Test users ที่ล็อกอินได้
- แผนฟรีของ Supabase มีได้ 2 โปรเจกต์ (prod + dev) จึงไม่กู้ข้อมูลจริงเข้า `kemi-dev` ซึ่งมีลิงก์ preview และบัญชีทดสอบ แต่กู้เข้า Supabase ชั่วคราวในงาน Actions แทน **[ต้องพิสูจน์]**
- พื้นที่ฟรี 10 GB ของ B2 นับรวมทุก bucket ในบัญชี: ให้ bucket ทดสอบใช้ไฟล์เล็ก ล้างเป็นระยะ และ **ตั้ง `quota_bytes` ของระบบจริงเป็น 10 GB ลบพื้นที่ที่กันไว้ให้ bucket ทดสอบ** (เช่น 9,500,000,000 ไบต์ เมื่อกันไว้ 0.5 GB) เพื่อให้ระบบหยุดรับตาม J10.2 ก่อนเพดานรวมของบัญชี; **ส่วน `kemi-dev` ตั้ง `quota_bytes` เท่าพื้นที่ที่กันไว้ให้ bucket ทดสอบ (เช่น 500,000,000 ไบต์) และ `hard_stop_margin_bytes` เล็กตามสัดส่วน (เช่น 50,000,000)** เพราะ bucket dev ใช้ 10 GB ก้อนเดียวกับ prod; ค่าที่ migration ใส่เป็นค่าเริ่มต้นให้ใช้ค่าฝั่ง dev (ลืมแก้บน prod แล้วหยุดรับเร็ว ดีกว่าเกินเพดานบัญชี) แล้วตั้งค่า prod ในงานเตรียม prod ระยะ 7 (ทบทวน 4 ต.ค. 2026); `restore-test` รอบรายเดือนกู้ไฟล์เป็นตัวอย่างและลบทันที
- **ภูมิภาค B2 เลือกตอนสมัครบัญชีและเปลี่ยนภายหลังไม่ได้** (ต้องเปิดบัญชีใหม่) และไม่มีเอเชีย: ในระยะ 0 วัดเวลาเชื่อมต่อ (`curl -w '%{time_connect} %{time_appconnect}'`) ไปยัง endpoint S3 ของทุกภูมิภาคตามเอกสาร B2 จาก Wi-Fi โรงเรียนและเน็ตมือถือหลายรอบ แล้วเลือกที่เร็วสุดตาม SYSTEM_SPEC ส่วน 12 ก่อนสมัคร และวัดซ้ำด้วยการอัปโหลดจริงที่จุดสาธิต 2; **ผลวัด 4 ต.ค. 2026** (`ops/b2-latency.mjs`, เน็ตมือถือของผู้พัฒนา, มัธยฐานเวลาตอบแรก 5 รอบ): EU Central 665 ms (638–695), US West 761 ms, CA East 2,167 ms, US East 2,702 ms → **เลือก EU Central** (`s3.eu-central-003.backblazeb2.com`); Wi-Fi โรงเรียนยังไม่ได้วัดเพราะผู้พัฒนาไม่ได้อยู่ที่โรงเรียน จึงให้ครูลองอัปโหลดจริงจาก Wi-Fi โรงเรียนที่จุดสาธิต 2 (P3-12) — ถ้าช้าผิดปกติ ก่อนระยะ 7 ยังไม่มีข้อมูลจริงใน B2 จึงเปิดบัญชีใหม่ในภูมิภาค US West ได้โดยไม่ต้องย้ายข้อมูล; **ผลจุดสาธิต 2 (8 ต.ค. 2026, เวลาจาก batch ถึงไฟล์ ready ในฐานข้อมูล ไม่รวมเวลาย่อรูปในเครื่อง):** ครูอัปโหลดผ่าน Wi-Fi โรงเรียน 3 ชุด ชุดละ 1 รูป (0.23–0.37 MB) ใช้ 4–5 วินาที และครูบอกว่าใช้ได้; การทดสอบบน iPhone/laptop วันเดียวกัน 1–3 ไฟล์ (0.4–3.5 MB) ใช้ 4–14 วินาที → **คง EU Central** และวัดซ้ำช่วงคาบที่นักเรียนใช้เน็ตพร้อมกันตอนนำร่อง

**ที่เก็บความลับ** (ห้ามอยู่ในโค้ดหรือไฟล์ build)

| ความลับ | อยู่ที่ |
| --- | --- |
| Supabase URL + publishable key (`sb_publishable_…`) | ตัวแปร build ของ Pages (`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`) — เปิดเผยได้ตามแบบ ความปลอดภัยมาจาก RLS; ตอน build ใส่ URL นี้ลงใน CSP `connect-src` ให้เอง |
| Google OAuth client secret (ล็อกอิน) | ตั้งค่า Auth ของ Supabase |
| B2 key อ่าน/เขียน/ลบ (เฉพาะ bucket) | secret ของ Edge Functions (`B2_KEY_ID`, `B2_APP_KEY`, `B2_BUCKET`, `B2_ENDPOINT`) |
| service role ของ Supabase (Edge Function ใช้เขียนข้อมูลที่ระบบเชื่อ เช่นผล complete) | `SUPABASE_SERVICE_ROLE_KEY` ที่ Edge Function ได้อัตโนมัติ (กุญแจแบบ legacy) — **ห้ามปิด legacy API keys ใน Dashboard จนกว่าจะเปลี่ยนฟังก์ชันไปใช้ secret key แบบใหม่ (`sb_secret_…`)**; ไม่ใส่ใน Pages หรือ GitHub |
| รหัสลับที่ `pg_cron` ใช้เรียก `process-jobs` | Supabase Vault + secret ของ Edge Function |
| งานสำรอง (P3-11, ชื่อตาม `backup.yml`): `BACKUP_DB_PASSWORD` (รหัสผ่านฐานข้อมูลอย่างเดียว — host/user ของ Session pooler ไม่ใช่ความลับ เขียนใน workflow), `RCLONE_CONFIG` (ทั้งไฟล์: token ของ Drive, กุญแจ B2 อ่านอย่างเดียวใน remote `b2ro`, รหัส crypt + salt แบบถอดกลับได้ — จึงไม่มี secret crypt แยก), `HC_PING_URL`, `SUPABASE_PING_KEY` (secret key `sb_secret_…` ชื่อ `github_backup` (ชื่อรับเฉพาะตัวพิมพ์เล็ก ตัวเลข `_`) ใช้เฉพาะเรียก `ping()` ไม่บังคับ); ระยะ 7 เพิ่ม `SUPABASE_ACCESS_TOKEN`, B2 key สำหรับ `restore-test` (เขียน/ลบได้เฉพาะ `kemi-dev-files`) และชุดของ prod | GitHub Actions secrets |
| รหัส crypt + salt, recovery codes ของทุกบัญชี | ตัวจัดการรหัสผ่านของผู้พัฒนา + สำเนาออฟไลน์ |

## 4. ฐานข้อมูล

### 4.1 หลักการเขียน

1. ทุกตารางใน `public` เปิด RLS; ไม่มี policy ให้ `anon`; ใน migration แรกตั้ง `ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (แบบทั้งระบบ เพราะ Postgres ให้ `PUBLIC` execute ทุกฟังก์ชันเป็นค่าเริ่มต้น และการ REVOKE เฉพาะ schema ลบสิทธิ์ระดับทั้งระบบไม่ได้) และ `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated` (ย้อนค่าที่ Supabase ให้ไว้รายschema) แล้ว GRANT รายฟังก์ชันตามข้อ 3 และยังตรวจซ้ำด้วยรายการในส่วน 11; ตาราง/sequence ใหม่ถอนสิทธิ์ทั้งหมดจาก `anon`, `authenticated` (รวมสิทธิ์ย่อยอย่าง TRUNCATE/REFERENCES/TRIGGER ที่ Supabase ยังให้แม้ปิด auto-expose) แล้ว GRANT เฉพาะ SELECT ที่หน้าเว็บอ่านผ่าน RLS; ถอน EXECUTE ของ `public.rls_auto_enable()` จาก `anon`, `authenticated`; ห้าม GRANT USAGE บน schema `private` ให้ `anon`/`authenticated`; ตาราง (ถ้ามี) ใน `private` เปิด RLS เองเพราะ automatic RLS ทำเฉพาะ `public` (ผลตรวจ `kemi-dev` 30 ก.ย. 2026)
2. หน้าเว็บ **อ่าน** ผ่าน SELECT policy หรือ RPC อ่าน และ **เขียนผ่าน RPC เท่านั้น** (ไม่มี INSERT/UPDATE/DELETE policy)
3. RPC ที่หน้าเว็บเรียกเป็น `SECURITY DEFINER`, `SET search_path = ''`, อ้างชื่อเต็ม และตรวจสิทธิ์เองจาก `private.current_account()`; GRANT ให้ `authenticated` เท่านั้น; ฟังก์ชันช่วยใน `private` ที่ RLS policy เรียกเป็น `SECURITY DEFINER` + GRANT EXECUTE ให้ `authenticated` รายฟังก์ชัน โดยไม่ GRANT USAGE บน `private` (policy ต้องการแค่ EXECUTE — TECHNICAL_DESIGN 3.1 ข้อ 5) และใน policy เขียนเป็น `(select private.current_account())` ให้คำนวณครั้งเดียวต่อคำสั่ง ไม่ใช่ทุกแถว; pgTAP ต้องมีข้อยืนยันว่า `authenticated` เรียกฟังก์ชันช่วยตรงๆ ไม่ได้; RPC ที่ Edge Function เรียกด้วย service role (เช่น `finalize_attachment`) GRANT ให้ `service_role` เท่านั้น
4. เวลาเก็บเป็น `timestamptz` (UTC) และตัดสินด้วย `clock_timestamp()` หลังล็อกแถว; คะแนนและโทเคนเป็นจำนวนเต็ม คำนวณหักสายด้วย `(raw * (100 - pct) + 99) / 100`
5. ลำดับล็อก: `term_control` → `assignments` → `submissions` → `wallets`; ห้ามเรียกบริการภายนอกระหว่างถือล็อก
6. คำสั่งที่เสี่ยงกดซ้ำรับ `p_request_key uuid` และบันทึกใน `operation_receipts` (อายุ 24 ชม.) คำขอซ้ำคืนผลเดิม
7. ข้อผิดพลาดตามกติกา `RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '<รหัส>'` เช่น `storage_full`, `term_ended`, `full_score_locked`, `reason_required`, `stale_revision`, `rate_limited` แล้วหน้าเว็บแปลงเป็นข้อความตาม UX_DESIGN ส่วน 7.1; migration ที่เพิ่มรหัสใหม่ต้องแจ้งให้เพิ่มแถวในตารางนั้นก่อนหน้าเว็บจะใช้ และรหัสที่ไม่มีในตารางแสดงข้อความสำรองของตาราง
8. ทุก migration มีไฟล์ทดสอบ pgTAP คู่กันก่อน merge
9. `accounts.auth_user_id` **ไม่ใส่ foreign key ไป `auth.users`** เพราะ dump ไม่รวม schema `auth` และต้องกู้ข้ามโปรเจกต์ได้ ตอนกู้ตั้งค่านี้เป็น NULL แล้ว `ensure_account()` จับคู่ใหม่ด้วย `provider_subject` (TECHNICAL_DESIGN ส่วน 3.1 ข้อ 7)

ตัวอย่างโครง RPC:

```sql
create or replace function public.grade_submission(
  p_submission_id uuid, p_raw int, p_pass boolean,
  p_override_pct int, p_reason text, p_seen_revision int,
  p_expected_version int,             -- รุ่นของแถว grades ที่หน้าจอเห็น (null = ยังไม่มีผลตรวจ) กันบันทึกทับ
  p_request_key uuid, p_admin_mode boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_acc record;
begin
  v_acc := private.require_teacher(p_admin_mode);   -- ครู หรือ admin ที่อยู่ในโหมดผู้ดูแล (L6; การส่ง p_admin_mode เป็นข้อเสนอใน TECHNICAL_DESIGN ส่วน 3)
  -- ล็อกตามลำดับ ตรวจ revision, K1 (0..full), L2 (0..100 + เหตุผล), L4 (ล็อกเมื่อ raw แรก),
  -- บันทึกผล + ความคิดเห็นเหตุผล + รางวัลครั้งเดียว ใน transaction เดียว
  ...
end $$;
revoke execute on function public.grade_submission from public, anon;
grant execute on function public.grade_submission to authenticated;
```

### 4.2 ลำดับ migration

| # | ไฟล์ **[ข้อเสนอ]** | เนื้อหา | ระยะ |
| --- | --- | --- | --- |
| 1 | `0001_base.sql` | schema `private`, ส่วนขยาย (`pgcrypto`; **ไม่ติดตั้ง `pgtap` ใน migration** — ไฟล์ทดสอบติดตั้งภายใน transaction แล้ว rollback จึงไม่เหลือบนฐานข้อมูลใด), default privileges, `private.settings` (ค่าตั้งของระบบ), `operation_receipts`, `rate_limits`, `jobs`, `maintenance_locks`, `ping()` — ตารางกลางที่ทุกระยะใช้ | 1 |
| 2 | `0002_accounts.sql` | `accounts`, `teachers`, `private.teacher_allowlist`, `ensure_account()`, `private.current_account()`, `require_teacher()`, `require_admin()` | 1 |
| 3 | `0003_roster.sql` (push แล้ว 3 ต.ค. 2026) | `terms`, `term_control`, `students`, `roster_entries`; RPC `preview_roster_import` / `commit_roster_import` (ไม่ลบคนที่หายจากไฟล์ ไม่แตะการผูกบัญชี มีแถวผิดแถวเดียวไม่บันทึกเลย) | 2 |
| 4 | `0004_identity.sql` (push แล้ว 3 ต.ค. 2026) | `search_roster`, `claim_identity` (L3: เทียบตรงทั้งค่า ตัดคำนำหน้าและช่องว่าง, ชื่อปิดบางส่วน, รหัสอ้างอิงอายุสั้น, เพดานใน `rate_limits`, ชิงชื่อพร้อมกันสำเร็จบัญชีเดียว) | 2 |
| 5 | `0005_classrooms.sql` (push แล้ว 3 ต.ค. 2026) | `classrooms`, `memberships`; แก้ผูก, สร้างห้อง/รหัส, เข้าห้องด้วยรหัสหรือลิงก์เชิญ (ไม่จำกัดห้องตามรายชื่อ), ปิด/เปิดการเข้าห้อง, เอานักเรียนออกจากชั้นเรียน `remove_member` (ไม่ลบงาน), จัดการบัญชีครู | 2 |
| 5a | `0006_teachers_read.sql` (push แล้ว 3 ต.ค. 2026) | ให้ครูและผู้ดูแลอ่านตาราง `teachers` ได้ (ชื่อครูบนแถบบน และให้ผู้ดูแลเลือกครูเจ้าของห้องใน T09) | 2 |
| 5b | `0007_student_classrooms.sql` (push แล้ว 4 ต.ค. 2026) | RPC `my_classrooms()` และ `classroom_view(uuid)` ให้นักเรียนเห็นชื่อห้อง ชื่อครู จำนวนสมาชิก และชื่อ + เลขที่ของเพื่อนในห้อง โดยไม่เปิด RLS ของตารางให้กว้างขึ้น (ไม่คืนเลขประจำตัว อีเมล หรือห้องตามรายชื่อของคนอื่น) | 2 |
| 5c | `0008_rebind.sql` (push แล้ว 4 ต.ค. 2026) | `roster_overview`, `rebind_preview`, `rebind_student`, `unbind_student`: แก้การผูก 2 แบบ ลบ `auth.sessions` และ refresh token ของบัญชีเดิมใน transaction เดียว ไม่แตะ membership งาน คะแนน โทเคน | 2 |
| 5d | `0009_teacher_admin.sql` (push แล้ว 4 ต.ค. 2026) | `admin_teachers`, `admin_add_teacher`, `admin_remove_teacher`: จัดการ allowlist ใน D01 ต้องเหลือครูอย่างน้อย 1 รายการ เอาออกแล้วสิทธิ์ครูหายทันที | 2 |
| 6 | `0010_posts.sql` (push แล้ว 4 ต.ค. 2026) | `posts`, `assignments`, `solutions`; ตัวกันช่องที่ล็อกเป็น trigger ระดับตาราง (I4 `reward_locked`, J2/L4/K2 `full_score_locked`, รับหลังเฉลย `after_solution_locked`, ชนิดโพสต์และเวลาเผยแพร่เฉลยแรก K4); RLS อ่านผ่าน `is_member`/`can_teach_classroom` และ `private.post_access`; GRANT แค่ SELECT ยังไม่มี RPC เขียน | 3 |
| 6a | `0011_files.sql` (push แล้ว 4 ต.ค. 2026) | `assets`, `attachments`, `upload_batches`, `storage_settings` (แถวเดียว ค่า dev); `private.storage_used_bytes()`, `private.reserve_storage()` (ล็อกแถวตั้งค่าก่อนนับ ตอบ `storage_full`), `private.can_read_solution(uuid)`; แถวผูกหายตามโพสต์/เฉลยแต่ asset อยู่ต่อ; สถานะไฟล์เดินหน้าอย่างเดียว; GRANT แค่ SELECT และไม่เปิดคอลัมน์ key/เวอร์ชัน/checksum/เจ้าของ | 3 |
| 6b | `0012_backups.sql` (push แล้ว 4 ต.ค. 2026) | `backup_runs` (public, ผู้ดูแลอ่าน, เก็บเป็นประวัติ), `private.backup_manifests`; ฟังก์ชันสำรอง 6 ตัวใน `private` เรียกได้เฉพาะ postgres (เริ่มรอบพร้อมตั้ง `maintenance_locks`, บันทึก manifest จาก snapshot แบบ REPEATABLE READ, จบรอบ, ปลดล็อก, บันทึก restore_test, ล้าง manifest เก่า); **ตาราง manifest แบบแถวต่อไฟล์ต่อรอบจะเปลี่ยนเป็นไฟล์ละแถวใน P3-01d (แถวถัดไป)** | 3 |
| 6c | `0013_backup_manifest.sql` (P3-01d, push แล้ว 4 ต.ค. 2026) | `private.backup_manifests` เป็นไฟล์ละแถว (`final_key` PK, `version_id`, ขนาด, checksum, รอบสำเร็จแรกและล่าสุดที่เห็นไฟล์) + `private.backup_run_files` รายการชั่วคราวของรอบที่กำลังทำ (ล้างเมื่อจบรอบไม่ว่าผลใด); รวมเข้าตารางถาวรเฉพาะรอบสำเร็จ; `backup_run_file_list`, `backup_new_files`, `backup_prune_candidates` → `backup_prune_confirm` (แทน `backup_prune_manifests`); ไม่ล้างไฟล์ของรอบสำเร็จล่าสุด; ตามที่ตัดสินในส่วน 8 | 3 |
| 6d | `0014_post_rpcs.sql` (push แล้ว 4 ต.ค. 2026) | `create_post(p_classroom_id, p_post jsonb, p_request_key, p_admin_mode)` — เนื้อหาเป็น jsonb ก้อนเดียวเพื่อเพิ่มคีย์ไฟล์ภายหลังโดยไม่เปลี่ยน signature; กติกา K5 (ภาคเรียน ended: การบ้านไม่ได้ ประกาศได้; ห้องเทอมก่อน: ไม่ได้ทั้งคู่); `close_at` ≥ `due_at`; เวลาต้องระบุเขตเวลา | 3 |
| 6e | `0015_post_update.sql` (push แล้ว 5 ต.ค. 2026) | `update_post(p_post_id, p_post jsonb, p_expected_version, p_request_key, p_admin_mode)` — ตรวจ request key ก่อนเทียบ version (ส่งซ้ำได้ผลเดิม) แล้ว `stale_revision`; แก้ชื่อ/รายละเอียดได้ตลอด ช่องงานแก้ได้จนล็อก; `due_at`/`close_at` รับเฉพาะค่าเดิม (เปลี่ยนผ่าน M1/M2 ใน P4-03) ต่างตอบ `invalid_request`; `content_updated_at` ขยับเฉพาะชื่อ/รายละเอียดเปลี่ยนจริง บันทึกโดยไม่เปลี่ยนไม่ขยับ version; ไม่จำกัดตามภาคเรียน; โพสต์ที่ไม่มีหรือไม่มีสิทธิ์ตอบ `forbidden` | 3 |
| 6f | `0016_upload_batch.sql` (push แล้ว 5 ต.ค. 2026) | `create_upload_batch(text,uuid,uuid,jsonb,uuid,boolean)` — ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล, วัตถุประสงค์ post/solution (submission มากับกลุ่ม submissions, charm ระยะ 5), J4–J6 (10 ไฟล์, รูป ≤ 2 MiB, PDF ≤ 10 MiB, รวม ≤ 20 MiB ต่อชุด), request key, เพดาน 30 ครั้ง/10 นาที/บัญชี, `reserve_storage` + batch ใน transaction เดียว, key `staging/{batch_id}/{uuid}`, batch อายุ 120 นาที | 3 |
| 6g | `0017_upload_complete.sql` (push แล้ว 5 ต.ค. 2026) | `upload_complete_target` (authenticated, อ่านอย่างเดียว) + `upload_complete_begin`/`finish`/`abort` และ `record_b2_usage` (service_role เท่านั้น — รายการแยกใน `function_privileges`); ตาราง `b2_daily_usage` ตามวัน UTC × แหล่ง (view/complete/backup): คำขอ Class B, ไบต์ดาวน์โหลด, `copy_bytes`; ค่างบเปิดดูใน `storage_settings` (750 MB / 1,800 คำขอ) | 3 |
| 6h | `0018_files_sign.sql` (push แล้ว 5 ต.ค. 2026) | `authorize_files(uuid[])` (authenticated: คืนเฉพาะ id ที่พร้อมใช้และมีสิทธิ์ ไม่ครบทั้งชุดตอบ `forbidden`) + `files_sign_begin(uuid[])` (service_role: ล็อกแถวตัวนับของวัน ตรวจ+นับงบเปิดดูในขั้นเดียว คืน key/เวอร์ชัน/ขนาด/ชื่อไฟล์) | 3 |
| 6i | `0019_post_files.sql` (push แล้ว 6 ต.ค. 2026) | `create_post`/`update_post` signature เดิม รับ `p_post.files` (asset id ตามลำดับ) — ผิดเงื่อนไข `post_file_unavailable`, ซ้ำ `invalid_request`, เกิน `too_many_files`/`batch_too_large`; ประกาศต้องมีข้อความหรือไฟล์ (`post_body_required`); batch `consumed` เมื่อผูกครบ; ผลคืนมีคีย์ `files` | 3 |
| 7 | `0020_submissions.sql` (6 ต.ค. 2026) | `submissions`, `revision_permissions`, `attachments.submission_id`; `create_upload_batch` วัตถุประสงค์ submission; `authorize_files` ไฟล์งานส่ง = เจ้าของ + ครู/ผู้ดูแล; `submit_assignment` ตามตารางรับการส่ง (TECHNICAL_DESIGN ส่วน 5 รวมลำดับตรวจที่ทำจริง), ส่งแก้แบบเก็บไฟล์เดิม, ไฟล์ที่ถูกแทนเป็น `deleting` + งาน `delete_asset` ใน `jobs` พร้อม `version_id`; ล็อกแถวงานแบบผูกขาดเฉพาะก่อนส่งแรก (ตั้ง `reward_locked_at`) หลังจากนั้นล็อกแบบใช้ร่วม | 3 |
| 7b | `0021_submission_status.sql` (6 ต.ค. 2026) | `private.submission_outcome` เป็นที่เดียวของกติกาตารางรับการส่ง ใช้ร่วมโดย `submit_assignment`, `create_upload_batch` (นักเรียน: ปฏิเสธเมื่อส่งไม่ได้แน่นอนด้วยรหัสเดียวกัน), RPC อ่าน `submission_status` (S03) และ `my_work` (S01/S02) | 3 |
| 7c | `0022_teacher_work.sql` (P3-09) | RPC อ่านสำหรับครู/ผู้ดูแล: ยอดต่องานของ T08 และรายชื่อสถานะของงานหนึ่งสำหรับ T03 (สมาชิกขณะนี้ ∪ นักเรียนที่ถูกเอาออกแต่มีงานส่ง เรียงเลขที่) ไม่ต้องส่ง admin mode; คนอื่นได้ `forbidden` | 3 |
| 7d | `0023_jobs.sql` (P3-10) | คิว `jobs`: ดึงแบบ `SKIP LOCKED` ทีละชุด, สำเร็จ/ล้ม + ลองใหม่เว้น 1→2→4→8→16 นาที ครบ 6 ครั้งเป็น `failed`, งาน running ค้างเกิน 10 นาทีดึงใหม่ได้; `delete_asset` ตรวจ `maintenance_locks` และไม่ลบ asset ที่ยังผูก; sweeper `copying` > 15 นาที; งานประจำใน SQL: batch เลยเวลาเป็น `expired`, asset กำพร้า (ไม่มีแถวผูก + batch หมดอายุเกิน 24 ชม. หรือไม่มี batch แล้วนับ 24 ชม. จากเวลาพร้อมใช้) เข้าคิวลบ, ล้าง `b2_daily_usage` > 30 วัน, งาน `done` > 30 วัน และใบรับคำขอที่หมดอายุ (`failed` เก็บไว้); RPC เป็น service role ยกเว้น `storage_status` และ `admin_b2_usage` | 3 |
| 7e | `0024_jobs_cron.sql` (P3-10) | `pg_cron` ทุก 2 นาที: ทำงานประจำใน SQL แล้วปลุก `process-jobs` ผ่าน `pg_net` เฉพาะเมื่อมีงาน (URL + รหัสลับจาก Vault; ตั้งรหัสด้วย `ops/jobs/set-secret.mjs` ที่ไม่พิมพ์ค่า) | 3 |
| 8 | `0025_grading.sql` (P4-01) และ migration ถัดไปของระยะ 4 | `grades` (ข้อมูลเวลาที่ใช้ตรวจเป็นคอลัมน์ `timing_*` ไม่แยกตาราง), `comments`; ตรวจ (L2/L4/K2), เปิดสิทธิ์แก้ (K3), ความคิดเห็น/ยกเลิก (F5), เปลี่ยนกำหนดส่งสองทิศ (N3, I2)/ปิดรับ, เฉลยบันทึก/เผยแพร่/แก้ (K4), ลบงาน/ประกาศแบบ cascade (N4), ตารางคะแนน | 4 |
| 9 | `…_rewards.sql` | `wallets`, `rarities`, `charms`, `owned_charms`, `student_equipment`; ให้รางวัลครั้งเดียว, สถานะเอฟเฟกต์ได้รับโทเคน, ปรับยอด, อัตราสุ่มจริง, สุ่ม (K6), สวมใส่, จัดการเครื่องราง | 5 |
| 10 | `…_terms.sql` | `terms_start`, `terms_end` (J9, K5, I5), epoch และล้างยอด | 5 |
| 11 | `…_notifications.sql` | `notifications`; สร้างแจ้งเตือนนักเรียน 5 / ครู 3 เหตุการณ์, งานเตือน 24 ชม. (J7, L5), เกณฑ์พื้นที่ | 6 |
| 12 | `…_retention.sql` | `retention_requests`; รายการส่งออก, ยืนยันลบ (จำนวน/ไบต์ต้องตรง), ลบก่อนกำหนด (J10.4), ตรวจเทอมเปิดเกิน 6 เดือน | 6 |

เลขไฟล์จริงเรียงตามลำดับที่ push และ migration ที่ push แล้วแก้ไม่ได้ ตารางนี้จึงใส่เลขเฉพาะไฟล์ที่ push แล้ว ไฟล์ที่ยังไม่ทำเขียนเป็น `…_ชื่อ.sql` ให้ใช้เลขถัดไปตอนสร้าง และแยกไฟล์ย่อยได้ตามงาน; ส่วนแผนรายระยะอ้างกลุ่มเนื้อหาด้วยชื่อ ไม่อ้างเลข

`seed.sql`: ระดับ 4 ระดับน้ำหนัก 60/25/10/5, เครื่องราง 12 ชิ้นตาม UX_DESIGN ส่วน 11 (J8), `storage_settings` (ค่า prod: `quota_bytes` = 10 GB แบบที่ B2 คิด (1 GB = 1,000,000,000 ไบต์) ลบส่วนที่กันไว้ให้ bucket ทดสอบตามส่วน 3 ส่วน dev ใช้ค่าตามส่วน 3, 80/90%, `hard_stop_margin_bytes` **[ข้อเสนอ]** 300,000,000 ไบต์), `term_control` เริ่มต้น; บน prod ใส่เฉพาะข้อมูลตั้งต้น ไม่ใส่นักเรียนทดสอบ

## 5. RPC และ Edge Functions

**RPC ในฐานข้อมูล** (เรียกด้วย `supabase.rpc`) ครอบคลุมทุกคำสั่งในตาราง API ของ TECHNICAL_DESIGN ส่วน 10 ที่ไม่ต้องใช้กุญแจ B2 เช่น `ensure_account`, `search_roster`, `claim_identity`, `rebind_student`, `create_classroom`, `lookup_classroom`, `join_classroom`, `set_join_enabled`, `create_post`, `update_post`, `update_assignment`, `delete_post`, `submit_assignment`, `grade_submission`, `open_revision_permission`, `post_comment`, `retract_comment`, `change_due`, `close_assignment`, `save_solution`, `publish_solution`, `update_solution`, `wallet_adjust`, `get_draw_options`, `draw_charm`, `set_equipment`, `terms_start`, `terms_end`, `mark_notification_read`, `admin_add_teacher`, `admin_remove_teacher`

**Edge Functions** (ใช้เมื่อต้องใช้กุญแจ B2 เท่านั้น) — หลักคือ **สิทธิ์ตัดสินใน RPC ที่เรียกด้วย JWT ของผู้ใช้** ส่วนฟังก์ชันทำเฉพาะงานที่ต้องใช้กุญแจ:

| ฟังก์ชัน | เส้นทาง | ขั้นตอน |
| --- | --- | --- |
| `uploads` | `POST /uploads` | RPC `create_upload_batch` (ตรวจสิทธิ์ งาน `ended` พื้นที่ จำนวน/ขนาด J4–J6, เพดานครั้ง) → ลงลายเซ็น PUT ต่อไฟล์ใต้ `staging/` อายุ 5 นาที พร้อม `content-type` และ `content-length` |
| `uploads` | `POST /uploads/:batch_id/complete` (body `{ item }`) | RPC `upload_complete_target` ด้วย JWT ผู้ใช้ (ตรวจเจ้าของ batch คืน staging key/ชนิด/ขนาดจากแถว batch — หน้าเว็บส่ง key เองไม่ได้) → GET แบบ Range 0–15 ครั้งเดียว (`staging_version_id` จาก `x-amz-version-id`, ขนาดจาก `Content-Range`, magic number) → `upload_complete_begin` (service role: ตรวจซ้ำ ล็อกแถว batch สร้าง asset `copying` — เรียกซ้ำ/พร้อมกันได้ asset เดิม) → CopyObject ระบุ `versionId` ต้นทาง + `REPLACE` content-type ไปที่ `files/{asset_id}.{jpg|png|pdf}` → `upload_complete_finish` (version/ETag ปลายทาง → `ready`) → ลบ staging ระบุเวอร์ชัน; CopyObject ได้ 4xx → `upload_complete_abort` ลบแถว, ผลไม่แน่นอน (5xx/เน็ตหลุด) ปล่อย sweeper; ทุกขั้นนับ `record_b2_usage`; ฟังก์ชันที่เขียนข้อมูลที่ระบบเชื่อ GRANT ให้ `service_role` เท่านั้น (`0017_upload_complete`) |
| `files` | `POST /files/sign` (`{ asset_ids, mode: view|download }`) | เพดาน 120 ครั้ง/10 นาที/บัญชี (นับก่อนตรวจสิทธิ์ กันไล่เดา id) และไม่เกิน 20 ไฟล์ต่อคำขอ → RPC `authorize_files(ids)` ด้วย JWT ผู้ใช้ คืนเฉพาะ id ที่ `ready` และมีสิทธิ์ (ไม่ครบทั้งชุดตอบ `forbidden` ไม่บอกว่ามีไฟล์อยู่หรือไม่; key/เวอร์ชัน/checksum ไม่เปิดให้ผู้ใช้) → `files_sign_begin(ids)` ด้วย service role อ่าน `final_key`/`version_id`/ขนาด/ชื่อไฟล์ และตรวจ+นับงบเปิดดูรายวันในขั้นเดียว (ไฟล์ละ 1 คำขอ + ขนาดเต็ม ทั้งเปิดดูและดาวน์โหลด นับทุกครั้งที่ออกลิงก์; ชุดที่รวมแล้วเกินงบถูกปฏิเสธทั้งชุดด้วย `download_budget_reached`) → presigned GET 600 วินาทีระบุ `versionId` + `response-content-type` + `response-content-disposition` (`inline`/`attachment`, ชื่อไทยแบบ `filename*=UTF-8''…`) + `response-cache-control: private,max-age=600`; การลงลายเซ็นไม่เรียก B2; ผู้ดูแลขอได้โดยไม่ต้องส่ง `p_admin_mode` เพราะเป็นการอ่าน (หน้าเว็บแสดงไฟล์ให้ผู้ดูแลเฉพาะในโหมดผู้ดูแล) |
| `files` | `GET /submissions/:id/files` | RPC ครู/ผู้ดูแลในโหมดผู้ดูแล → รายการไฟล์ตามลำดับ + ลิงก์ + ชื่อ PDF `{เลขที่ 2 หลัก}_{ชื่อ}_{นามสกุล}.pdf` |
| `files` | `POST /exports` | RPC ครู → รายการไฟล์ภาคเรียนเป็นหน้า ๆ พร้อมลิงก์ สำหรับ ZIP ฝั่งเบราว์เซอร์ |
| `process-jobs` | เรียกจาก `pg_cron` ผ่าน `pg_net` (ทุก 2 นาทีเฉพาะเมื่อมีงาน) | เทียบรหัสลับแบบเวลาคงที่ → ดึงงานด้วย `FOR UPDATE SKIP LOCKED` → ทำงานตาม `kind`: `delete_asset` = DeleteObject ระบุ `version_id` (สำเร็จหรือ 404 = ลบแล้ว ยืนยันด้วยคำตอบนี้ ไม่ HEAD/List ซ้ำ), sweeper `copying` = HEAD ปลายทาง (นับ Class B) → ทำงานเพิ่มในระยะ 6 |

ทุกฟังก์ชันตั้ง CORS รับเฉพาะ origin ของเว็บเรา ตรวจ JWT ของผู้ใช้ (ยกเว้น `process-jobs` ที่ตรวจรหัสลับ) และไม่บันทึกเนื้อหาไฟล์/ความคิดเห็นลง log

## 6. หน้าเว็บ

| รหัสหน้าจอ | เส้นทาง **[ข้อเสนอ]** | ระยะ |
| --- | --- | --- |
| A01, A02 | `/login`, `/join/:code` (ลิงก์เชิญ: ล็อกอิน → เลือกชื่อ → ยืนยันเข้าห้อง), ป๊อปอัปเลือกชื่อทับหน้าแรก | 1–2 |
| S01, S02, S03 | `/`, `/c/:classId`, `/c/:classId/w/:postId` | 2–4 |
| S06 | `/me` (ยอดโทเคนและตู้สะสมเติมในระยะ 5) | 2 |
| S04, S05, C01 | `/draw`, `/collection`, `/notifications` | 5–6 |
| T01, T09, T08, T10 | `/t`, `/t/new-class`, `/t/c/:classId` (+ แสดงรหัสเต็มจอ) | 2 |
| T02, T03 | `/t/c/:classId/new`, `/t/w/:postId/edit` (แก้ไข N2), `/t/w/:postId` (สถานะ + การ์ดโจทย์), `/t/w/:postId/s/:studentId` (ตรวจ) | 3–4 |
| T04, T05 | `/t/c/:classId/grades`, `/t/roster` (รายชื่อทุกห้องตามไฟล์ เพราะรายชื่อไม่ได้ผูกกับชั้นเรียน; นำเข้าที่ `/t/roster/import`) | 2–4 |
| T12 | `/t/me` | 2 |
| T06, T07, T11 | `/t/charms`, `/t/term`, `/t/notifications` | 5–6 |
| D01 | `/admin` (+ ปุ่มเข้าหน้าครูในโหมดผู้ดูแล แถบเตือนอยู่ใน layout ครู) | 2, 6–7 |

- **ข้อความ:** ใช้ข้อความจากแบบ v2/UX_DESIGN เป็นค่าเริ่มต้น รวมไว้ที่ `src/copy/th.ts` เพื่อแก้ตามที่ครูขอได้ที่เดียว
- **ตัวห้อย/ตัวยก:** ช่องรายละเอียดงาน ประกาศ เฉลย และความคิดเห็นมีปุ่มแปลงตัวที่เลือกเป็นอักขระ Unicode (H₂O, Fe³⁺) แล้วเก็บเป็นข้อความธรรมดา ไม่เก็บ HTML (SYSTEM_SPEC ส่วน 3)
- **อัปโหลด:** ตรวจชนิด/ขนาดก่อนย่อ (J4–J5) → แปลง HEIC → ย่อไม่เกิน 2 MB → ขอ batch → PUT ด้วย `XMLHttpRequest` เพื่อแสดงความคืบหน้ารายไฟล์ → complete → submit; ล้มเหลวกลางทางไม่ทำให้ชุดเดิมหาย
- **การแสดงผลตรวจ:** แยกคะแนนก่อนหัก การหัก คะแนนสุทธิ ผ่าน/ไม่ผ่าน และสถานะรางวัลตาม UX_DESIGN; สูตรในหน้าเว็บใช้แสดงตัวอย่างเท่านั้น
- **Security headers (`web/public/_headers`):** CSP ที่ `connect-src` อนุญาตเฉพาะ Supabase ของเราและ endpoint S3 ของ B2, `img-src` อนุญาต `blob:`, `data:` และ B2, `frame-ancestors 'none'`, `Referrer-Policy: no-referrer`; ไม่มีสคริปต์ติดตามหรือวิเคราะห์ผู้ใช้
- **รองรับจอ:** นักเรียนใช้มือถือ **และแท็บเล็ต** เป็นหลัก (SYSTEM_SPEC ส่วน 10) ตรวจที่ 320, 390 (มือถือ), 820 × 1180 (แท็บเล็ตแนวตั้ง), 1180 × 820 (แท็บเล็ตแนวนอน) และ 1280 px (คอมพิวเตอร์) และซูมข้อความ 200%; แบบ v2 แสดงหน้านักเรียนเฉพาะในกรอบมือถือ หน้าตาบนแท็บเล็ตจึงต้องออกแบบเพิ่ม (UX_DESIGN ส่วน 13)
- **แยกอุปกรณ์ด้วยความกว้างจอและ `pointer: coarse` ห้ามใช้ user agent** (Safari บน iPad แจ้งตัวเป็น Mac); ไม่มีการทำงานที่ต้องใช้ hover อย่างเดียว; เป้าแตะอย่างน้อย 44 px แม้เลย์เอาต์จอกว้าง

## 7. ตั้งค่าบริการ (ระยะ 0 และปรับในระยะ 1/3)

**Supabase (ทั้ง dev และ prod)**

1. สร้างโปรเจกต์ภูมิภาคสิงคโปร์ จดเวอร์ชัน Postgres (`select version()`)
2. Auth: เปิด Google ใส่ client ID/secret; ปิด Email, Phone และ Anonymous sign-in (dev เปิด Email ได้เฉพาะบัญชีทดสอบตามส่วน 9); Site URL และ Redirect URLs ตาม TECHNICAL_DESIGN ส่วน 3.1; ตรวจ rate limit ของ Auth
3. Database: เปิด `pg_cron`, `pg_net`; ใส่รหัสลับของ `process-jobs` ลง Vault; จด connection string ของ Session pooler สำหรับ GitHub secrets
4. API: เปิดเผยเฉพาะ schema `public` **[ข้อเสนอ]** ปิด GraphQL ถ้าไม่ใช้
5. รัน Security Advisor ใน Dashboard หลังทุกระยะที่เพิ่มตาราง/ฟังก์ชัน

**Google Cloud (ล็อกอิน)**

1. โปรเจกต์ของผู้พัฒนา → OAuth consent screen แบบ External ขอเฉพาะ `openid`, `email`, `profile`; **ระหว่างพัฒนาอยู่สถานะ Testing** และเพิ่มบัญชีทดสอบใน Test users; เผยแพร่เป็น production ในงาน P7-06 เพราะ Google บังคับให้มี homepage URL และ privacy policy URL บนโดเมนที่ยืนยันใน Authorized domains (`kemi-classroom.pages.dev`) — หน้าเว็บจึงต้องมีหน้าแรกสาธารณะและหน้า `/privacy`
2. OAuth client แบบ Web: Authorized redirect URI = `https://<project-ref>.supabase.co/auth/v1/callback` ของ dev และ prod

**Backblaze B2**

1. วัดความเร็วไปยังทุกภูมิภาคก่อน (ส่วน 3) แล้วสมัครบัญชีในภูมิภาคที่เร็วสุด ตรวจว่าต้องผูกบัตรหรือไม่ แล้วตั้ง Caps & Alerts ของ storage, download และ transactions ที่ปริมาณฟรีทันที
2. สร้าง bucket แบบ private: `kemi-files`, `kemi-dev-files`; ไฟล์ทุกชิ้นอยู่ใต้ `files/` หรือ `staging/` เท่านั้น
3. Lifecycle rules **[ต้องพิสูจน์ว่า prefix แยกกันตั้งได้ตามนี้]** (`ops/b2/lifecycle.json`):

```json
[
  {"fileNamePrefix": "files/",   "daysFromUploadingToHiding": null, "daysFromHidingToDeleting": 1},
  {"fileNamePrefix": "staging/", "daysFromUploadingToHiding": 1,    "daysFromHidingToDeleting": 1}
]
```

4. CORS (`ops/b2/cors.json`) ตั้งหลังได้ชื่อเว็บ แล้วใช้ B2 CLI ตั้งกับ bucket:

```json
[{"corsRuleName": "web",
  "allowedOrigins": ["https://<ชื่อ>.pages.dev", "https://*.<ชื่อ>.pages.dev", "http://localhost:5173"],
  "allowedOperations": ["s3_get", "s3_head", "s3_put"],
  "allowedHeaders": ["content-type", "content-length"],
  "exposeHeaders": ["ETag", "x-amz-version-id"],
  "maxAgeSeconds": 3600}]
```

   ลายเซ็นอยู่ใน query string จึงไม่ต้องอนุญาต `authorization`/`x-amz-*`; bucket ใช้จริงควรเอา `localhost` และ preview ออกเมื่อเปิดใช้; **พิสูจน์แล้ว 5 ต.ค. 2026:** B2 รับ origin แบบ wildcard และ preflight ผ่านเฉพาะ production/preview/localhost (ตั้งด้วย `ops/b2/apply-settings.mjs` ใช้กุญแจชั่วคราว `listBuckets`+`writeBuckets` แล้วลบทิ้ง)
5. Application keys: `kemi-edge` (list/read/write/delete เฉพาะ bucket), `kemi-backup-ro` (Read Only เฉพาะ bucket **จำกัด prefix `files/`** — dev ใช้ `kemi-backup-ro-dev` ของ `kemi-dev-files` สร้างจากหน้าเว็บใน P3-11) — ชื่อ capability ใช้ตาม B2 CLI รุ่นที่ติดตั้ง; dev ใช้ `kemi-edge-dev` ที่สร้างจากหน้าเว็บแบบ Read and Write เฉพาะ bucket — **ตรวจจากหน้า B2 5 ต.ค. 2026 กว้างกว่าที่ใช้มาก:** มี `writeBuckets` และ `write/readBucket*` (Encryption, LifecycleRules, Logging, Notifications, Replications) นอกจาก `readFiles`/`writeFiles`/`deleteFiles`/`listFiles`/`shareFiles` — ถ้ากุญแจนี้รั่วจะเปลี่ยน bucket เป็นสาธารณะหรือแก้ CORS/lifecycle ได้; **ของ prod ในระยะ 7 ต้องสร้างผ่าน API ให้เหลือ `readFiles`, `writeFiles`, `deleteFiles` (+ `listFiles` ถ้า sweeper ต้องใช้) เฉพาะ bucket** และพิจารณาเปลี่ยนกุญแจ dev แบบเดียวกันตอนนั้น

**Cloudflare Pages**

1. เชื่อม repo: root `web`, build `npm ci && npm run build`, output `dist`, ตั้ง `NODE_VERSION`
2. ตัวแปร build แยก production/preview (ชี้ Supabase prod/dev); ระยะ 1–6 ทั้งสองชี้ `kemi-dev` ตามส่วน 3 และไฟล์ `web/.node-version` กำหนด Node 24
3. เปิด preview deployments เฉพาะ branch ที่ใช้ทดสอบ

**Google Drive สำรอง + rclone**

1. บัญชี Google แยกของโปรเจกต์ เปิดยืนยันสองขั้น; **ไม่สร้างโฟลเดอร์เองจากหน้าเว็บ Drive** เพราะสิทธิ์ `drive.file` เห็นเฉพาะสิ่งที่ rclone สร้าง — ให้ `rclone mkdir gcrypt:` สร้าง `kemi-backup` (ไม่แชร์ให้ใคร ห้ามย้าย/เปลี่ยนชื่อ) (P3-11a, 7 ต.ค. 2026)
2. โปรเจกต์ Google Cloud ในบัญชีนี้ → OAuth client แบบ Desktop สำหรับ rclone, scope `drive.file`, consent screen production (กัน token หมดอายุ 7 วัน); **ตั้งแต่ปลาย ส.ค. 2026 Google ไม่ให้กด Publish app จนกว่าหน้า Branding จะมี homepage URL + privacy policy URL** — ใช้ `https://kemi-classroom.pages.dev` กับ `https://kemi-classroom.pages.dev/privacy` (หน้าจริงสร้างใน P7-06 ร่วมกับแอปล็อกอิน) และ Authorized domain `kemi-classroom.pages.dev`; ไม่ใส่โลโก้ (ใส่แล้วต้องส่งตรวจ); สถานะเป็น In production แบบไม่ผ่านการตรวจได้เพราะ `drive.file` ไม่ต้องตรวจ (ทำแล้ว 7 ต.ค. 2026 กับ dev)
3. `rclone config` บนเครื่องผู้พัฒนา: remote `gdrive` (drive, `drive.file`) → remote `gcrypt` (crypt ครอบ `gdrive:kemi-backup` เข้ารหัสชื่อไฟล์และเนื้อหา รหัส + salt ให้ rclone สุ่ม 256 บิต) และ remote `b2ro` (B2 ด้วยกุญแจอ่านอย่างเดียว — สคริปต์ใช้เป็นที่เก็บกุญแจให้ `aws s3api` ไม่ได้อ่าน B2 ผ่าน rclone ดูส่วน 8 ข้อ 5); ห้ามตั้งรหัสผ่านให้ไฟล์ config; เก็บทั้งไฟล์เป็น GitHub secret แล้วลบไฟล์ในเครื่อง; ขั้นตอนละเอียดอยู่ใน `ops/backup-setup.md`

**Healthchecks.io**

1. check `kemi-backup` รอบ 12 ชั่วโมง เผื่อ **6 ชั่วโมง** ส่งอีเมลถึงผู้พัฒนา (เดิม 3 ชม.; เพิ่ม 17 ต.ค. 2026 เพราะ GitHub เริ่มรอบตามตารางช้ากว่าเวลาที่ตั้ง 2.5–5.5 ชม. ช่วงห่างระหว่างรอบสำเร็จจึงยาวได้ถึงราว 17.5 ชม. ซึ่งเกินเส้น 15 ชม. แบบเดิม; ถ้าช้ากว่านี้จนเตือนผิดบ่อย ทางเลือกคือให้ `pg_cron` + `pg_net` เรียก `workflow_dispatch` ตรงเวลาแทน)
2. check `kemi-restore-test` **[ข้อเสนอ]** รอบ 35 วัน เพื่อเตือนเมื่อไม่ได้ทดสอบกู้คืนตามรอบเดือน

## 8. GitHub Actions

| workflow | เมื่อไร | ทำอะไร |
| --- | --- | --- |
| `ci.yml` | ทุก push/PR | ติดตั้ง, lint, typecheck, Vitest, build หน้าเว็บ; เมื่อแก้ `supabase/**` รัน pgTAP กับฐานข้อมูลชั่วคราวใน runner (Supabase CLI เปิด Postgres ใน Docker แล้วใส่ migration ของ commit นั้น) — ไม่ใช้ secret และไม่แตะ `kemi-dev` |
| `deploy-db.yml` | กดรันเอง (`workflow_dispatch`) เลือก dev/prod | `supabase db push` และ `supabase functions deploy`; รอบ dev รัน pgTAP กับ `kemi-dev` หลัง push (รวมข้อที่พึ่ง automatic RLS ซึ่งฐานข้อมูลใน runner ไม่มี); prod รันหลังผ่าน dev แล้วเท่านั้น และ**ห้ามรัน pgTAP กับ prod เด็ดขาด** (บางเทสต์แก้แถวจริงชั่วคราวใน transaction ที่ย้อนกลับ เช่นเทสต์ครูคนสุดท้าย) สคริปต์รันเทสต์ต้องตรวจ project ref ว่าเป็น `kemi-dev` หรือฐานข้อมูลในเครื่องก่อนรัน |
| `backup.yml` | `30 19 * * *`, `30 7 * * *` (02:30/14:30 น. ไทย) + กดรันเอง (input `simulate_failure` ไว้ทดสอบการล้ม) | สำรองตาม TECHNICAL_DESIGN ส่วน 12; GitHub สั่งรันด้วยมือได้เฉพาะ workflow ที่มีไฟล์บน branch หลัก จึงวางไฟล์แบบ `workflow_dispatch` อย่างเดียว (ไม่มีตารางเวลา) บน `main` ก่อน แล้วสั่ง `--ref phase-3` ซึ่งใช้ไฟล์ของ branch นั้น; ตารางเวลาเริ่มเมื่อ merge ระยะ 3 |
| `restore-test.yml` | กดรันเอง เลือกจุดกู้คืนและชุดไฟล์ | กู้เข้า Supabase ชั่วคราวใน runner + ไฟล์ใน `kemi-dev-files` แล้วตรวจ ลบทิ้ง และบันทึกผลลง prod |

ประมาณการนาที: สำรอง 2–4 นาทีต่อรอบ (วัด 7 ต.ค. 2026 กับ kemi-dev; repo private ปัดขึ้นเป็นนาทีเต็มต่อ job; ช้าสุดคือ `pg_dump` ผ่าน pooler 60–80 วินาที) × 60 รอบ ≈ 150–250 นาที/เดือน + CI ≈ 300–500 นาที + `restore-test` ~15 นาทีต่อครั้ง รวมต่ำกว่า 2,000 นาทีฟรีของ repo private

**ขั้นตอน `backup.yml`** (สคริปต์ `ops/backup.sh`, ทุกขั้นล้มเหลวแล้ว ping `/fail` และปลดล็อก ยกเว้นข้อ 8; ก่อนระยะ 7 สคริปต์เขียน project ref และ bucket ของ `kemi-dev` ตายไว้ project อื่นถูกกันก่อนต่อฐานข้อมูล `target_not_allowed`):

1. `concurrency: backup` (ไม่ยกเลิกรอบที่กำลังทำ); ตรวจว่ามี secret ครบ; ping `/start`; ติดตั้ง `postgresql-client` รุ่นหลักตรงกับเซิร์ฟเวอร์จาก PGDG และ rclone รุ่นที่ตรึงไว้พร้อมตรวจ SHA-256 (`aws` CLI มีใน runner อยู่แล้ว); **ห้ามตั้งตัวแปรสภาพแวดล้อมที่ขึ้นต้นด้วย `RCLONE_` เว้นแต่ตั้งใจให้เป็นค่าตั้งของ rclone** เพราะ rclone อ่านเป็นแฟล็ก (`RCLONE_VERSION` กลายเป็น `--version`, P3-11c)
2. psql เรียก `private.backup_start` (ตั้ง `maintenance_locks` หมดอายุ 2 ชม. + สร้าง `backup_runs` สถานะกำลังทำ ใน transaction เดียว; รอบค้างที่ธงหมดอายุแล้วถูกปิดเป็น failed) — ฟังก์ชันสำรองทุกตัวเรียกได้เฉพาะ postgres ผ่าน connection string เดียวกับ pg_dump จึงไม่ต้องมี service role key ใน GitHub; สคริปต์ตั้ง `trap` ให้เรียก `private.backup_release_lock` ทุกครั้งที่ออก เพราะจบรอบไม่ปลดธงเอง
3. เปิด session A ผ่าน Session pooler: `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT pg_export_snapshot();` แล้วใน session เดียวกันรัน `ops/manifest.sql` ซึ่งเรียกฟังก์ชันบันทึก manifest (ดึง asset สถานะ `ready` จาก snapshot นี้เอง ไม่ใช่ใน REPEATABLE READ ตอบ `snapshot_required`) แล้วอ่านรายการ `final_key`, `version_id`, ขนาด, checksum ออกมาเป็นไฟล์ manifest
4. session B: `pg_dump --snapshot=<id> --schema=public --schema=private --exclude-table-data=private.backup_manifests --exclude-table-data=private.backup_run_files` (manifest อัปโหลดเป็นไฟล์แยกอยู่แล้ว ไม่ต้องอยู่ใน dump) แยกไฟล์ schema และ data จากนั้น COMMIT session A — dump กับ manifest จึงมาจากจุดเดียวกัน **[ต้องพิสูจน์ผ่าน pooler]**
5. หาไฟล์ใหม่ = ไฟล์ในรอบนี้ที่ยังไม่เคยอยู่ในรอบสำเร็จใด (`backup_new_files`; ส่วนไฟล์ manifest ของรอบใช้ `backup_run_file_list` — ทั้งสองเรียกได้เฉพาะระหว่างรอบ ต้องเรียกก่อนจบรอบ) → **ข้ามไฟล์ใหม่ที่มีอยู่ใน `gcrypt:files` แล้วและขนาดตรง** (เหลือจากรอบที่ล้มหลังคัดลอก; ตรวจแบบเดียวกับไฟล์เดิมในข้อ 6 — เพิ่ม 7 ต.ค. 2026) → ดึงที่เหลือไฟล์ละ 1 GET ด้วย `aws s3api get-object --version-id` (endpoint S3 ของ B2, กุญแจจาก remote `b2ro`) ซึ่งอ่านเวอร์ชันที่บันทึกตรง ๆ และไม่มีคำขอ HEAD/List เพิ่มแบบ `rclone copy b2ro:` (**อ่านจาก B2 ครั้งเดียว** ตาม TECHNICAL_DESIGN 9.3; P3-11a) ตรวจขนาด/MD5 กับ manifest → `rclone copy ./new gcrypt: --no-traverse`; บันทึกไบต์/คำขอที่อ่านลงงบรายวันผ่าน psql ทั้งตอนสำเร็จและล้มเหลว
6. `rclone cryptcheck ./new gcrypt: --one-way` (ต้นทางเป็นสำเนาในเครื่อง ไม่อ่าน B2 ซ้ำ) + ตรวจการมีอยู่/ขนาดของทุกไฟล์ใน manifest จาก `rclone lsjson -R gcrypt:files`; ไฟล์ที่หายหรือขนาดไม่ตรงดึงตาม `version_id` ด้วยวิธีเดียวกับข้อ 5 แล้วคัดลอก + cryptcheck + ตรวจซ้ำ; ยังไม่ครบ = ล้มเหลว
7. อัปโหลด dump + manifest ไป `gcrypt:runs/<YYYYMMDDTHHMMSSZ>/` = `schema.dump`, `data.dump` (`pg_dump -Fc`), `manifest.csv`, `meta.json` (รอบ, snapshot, จำนวน, ขนาด, รุ่น Postgres — ไม่มีข้อมูลนักเรียน) แล้ว cryptcheck; ไฟล์อยู่ที่ `gcrypt:files/<asset_id>.<ext>` ตาม `final_key` → psql เรียกฟังก์ชันจบรอบสำเร็จพร้อมชื่อจุดกู้คืน จำนวน และขนาด (ไม่ตรงกับ manifest ตอบ `manifest_mismatch` = รอบล้มเหลว) → ping สำเร็จ; รอบที่ล้มหลังอัปโหลดแล้วลบ `runs/<เวลา>` ของรอบนั้นทิ้ง (ไฟล์ใน `files/` คงไว้ให้รอบถัดไปใช้ตามข้อ 5)
8. ล้าง dump/manifest ของรอบเก่ากว่า 7 วัน**ยกเว้นรอบสำเร็จล่าสุดเสมอ** และไฟล์จาก `backup_prune_candidates` (รอบสำเร็จล่าสุดที่เห็นไฟล์เก่ากว่า 8 วัน ไม่รวมไฟล์ในรอบสำเร็จล่าสุด) ด้วย `--drive-use-trash=false` เฉพาะในโฟลเดอร์สำรอง แล้วจึงส่งรายการที่ลบสำเร็จให้ `backup_prune_confirm` (ลบจาก Drive ก่อน ค่อยลบแถว); **ข้อนี้ล้มเหลวหลังจบรอบสำเร็จแล้ว:** workflow ล้มให้ GitHub ส่งอีเมล แต่ไม่ ping `/fail` และ `backup_runs` ยังเป็นสำเร็จ เพราะจุดกู้คืนของรอบนั้นใช้ได้ (ล้างไม่สำเร็จนาน ๆ ทำให้ Drive เต็ม จึงต้องแก้เมื่อได้อีเมล)
9. ปลดล็อก (`private.backup_release_lock` จาก trap ในข้อ 2) และเรียก `ping()` ผ่าน Data API ด้วย `SUPABASE_PING_KEY` (secret key แยกของงานนี้ เพราะ anon เรียกฟังก์ชันใดไม่ได้; ช่วยกันโปรเจกต์หลับ) — ไม่มี key หรือเรียกไม่สำเร็จขึ้นแค่คำเตือน ไม่ทำให้รอบล้ม; ยืนยันใน P3-11c ว่าเรียกสำเร็จจริงเมื่อใส่ key

**ตาราง manifest ในฐานข้อมูล (ตัดสิน 4 ต.ค. 2026 จากขนาดที่วัดใน P3-01c; ทำแล้วใน P3-01d วัดได้รวมประมาณ 9–19 MB ที่ 10,000–20,000 ไฟล์):** แบบแถวต่อไฟล์ต่อรอบใช้ประมาณ 468 ไบต์ต่อแถว เก็บ 16 รอบแล้วกิน 75–150 MB (15–30% ของ 500 MB ฟรี) จึงเปลี่ยนเป็น**ไฟล์ละแถว** เก็บ `final_key`, `version_id`, ขนาด, checksum, รอบสำเร็จแรกและรอบสำเร็จล่าสุดที่เห็นไฟล์ (ประมาณ 5–10 MB) ใช้ได้เพราะ `final_key` ไม่ถูกใช้ซ้ำและ asset ไม่ย้อนเป็น `ready` ไฟล์จึงอยู่ในรอบติดกันเสมอ; รายการของรอบที่กำลังทำเก็บชั่วคราวได้แต่ต้องล้างเมื่อจบรอบไม่ว่าผลใด; รอบแรก/ล่าสุดขยับเฉพาะตอนจบรอบสำเร็จ; รายการเต็มของแต่ละจุดกู้คืนอยู่ในไฟล์ manifest บน Drive ซึ่งเป็นสิ่งที่ `restore-test` และการกู้จริงใช้

**ขั้นตอน `restore-test.yml`** (สคริปต์ `ops/restore-test.sh`, input: จุดกู้คืน และ `files: sample|all`):

1. ติดตั้ง Supabase CLI แล้ว `supabase start` ใน runner (Postgres รุ่นหลักเดียวกับ prod) — ฐานข้อมูลนี้อยู่แค่ในงานนี้และถูกทิ้งเมื่อจบ
2. ดึง dump + manifest ของจุดที่เลือกจาก `gcrypt:` → restore schema แล้ว data → ตั้ง `accounts.auth_user_id` เป็น NULL
3. อัปโหลดไฟล์จาก manifest (`sample` = สุ่มประมาณ 50 ไฟล์สำหรับรอบรายเดือน, `all` = ทุกไฟล์ ใช้ก่อนเปิดใช้จริงเมื่อข้อมูลยังเล็ก) เข้า `final_key` เดิมใน `kemi-dev-files` เก็บ `version_id` ใหม่ → อัปเดตในฐานข้อมูลชั่วคราวตาม TECHNICAL_DESIGN ส่วน 12 ตรวจขนาด/checksum
4. ตรวจยอดแถวหลัก ยอดโทเคน owned_charms และสร้าง presigned GET ของไฟล์ที่กู้แล้วดาวน์โหลดเทียบ checksum
5. ลบไฟล์ที่อัปโหลดในข้อ 3 จาก `kemi-dev-files` โดยระบุ `version_id` (ทำแม้ขั้นก่อนหน้าล้มเหลว) และหยุด `supabase stop`
6. บันทึกผล (ผ่าน/ไม่ผ่าน จุดกู้คืน จำนวนไฟล์ที่ตรวจ) ลง `backup_runs` ของ prod เป็นชนิด `restore_test` ด้วย psql เรียก `private.backup_record_restore_test` (บันทึกครั้งเดียวตอนจบ) เพื่อแสดง “ทดสอบกู้คืนล่าสุด” ใน D01 แล้ว ping `kemi-restore-test`

**งาน `guard`** (อยู่ใน `backup.yml` แยก job): ตรวจว่า `private.settings` ของ prod ไม่มี `allow_test_logins = on` ถ้ามีให้ job นี้ล้มเหลวเพื่อให้ GitHub ส่งอีเมล โดยงานสำรองยังทำต่อตามปกติ

## 9. การทดสอบ

| ชั้น | เครื่องมือ | ครอบคลุม |
| --- | --- | --- |
| หน่วย | Vitest | สูตรคะแนนชุดตัวอย่างเดียวกับฐานข้อมูล (ไฟล์ JSON ร่วม), การแปลงเวลาไทย, ชื่อปิดบางส่วน, ตรวจไฟล์ก่อนอัปโหลด, ชื่อไฟล์ PDF, CSV |
| ฐานข้อมูล | pgTAP บน Supabase ในเครื่อง (Docker) เป็นหลัก และกับ `kemi-dev` ผ่าน `supabase db query --linked` ทุกไฟล์รูปแบบ `begin; create extension if not exists pgtap …; … rollback;`; CI รันชุดเดียวกันในฐานข้อมูลชั่วคราวใน runner (ส่วน 8) | ตารางสิทธิ์ทุกบทบาท (นักเรียน/ครู/ผู้ดูแลในและนอกโหมด/anon), ทุก RPC ตามกติกา, ตารางรับการส่ง 7 แถว, I1–I5, K1–K6, L2–L6 |
| พร้อมกัน | สคริปต์ Node เปิดหลาย connection | ชิงชื่อเดียวกัน, สุ่มสองแท็บ, ตรวจซ้ำพร้อมกัน, ตรวจชนเริ่มเทอม, แก้รางวัลชนส่งแรก |
| หน้าเว็บ | Playwright (มือถือ 390 px, แท็บเล็ต 820 × 1180 และ 1180 × 820 แบบสัมผัส, คอม 1280 px) | เส้นทางหลักทุกบทบาทบน preview ของ dev |
| อุปกรณ์จริง | ทดสอบมือ | iPhone Safari (HEIC), Android Chrome, iPad, มือถือรุ่นเก่าหน่วยความจำน้อย, Wi-Fi โรงเรียน |
| ภาระ | สคริปต์ส่งงาน | 40 คนส่งภายใน 5 นาที และล็อกอินต่อเนื่องทั้งห้อง บน dev |

- จำลองผู้ใช้ใน pgTAP ด้วย `set local role authenticated` + `set local request.jwt.claims` และสร้างแถว `auth.users`/`auth.identities` ของ provider `google` ในข้อมูลทดสอบ
- Playwright ล็อกอินด้วย Google อัตโนมัติไม่ได้ **[ข้อเสนอ]** บน `kemi-dev` เท่านั้นเปิด Email/Password ให้บัญชีทดสอบ และ `ensure_account()` ยอมรับ provider `email` เฉพาะเมื่อตาราง `private.settings` มี `allow_test_logins = on` และบัญชีแบบนี้เป็นครูได้ด้วย `provider_subject` เท่านั้น ไม่จับคู่ด้วยอีเมล (ใช้ตารางแทนค่าตั้งของฐานข้อมูล เพราะ Supabase อาจไม่ให้ `ALTER DATABASE … SET`); งาน `guard` ตรวจค่านี้บน prod ทุกรอบสำรอง และตรวจ Email provider ด้วยมือในรายการส่วน 11
- ใช้ชุดสูตรคะแนนเดียวกันทั้ง Vitest และ pgTAP เช่น (7, 50%) → 4, (9, 50%) → 5, (7, 30%) → 5, (7, 20% รายคน) → 6, (7, 0%) → 7, (149, 50%, เต็ม 150) → 75

## 10. แผนงานรายระยะ

### ระยะ 0 — เตรียมบริการ

งาน: เปิดบัญชี GitHub, Supabase (2 โปรเจกต์), Google Cloud, Backblaze, Cloudflare, บัญชี Google สำรอง, Healthchecks.io ตามส่วน 7 พร้อมยืนยันสองขั้น; ตรวจหน้าราคา/โควตาทางการอีกครั้ง

ตรวจรับ:
- [ ] ผลตรวจตอนสมัครข้อ 1–8 ของ SYSTEM_SPEC ส่วน 12 บันทึกลงเอกสารพร้อมวันที่ (ข้อที่ยังทดสอบไม่ได้ระบุระยะที่จะทดสอบ)
- [ ] ไม่มีบริการใดเปิด billing หรือผูกแพ็กเกจเสียเงิน; B2 ตั้ง caps แล้ว
- [ ] รายการบัญชี กุญแจ และ recovery codes อยู่ในตัวจัดการรหัสผ่าน

### ระยะ 1 — โครงระบบและล็อกอิน

งาน: สร้างโปรเจกต์ Vite + React + TS, tokens และคอมโพเนนต์พื้นฐานจากแบบ v2, Pages + `_headers`, `ci.yml`, migration 1–2, ตั้ง Auth, หน้า A01 + callback + แยกหน้าตามบทบาท (ยังเป็นหน้าว่าง)

ตรวจรับ:
- [ ] เปิด `https://<ชื่อ>.pages.dev` ล็อกอิน Google ได้ทั้งมือถือและคอม; บัญชีใน allowlist เข้าหน้าครู บัญชีอื่นเข้าแบบนักเรียน
- [ ] เรียก REST ด้วย anon key อ่าน/เขียนตารางใดไม่ได้; ฟังก์ชันไม่มีสิทธิ์ execute สำหรับ `anon`
- [ ] แก้ `user_metadata` ของตัวเองแล้วไม่ได้สิทธิ์ครู
- [ ] ผู้ใช้ทดสอบบัญชี Google ของโรงเรียน (จุดสาธิต 1) และบันทึกผล
- [ ] Security Advisor ไม่มีรายการระดับ error

### ระยะ 2 — บัญชี รายชื่อ ห้อง

งาน: migration กลุ่ม roster, identity, classrooms; นำเข้า Excel (ตัวอย่างก่อนบันทึก ตรวจซ้ำ ศูนย์นำหน้า); A02 (L3); A01 แบบมาจากลิงก์เชิญ + `/join/:code`; S01 + เข้าห้องด้วยรหัส; S06; T01, T09, T08 (แท็บสมาชิก + คัดลอกลิงก์เชิญ **[ข้อเสนอ]**), T10, T05 (แก้ผูก), T12; D01 ส่วนบัญชีครู + โหมดผู้ดูแล (L6)

ตรวจรับ:
- [ ] ค้นด้วยชื่อบางส่วนไม่เจอ ค้นเลขเต็ม/ชื่อเต็มเจอเป็นชื่อปิดบางส่วน + ห้อง + เลขที่; ค้นครั้งที่ 11 ใน 10 นาทีถูกปฏิเสธ (L3)
- [ ] สองบัญชียืนยันชื่อเดียวกันพร้อมกัน สำเร็จบัญชีเดียว
- [ ] แก้ผูกแล้วแท็บของบัญชีเดิมทำคำสั่งถัดไปไม่ได้
- [ ] ครูเอานักเรียนออกแล้ว นักเรียนเปิดห้องหรือเรียก RPC ของห้องนั้นไม่ได้ (`not_member`) ข้อมูลเดิมยังอยู่ และเข้าใหม่ด้วยรหัสแล้วเห็นเหมือนเดิม
- [ ] เข้าห้องได้ทั้งด้วยรหัสและลิงก์เชิญ (ลิงก์เชิญยังต้องล็อกอินและเลือกชื่อก่อน); รหัสห้องผิดซ้ำถูกจำกัด; ปิดการเข้าห้องแล้วเข้าไม่ได้ทั้งรหัสและลิงก์แต่สมาชิกเดิมใช้ต่อได้; กดเข้าซ้ำไม่เกิดสมาชิกซ้ำ
- [ ] เอาบัญชีครูรายการสุดท้ายออกไม่ได้; โหมดผู้ดูแลมีแถบเตือนทุกหน้า และ RPC ฝั่งครูที่ผู้ดูแลเรียกโดยไม่ส่งโหมดถูกปฏิเสธ (L6)
- [ ] ตัวอ่านอ่านไฟล์ Excel จริงของครูทั้ง 3 ห้องได้ครบ (ได้ไฟล์แล้ว 2 ต.ค. 2026) โดยทดสอบแบบอ่านอย่างเดียวบนเครื่องผู้พัฒนา ไฟล์อยู่นอก repo หรือใน `.work/` ไม่ส่งข้อมูลขึ้นเซิร์ฟเวอร์ใด และรายงานแค่จำนวนแถวกับจำนวนปัญหา ไม่พิมพ์ชื่อหรือเลขประจำตัว; นำเข้าจริงทำบน prod ในระยะ 8 เท่านั้น

### ระยะ 3 — งานและไฟล์

งาน: migration กลุ่ม posts_files, submissions; Edge Functions `uploads`, `files` และ `process-jobs` ขั้นต่ำ (ลบไฟล์ที่ถูกแทน, sweeper `copying`, batch ค้าง และ asset ที่ไม่มีแถวผูกแล้ว) พร้อม `pg_cron`; ตั้ง CORS/lifecycle/keys ของ B2; โมดูลอัปโหลด; T02 (K1: คะแนนเต็มจำนวนเต็ม ≥ 1 ไม่มีเพดาน 100, ปุ่มตัวห้อย/ตัวยก, รายละเอียด/ไฟล์ไม่บังคับ) + โหมดแก้ไข (N2, N1), S02, S03 (ไฟล์โจทย์เปิดดู/ดาวน์โหลด, ส่ง/ส่งแก้/สถานะ), T08 รายการงาน, T03 รายการสถานะ + การ์ดโจทย์และไฟล์ + ตัวดูไฟล์เบื้องต้น; ระบบนับพื้นที่ + แถบพื้นที่เต็ม; **ตั้ง `backup.yml` แบบพื้นฐานกับ dev** (ใช้ `maintenance_locks` จาก `0001_base` และ `backup_runs` จากกลุ่ม posts_files)

ตรวจรับ:
- [ ] PUT ที่ขนาดไม่ตรงลายเซ็นถูก B2 ปฏิเสธ; ไฟล์ที่ magic number ไม่ใช่ JPEG/PNG/PDF ถูกปฏิเสธตอน complete
- [ ] หลัง complete แล้วใช้ลิงก์เดิมอัปทับ staging ไฟล์ที่ระบบใช้ไม่เปลี่ยน (ตรวจ `version_id`)
- [ ] นักเรียนที่เป็นสมาชิกเปิดดูและดาวน์โหลดไฟล์โจทย์ได้ ชื่อไฟล์ภาษาไทยถูกต้องบนมือถือ แท็บเล็ต และคอม; คนที่ไม่ใช่สมาชิกห้องขอลิงก์ไม่ได้
- [ ] ขอลิงก์เปิดไฟล์ของนักเรียนคนอื่นได้ 403; เปิด URL ของ B2 โดยไม่มีลายเซ็นไม่ได้; เรียกจาก origin อื่นถูก CORS ปฏิเสธ
- [ ] สร้างการบ้านโดยไม่มีรายละเอียดและไฟล์ได้; แก้ชื่อ/รายละเอียด/ไฟล์หลังมีคนส่งได้ ไม่มีแจ้งเตือน นักเรียนเห็น “แก้ไขล่าสุด” และไฟล์ที่เอาออกเข้าคิวลบ; ช่องที่ล็อก (N2) แก้ผ่าน RPC ไม่ได้
- [ ] ตารางรับการส่งทั้ง 7 แถวผ่าน pgTAP; ส่งแก้ล้มเหลวชุดเดิมและเวลาเดิมอยู่ครบ
- [ ] ส่งแก้โดยเก็บรูปเดิม 2 รูปเปลี่ยนรูปที่ 3: ไม่อัปโหลด 2 รูปเดิมซ้ำ และลบเฉพาะรูปที่ถูกแทน (ระบุเวอร์ชัน)
- [ ] ตั้ง quota ต่ำบน dev: อัปโหลดใหม่ถูกหยุดพร้อมข้อความ J10.3 แต่ดู/ตรวจงานได้
- [ ] `backup.yml` กับ dev: รอบแรกสำเร็จ (dump + manifest + ไฟล์อยู่ใน Drive แบบเข้ารหัส, `pg_dump --snapshot` ผ่าน pooler = ส่วน 13 ข้อ 12); รอบสองไม่อ่าน B2 ซ้ำ; รอบล้มโดยตั้งใจได้อีเมล Healthchecks.io (ข้อ 5) และธง `maintenance_locks` ถูกปลด; `ping()` ผ่าน Data API สำเร็จ
- [ ] ตั้งงบดาวน์โหลดรายวันต่ำบน dev: เปิดดูไฟล์ถูกหยุดพร้อมข้อความ `download_budget_reached` แต่การส่งงานยังผ่าน; เปิดไฟล์เดิมซ้ำภายใน 10 นาทีไม่เพิ่มตัวนับและไม่โหลดจาก B2 ซ้ำ (ดูแท็บ Network); complete ใช้คำขอ B2 ครั้งเดียวต่อไฟล์
- [ ] จุดสาธิต 2: จดตัวเลขจากหน้า Caps & Alerts ของ B2 หลังวันใช้งานจริง เทียบกับตัวนับในฐานข้อมูล แล้วปรับงบใน TECHNICAL_DESIGN 9.3
- [ ] อุปกรณ์จริง: HEIC จาก iPhone, รูปต้นฉบับเกิน 20 MB ถูกปฏิเสธก่อนย่อแต่รูปที่ไม่เกินผ่าน, ตัวห้อย/ตัวยกอ่านชัดหลังย่อ, วัดเวลาอัปโหลดผ่าน Wi-Fi โรงเรียน (จุดสาธิต 2)

### ระยะ 4 — ตรวจงานและคะแนน

งาน: migration กลุ่ม grading; T03 หน้าตรวจ (ตัวดูรูป/PDF, ซูม, หมุน, ดาวน์โหลด PDF), แผงคะแนน (L2, L4, K2), สิทธิ์แก้ (K3), ความคิดเห็น + ยกเลิก, M1 เปลี่ยนกำหนดส่งสองทิศ (N3), M2 ปิดรับ, M3 เฉลย (K4), ลบงาน/ประกาศ (N4), T04 + CSV, หน้าผลตรวจ/เฉลยของนักเรียน; ตัวดูไฟล์ทำตาม TECHNICAL_DESIGN 9.3 (โหลดเฉพาะไฟล์ที่กำลังดู ใช้ลิงก์ในแคช ไม่โหลดรูปย่อจาก B2)

**ขอบเขตกับระยะถัดไป (ตัดสิน 11 ต.ค. 2026):** ระยะ 4 ยังไม่มีกระเป๋าโทเคน (ระยะ 5) และงานเตือน 24 ชม. (ระยะ 6) — `grade_submission` ของระยะ 4 บันทึกผลตรวจอย่างเดียว ไม่ให้โทเคนและไม่แตะ `reward_granted`; ระยะ 5 เพิ่มขั้นให้รางวัล (TECHNICAL_DESIGN ส่วน 6 ข้อ 6–7) ในฟังก์ชันเดิมให้อยู่ใน transaction เดียวกัน ดังนั้นโครงฟังก์ชันต้องมีจุดต่อขั้นนี้ชัดเจน; ส่วนโทเคนและงานเตือนของข้อตรวจรับด้านล่างย้ายไปตรวจในระยะ 5 และ 6

ตรวจรับ:
- [ ] ชุดสูตรคะแนนในส่วน 9 ผ่านทั้งหน้าเว็บและฐานข้อมูล; คะแนนเกินเต็มถูกปฏิเสธ; คะแนนเต็ม 150 ใช้ได้ (K1)
- [ ] บันทึกเฉพาะผ่านไม่ล็อก; บันทึกคะแนนแรกล็อกคะแนนเต็มและ % หัก และแก้ผ่าน `update_assignment` ไม่ได้ (L4, K2)
- [ ] ปรับหักรายคนไม่มีเหตุผลบันทึกไม่ได้; เหตุผลขึ้นในความคิดเห็นที่นักเรียนเห็น; 0% = ยกเว้น (L2, J3)
- [ ] สิทธิ์แก้: ส่งล้มเหลวไม่ใช้สิทธิ์ ส่งสำเร็จใช้ครั้งเดียว ครั้งถัดไปต้องเปิดใหม่ (K3)
- [ ] แก้เฉลยหลังเผยแพร่: `published_at` คงเดิม แสดงเวลาแก้ล่าสุด คะแนนและ `first_after_solution` ไม่เปลี่ยน (K4; ส่วนโทเคนตรวจในระยะ 5)
- [ ] I1 ไม่หักเพราะเวลาส่งแก้, I2 ขยายกำหนดไม่เขียนทับผลเดิม, เปลี่ยนผลผ่าน→ไม่ผ่านได้ (I3 เรื่องไม่ถอนโทเคนตรวจในระยะ 5)
- [ ] N3: เลื่อนกำหนดเร็วขึ้นแล้วงานที่ยังไม่ตรวจซึ่งส่งหลังกำหนดใหม่กลายเป็นสาย งานที่ตรวจแล้วคงผลเดิม หน้าต่างแสดงรายชื่อทั้งสองทิศก่อนบันทึก (โทเคนตรวจในระยะ 5, งานเตือน 24 ชม. ในระยะ 6)
- [ ] N4: ลบการบ้านที่มีงานส่ง คะแนน และความคิดเห็นแล้ว ข้อมูลที่เกี่ยวข้องหายครบใน transaction เดียว ไฟล์ B2 เข้าคิวลบ จำนวนที่หน้าเว็บส่งมาไม่ตรงได้ conflict; ลบประกาศได้
- [ ] ครูบันทึกผลบนไฟล์รุ่นเก่าขณะนักเรียนส่งใหม่ ได้ conflict แล้วโหลดใหม่
- [ ] CSV เปิดใน Excel ภาษาไทยถูก; PDF รวมทุกหน้าตามลำดับ ชื่อ `12_ธนภัทร_ใจดี.pdf`

### ระยะ 5 — รางวัลและสะสม

งาน: migration กลุ่ม rewards, terms; ให้รางวัลใน transaction เดียวกับผลตรวจ, เอฟเฟกต์เมื่อได้รับโทเคนแสดงครั้งเดียวเมื่อกลับมา (`reward_effect_seen`), ปรับยอด, S04 (อัตราจริง), สุ่ม + เอฟเฟกต์, S05, สวมใส่ + แสดงในแท็บสมาชิก, T06 (อัตรารวม 100, อัปโหลดรูปเครื่องราง), T07 เริ่ม/จบภาคเรียน

ตรวจรับ:
- [ ] เอฟเฟกต์ได้รับโทเคนแสดงครั้งเดียว ไม่มีรายการในกระดิ่ง
- [ ] ตรวจซ้ำ/พร้อมกันให้โทเคนครั้งเดียว; ผ่าน→ไม่ผ่าน→ผ่านไม่ได้ซ้ำ; ส่งช้าไม่ได้โทเคน; งานเทอมเก่าไม่ให้โทเคนเข้าเทอมใหม่ (I5)
- [ ] สุ่มสองแท็บพร้อมกันมี 1 โทเคน สำเร็จครั้งเดียว ยอดไม่ติดลบ; ไม่มีของซ้ำ
- [ ] ชิ้นที่ยังไม่มีในระดับเดียวกันโอกาสเท่ากัน (ทดสอบสถิติบน dev); ครบทุกชิ้น = completed; เหลือแต่น้ำหนัก 0 = unavailable ไม่หักโทเคน (K6)
- [ ] จบภาคเรียน: นักเรียนส่งงาน/ความคิดเห็นไม่ได้ (ปฏิเสธที่เซิร์ฟเวอร์) แต่สุ่มได้; ครูตรวจและเขียนความคิดเห็นได้; งานเข้าเกณฑ์ยังได้โทเคน (K5)
- [ ] เริ่มภาคเรียนใหม่ล้างยอดทุกห้องพร้อมกัน คง owned_charms; กดซ้ำคืนผลเดิม; ตรวจงานชนการเริ่มเทอมไม่ทำให้ยอดผิด
- [ ] ส่วนโทเคนที่ย้ายมาจากระยะ 4: เปลี่ยนผลผ่าน→ไม่ผ่านไม่ถอนโทเคน (I3); แก้เฉลยหลังเผยแพร่โทเคนไม่เปลี่ยน (K4); เลื่อนกำหนดส่งแล้วงานที่ตรวจแล้วคงโทเคน (N3); ลบการบ้านที่ให้โทเคนไปแล้ว ยอดโทเคนคงเดิม (N4)

### ระยะ 6 — แจ้งเตือนและงานเบื้องหลัง

งาน: migration กลุ่ม notifications, retention; เพิ่มงานใน `process-jobs`: เตือน 24 ชม. (J7, L5), สร้างแจ้งเตือน (นักเรียน 5 / ครู 3 เหตุการณ์, dedupe), เทียบยอดพื้นที่ B2 รายวัน, เกณฑ์ 80/90/100%, เทอมเปิดเกิน 6 เดือน, เสนอลบตามอายุ; C01, T11, แผงพื้นที่และรายการงานเบื้องหลังที่ล้มเหลวใน D01, แถวข้อมูลเก่าใน T07 + ZIP + ยืนยันลบ + ลบก่อนกำหนด (J10.4)

ตรวจรับ:
- [ ] เตือนเฉพาะคนยังไม่ส่ง 24 ชม. ก่อนกำหนด ครั้งเดียว; โพสต์เมื่อเหลือไม่ถึง 24 ชม. ไม่มีเตือน; ขยายจากเหลือ 10 ชม. เป็น 3 วันได้เตือน 1 ครั้ง; เคยเตือนแล้วขยายอีกไม่เตือนซ้ำ (L5); เลื่อนกำหนดเร็วขึ้นหรือปิดรับแล้วงานเตือนถูกจัดใหม่หรือยกเลิกถูกต้อง (N3 ส่วนที่ย้ายมาจากระยะ 4)
- [ ] แจ้งเตือนไม่เก็บเนื้อความคิดเห็น; ความคิดเห็นที่ยกเลิกแล้วเปิดจากกระดิ่งเห็น “ข้อความนี้ถูกยกเลิก”
- [ ] เรียก `process-jobs` ซ้อนกันไม่ทำงานซ้ำ; มี `maintenance_locks` แล้วงานลบรอ
- [ ] เกณฑ์พื้นที่แจ้งครั้งเดียวต่อระดับ; ยอด B2 จริงลดลงหลังลบ (ตรวจวันถัดไป)
- [ ] ZIP ของภาคเรียนทดสอบมีไฟล์ครบตาม `manifest.csv`; ยืนยันลบด้วยจำนวน/ไบต์ไม่ตรงถูกปฏิเสธ

### ระยะ 7 — สำรองและความพร้อม

งาน: `backup.yml` ฉบับเต็ม + job `guard` + `restore-test.yml`; แผงสำรองและ “ทดสอบกู้คืนล่าสุด” ใน D01 จาก `backup_runs`; รายการความปลอดภัยส่วน 11; ทดสอบภาระ; ทดสอบอุปกรณ์และการเข้าถึง; เตรียม prod (migration, seed, allowlist ครู, storage settings, caps, bucket `kemi-files` + กุญแจ B2 ของ prod แบบสิทธิ์แคบผ่าน API, redirect, CORS เฉพาะโดเมนจริง); ชื่อภาคเรียนแรกใน seed ของ prod ตั้งตามภาคเรียนจริงตอนเปิดใช้ (ถามครู); สลับตัวแปร Production ของ Pages เป็น `kemi-prod` พร้อม `VITE_DEPLOY_ENV=prod` แล้ว deploy ใหม่ และเอาโดเมน production ออกจาก Redirect URLs ของ `kemi-dev`; สลับ `backup.yml` ไป prod (ตัวกันในสคริปต์, secret ชุด prod, กุญแจอ่านอย่างเดียวของ `kemi-files`) **ห้ามให้สำรอง dev กับ prod ปนในโฟลเดอร์ Drive เดียวกัน** (ใช้ remote crypt ใหม่ที่ชี้โฟลเดอร์ใหม่ หรือ purge สำรอง dev ก่อนรอบแรกของ prod) แล้วหยุดสำรอง dev เพราะใช้เพดานรายวันของ B2 ก้อนเดียวกับ prod

ตรวจรับ:
- [ ] สำรองสำเร็จต่อเนื่อง 6 รอบ; ลองทำให้งานไม่รันแล้วได้อีเมลจาก Healthchecks.io
- [ ] `restore-test` แบบ `all` ผ่าน รวมจับคู่ `version_id` ใหม่ ไฟล์ทดสอบถูกลบหลังจบ และ D01 แสดงผลรอบล่าสุด; เปิดไฟล์ที่กู้ผ่านหน้าตรวจ/หน้างานนักเรียน/ดาวน์โหลด PDF บน dev ด้วยชุดข้อมูลทดสอบได้
- [ ] `https://<ชื่อ>.pages.dev` ไม่มีแถบ “ระบบทดสอบ”, CSP `connect-src` ใน header ชี้ `kemi-prod` และ Redirect URLs ของ `kemi-dev` ไม่มีโดเมน production แล้ว
- [ ] ผ่านทุกข้อในส่วน 11 และรายการ “พร้อมนำร่อง” ของ DEVELOPMENT_PLAN ส่วน 5 (จุดสาธิต 4)

### ระยะ 8 — นำร่องและเปิดใช้

งาน: นำเข้ารายชื่อห้องนำร่องบน prod; ครูสร้างห้องและโพสต์การบ้านจริง 1–2 ชิ้น; ติดตามรายวัน (งานล้มเหลว เวลาอัปโหลด ขนาดรูปเฉลี่ย พื้นที่ที่โต); แก้ปัญหา; บันทึกขนาดรูปจริงลง SYSTEM_SPEC ส่วน 11 (2.3); ประชุมตัดสินใจ; นำเข้าอีก 2 ห้อง

ตรวจรับ:
- [ ] ครูและผู้พัฒนาร่วมยืนยันตามเกณฑ์ข้อ 65 และบันทึกผลใน SYSTEM_SPEC
- [ ] ประมาณการพื้นที่ต่อภาคเรียนจากข้อมูลจริงยังอยู่ในเกณฑ์ J10

## 11. รายการตรวจความปลอดภัยก่อนนำร่อง

- [ ] ทุกตารางใน `public` เปิด RLS (`select … from pg_tables where schemaname = 'public' and not rowsecurity` ต้องว่าง)
- [ ] ไม่มีฟังก์ชันที่ `anon` หรือ `PUBLIC` execute ได้; ทุก `SECURITY DEFINER` มี `search_path` ตั้งไว้ (ตรวจ `pg_proc.proconfig`)
- [ ] ฟังก์ชันที่ `authenticated` execute ได้ตรงกับรายการที่ตั้งใจไว้ทุกตัว (RPC ตามสัญญา API ใน TECHNICAL_DESIGN ส่วน 10 + ฟังก์ชันช่วยที่ policy เรียก) โดยมี pgTAP เทียบรายการนี้และล้มเมื่อมีตัวเกิน; คำเตือน (WARN) ของ Security Advisor ว่า `SECURITY DEFINER` ถูกเรียกได้โดยผู้ใช้ที่ล็อกอิน เป็นเรื่องปกติเฉพาะฟังก์ชันในรายการนี้ ถ้าขึ้นกับตัวอื่นถือเป็นข้อบกพร่อง
- [ ] ไม่มีการตัดสินสิทธิ์จาก `user_metadata`; ทุก RPC อ่านบทบาทจากฐานข้อมูลสด
- [ ] ทดสอบข้ามคน: นักเรียน A เปิดงาน คะแนน ความคิดเห็น ไฟล์ ตู้สะสม ของ B ไม่ได้; บัญชีที่ไม่อยู่ใน allowlist เรียกคำสั่งฝั่งครูไม่ได้; ผู้ดูแลนอกโหมดผู้ดูแลแก้ข้อมูลครูไม่ได้
- [ ] Edge Functions ตรวจ JWT และ CORS เฉพาะโดเมนเรา; `process-jobs` ปฏิเสธคำขอที่ไม่มีรหัสลับ
- [ ] bucket เป็น private; ไม่มีกุญแจ B2/ service role ในไฟล์ build (ค้นใน `dist`)
- [ ] CSP ทำงานและไม่มีสคริปต์ภายนอก; ฟอนต์โฮสต์เอง
- [ ] log ของ Edge Functions/Actions ไม่มีเนื้อความคิดเห็น ชื่อไฟล์นักเรียน หรือโทเคน; ping ของ Healthchecks.io ไม่แนบข้อมูล
- [ ] สำรองใน Drive เข้ารหัส โฟลเดอร์ไม่แชร์; restore ด้วยรหัสจากสำเนาออฟไลน์ได้
- [ ] rate limit ของ Auth, ค้นรายชื่อ, รหัสห้อง และขอ upload batch ทำงาน
- [ ] prod: Email provider ปิด และ `app.allow_test_logins` ไม่ได้เปิด

## 12. เกณฑ์ “เสร็จ” ของแต่ละงาน

1. โค้ด + migration + สิทธิ์ (RLS/GRANT) + การทดสอบที่เกี่ยวข้องผ่านใน CI
2. ข้อความและสถานะบนหน้าจอตรง UX_DESIGN/แบบ v2 หรือบันทึกความต่างไว้เป็นข้อเสนอให้ครูดู
3. ทดสอบบนจอมือถือ 390 px แท็บเล็ต 820 px (แนวตั้ง) และ 1180 px (แนวนอน) และคอม 1280 px ไม่มีข้อผิดพลาด JavaScript
4. ถ้าพบว่ากติกาไม่พอหรือขัดกัน ให้หยุดส่วนนั้นแล้วถามผู้ใช้ และแก้ SYSTEM_SPEC ก่อนแก้โค้ด
5. deploy ขึ้น dev แล้วลองผ่านหน้าเว็บจริงอย่างน้อยหนึ่งรอบ

## 13. เรื่องที่ต้องพิสูจน์กับบริการจริง

| # | เรื่อง | ทดสอบในระยะ | ถ้าไม่ผ่าน |
| --- | --- | --- | --- |
| 1 | B2 ต้องผูกบัตรไหม และ caps ตั้งที่ปริมาณฟรีได้ (ตรวจตอนสมัครข้อ 1) — **ตั้งแล้ว 5 ต.ค. 2026:** caps ทั้ง 4 ชนิดเป็น $0 (ผู้ใช้ไม่ได้แจ้งว่าถูกขอบัตร); ปริมาณฟรีจริงเป็นรายวัน ดูข้อ 19 และ TECHNICAL_DESIGN 9.3 | 0 | ทบทวนแผนเก็บไฟล์กับผู้ใช้ก่อนทำต่อ |
| 2 | `pg_cron` + `pg_net` ใช้ในแผนฟรีได้ (ข้อ 2, 8) — **พิสูจน์แล้ว 6 ต.ค. 2026** บน kemi-dev (`pg_cron` 1.6.4, `pg_net` 0.20.4, Vault มีแล้ว) cron ลบไฟล์จริงสำเร็จ | 0 | ให้ GitHub Actions เรียก `process-jobs` แทน |
| 3 | บัญชี Google ของโรงเรียนล็อกอินได้ (ข้อ 3) | 1 | ใช้บัญชีส่วนตัว หรือขอโรงเรียนอนุญาต |
| 4 | Supabase ใช้ฟรีโดยไม่ผูกบัตร (ข้อ 4) | 0 | — |
| 5 | Healthchecks.io ส่งอีเมลจริง (ข้อ 5) — **ส่วน /fail พิสูจน์แล้ว 7 ต.ค. 2026 (P3-11c):** รอบ `simulate_failure` ได้อีเมล DOWN และรอบปกติถัดมาได้อีเมล UP; **ส่วนงานไม่รันตามเวลาผ่านแล้ว:** ได้อีเมล “DOWN | kemi-backup” 01:27 น. 8 ต.ค. 2026 (success signal did not arrive on time, grace time passed) ≈ 15 ชม. หลังรอบสุดท้าย — **ผ่านครบทั้งสองกรณี** | 3, 7 | เปลี่ยนช่องทางแจ้ง |
| 6 | Lifecycle rules แยก `files/` กับ `staging/` ได้ตามส่วน 7 (ข้อ 6) — **พิสูจน์แล้ว 5 ต.ค. 2026** (`apply-settings.mjs` อ่านกลับตรง) | 0, 3 | ใช้งานลบตามรอบใน `process-jobs` เป็นหลัก |
| 7 | CORS, ลายเซ็น `content-length`, CopyObject ระบุเวอร์ชันต้นทาง, เพดานดาวน์โหลดเดือนแรก (ข้อ 7) — **พิสูจน์แล้ว 5 ต.ค. 2026:** CORS และลายเซ็น `content-length`/`content-type` (ขนาดเกิน 1 ไบต์ หรือชนิดต่าง → 403) ผ่าน; CopyObject ระบุเวอร์ชันต้นทางได้ (อัปทับไฟล์พักก่อน complete แล้วไฟล์จริงยังเป็นเนื้อเวอร์ชันที่ตรวจ) และ `REPLACE` ตั้งชนิดไฟล์ได้; อัปทับไฟล์พักหลัง complete ไม่กระทบไฟล์ใน `files/` (`proof-complete.mjs` 16/16); เรื่องเพดานดาวน์โหลดย้ายไปข้อ 19 | 3 | ตรวจขนาดตอน complete อย่างเดียว / ดาวน์โหลดแล้วอัปโหลดแทนการคัดลอก / ปรับเพดาน |
| 8 | เวอร์ชัน Postgres, ต่อ Session pooler จาก Actions, rate limit ของ Auth (ข้อ 8) | 1, 3, 7 | ปรับวิธี dump / ปรับค่าใน Dashboard |
| 9 | ชนิดของ ETag ที่ B2 ส่งกลับ (ใช้เป็น checksum) — **พิสูจน์แล้ว 5 ต.ค. 2026:** PUT ชิ้นเดียวได้ ETag = MD5 hex ของเนื้อไฟล์ (ในเครื่องหมายคำพูด) GET ส่งค่าเดียวกัน; ETag ของ CopyObject เท่ากับ MD5 ของไฟล์และตรงกับที่ GET ส่งกลับ (5 ต.ค. 2026) | 3 | ใช้ขนาด + `cryptcheck` เป็นหลัก |
| 10 | `response-content-type` / `response-content-disposition` บน presigned GET ของ B2 — **พิสูจน์แล้ว 5 ต.ค. 2026** รวมชื่อไฟล์ไทยแบบ `filename*=UTF-8''…` | 3–4 | ตั้งชื่อไฟล์ฝั่งหน้าเว็บด้วย Blob |
| 11 | Safari บน iPhone แปลง HEIC เป็น JPEG เองเมื่อเลือกไฟล์ | 3 | โหลดตัวถอด HEIC ตามแผน |
| 12 | `pg_dump --snapshot` ผ่าน Session pooler — **ผ่านแล้ว 7 ต.ค. 2026 (P3-11c):** รันบน GitHub Actions กับ kemi-dev สำเร็จ 3 รอบ (PG 17, session A `REPEATABLE READ` + `pg_export_snapshot` แล้ว `pg_dump --snapshot` อีก session ผ่าน pooler พอร์ต 5432) | 3, 7 | dump ก่อนแล้วสร้าง manifest จาก dump ที่ restore ชั่วคราว หรืออาศัย `maintenance_locks` |
| 13 | การต่อฐานข้อมูลผ่าน pooler อย่างเดียวกันโปรเจกต์หลับได้ไหม | 7–8 (สังเกตช่วงปิดเทอม) | `ping()` ผ่าน Data API ทุกรอบสำรองอยู่แล้ว |
| 14 | token ของ rclone (`drive.file`, consent production) ไม่หมดอายุ 7 วัน — **7 ต.ค. 2026:** Publish เป็น In production ได้หลังใส่ homepage/privacy URL (ส่วน 7); พิสูจน์เมื่อรอบสำรองยังผ่านหลังวันที่ 14 ต.ค. 2026 | 0, 7 | ตรวจสถานะ consent screen และสร้าง token ใหม่; Healthchecks.io จะเตือนถ้าสำรองล้มเหลว |
| 15 | สร้าง ZIP ภาคเรียนขนาดหลาย GB ในเบราว์เซอร์ของครู | 6 | แบ่ง ZIP ตามห้อง/งาน |
| 16 | `supabase start` ใน runner ของ GitHub Actions ใช้ restore dump ของ prod ได้ (roles/ส่วนขยายตรงกัน) | 7 | ใช้ Postgres container รุ่นเดียวกันพร้อมสร้าง role ที่ต้องใช้เอง |
| 17 | ความเร็วจากประเทศไทยไปแต่ละภูมิภาคของ B2 — **วัดแล้ว 4 ต.ค. 2026:** เลือก EU Central (ส่วน 3) | 0 (ก่อนสมัคร) | เลือกภูมิภาคที่เร็วรองลงมาที่ผ่านการวัด |
| 18 | B2 รับ GET แบบ Range แล้วส่ง `x-amz-version-id` + `Content-Range`; presigned GET รับ `response-cache-control`; ข้อความ 403 เมื่อเกินเพดานรายวัน — **พิสูจน์แล้ว 5 ต.ค. 2026:** Range GET ได้ 206 + `x-amz-version-id` ตรงกับตอน PUT + `Content-Range: bytes 0-15/<ขนาดเต็ม>`; `response-cache-control` ใช้ได้; รูปแบบ 403 ยืนยันจากเอกสาร B2 (ไม่ทดลองจริงตามข้อห้าม) — Native `download_cap_exceeded`/`transaction_cap_exceeded`, S3 เป็น XML ข้อความ “cap exceeded” | 3 | HEAD + GET แบบเดิม (2 คำขอ); แคชลิงก์ฝั่งหน้าเว็บอย่างเดียว |
| 19 | ดาวน์โหลด 1 GB / Class B 2,500 ต่อวันพอสำหรับวันใช้งานจริง (TECHNICAL_DESIGN 9.3) | 3 (จุดสาธิต 2), 7 | ลดงบเปิดดู, ให้ครูใช้ไฟล์โจทย์เล็กลง, ลดความละเอียดภาพหลังย่อ |

ผลการพิสูจน์แต่ละข้อให้บันทึกกลับใน SYSTEM_SPEC ส่วน 12 หรือ TECHNICAL_DESIGN ส่วนที่เกี่ยวข้องพร้อมวันที่
