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
| รูปภาพ | `createImageBitmap` + canvas ย่อทีละขั้น; ตัวถอด HEIC (เช่น `heic2any` หรือ libheif) โหลดเมื่อพบ HEIC เท่านั้น | TECHNICAL_DESIGN ส่วน 9.2 ข้อ 7 |
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
      _shared/                 # b2.ts (aws4fetch), auth.ts, errors.ts
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
- พื้นที่ฟรี 10 GB ของ B2 นับรวมทุก bucket ในบัญชี: ให้ bucket ทดสอบใช้ไฟล์เล็ก ล้างเป็นระยะ และ **ตั้ง `quota_bytes` ของระบบจริงเป็น 10 GB ลบพื้นที่ที่กันไว้ให้ bucket ทดสอบ** (เช่น 9,500,000,000 ไบต์ เมื่อกันไว้ 0.5 GB) เพื่อให้ระบบหยุดรับตาม J10.2 ก่อนเพดานรวมของบัญชี; `restore-test` รอบรายเดือนกู้ไฟล์เป็นตัวอย่างและลบทันที
- **ภูมิภาค B2 เลือกตอนสมัครบัญชีและเปลี่ยนภายหลังไม่ได้** (ต้องเปิดบัญชีใหม่) และไม่มีเอเชีย: ในระยะ 0 วัดเวลาเชื่อมต่อ (`curl -w '%{time_connect} %{time_appconnect}'`) ไปยัง endpoint S3 ของทุกภูมิภาคตามเอกสาร B2 จาก Wi-Fi โรงเรียนและเน็ตมือถือหลายรอบ แล้วเลือกที่เร็วสุดตาม SYSTEM_SPEC ส่วน 12 ก่อนสมัคร และวัดซ้ำด้วยการอัปโหลดจริงที่จุดสาธิต 2

**ที่เก็บความลับ** (ห้ามอยู่ในโค้ดหรือไฟล์ build)

| ความลับ | อยู่ที่ |
| --- | --- |
| Supabase URL + publishable key (`sb_publishable_…`) | ตัวแปร build ของ Pages (`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`) — เปิดเผยได้ตามแบบ ความปลอดภัยมาจาก RLS; ตอน build ใส่ URL นี้ลงใน CSP `connect-src` ให้เอง |
| Google OAuth client secret (ล็อกอิน) | ตั้งค่า Auth ของ Supabase |
| B2 key อ่าน/เขียน/ลบ (เฉพาะ bucket) | secret ของ Edge Functions (`B2_KEY_ID`, `B2_APP_KEY`, `B2_BUCKET`, `B2_ENDPOINT`) |
| รหัสลับที่ `pg_cron` ใช้เรียก `process-jobs` | Supabase Vault + secret ของ Edge Function |
| connection string ของ Session pooler, B2 key อ่านอย่างเดียว, rclone config, รหัส crypt + salt, URL ping ของ Healthchecks.io, `SUPABASE_ACCESS_TOKEN`, B2 key สำหรับ `restore-test` (เขียน/ลบได้เฉพาะ `kemi-dev-files`) | GitHub Actions secrets |
| รหัส crypt + salt, recovery codes ของทุกบัญชี | ตัวจัดการรหัสผ่านของผู้พัฒนา + สำเนาออฟไลน์ |

## 4. ฐานข้อมูล

### 4.1 หลักการเขียน

1. ทุกตารางใน `public` เปิด RLS; ไม่มี policy ให้ `anon`; ใน migration แรกตั้ง `ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (แบบทั้งระบบ เพราะ Postgres ให้ `PUBLIC` execute ทุกฟังก์ชันเป็นค่าเริ่มต้น และการ REVOKE เฉพาะ schema ลบสิทธิ์ระดับทั้งระบบไม่ได้) และ `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated` (ย้อนค่าที่ Supabase ให้ไว้รายschema) แล้ว GRANT รายฟังก์ชันตามข้อ 3 และยังตรวจซ้ำด้วยรายการในส่วน 11; ตาราง/sequence ใหม่ถอนสิทธิ์ทั้งหมดจาก `anon`, `authenticated` (รวมสิทธิ์ย่อยอย่าง TRUNCATE/REFERENCES/TRIGGER ที่ Supabase ยังให้แม้ปิด auto-expose) แล้ว GRANT เฉพาะ SELECT ที่หน้าเว็บอ่านผ่าน RLS; ถอน EXECUTE ของ `public.rls_auto_enable()` จาก `anon`, `authenticated`; ห้าม GRANT USAGE บน schema `private` ให้ `anon`/`authenticated`; ตาราง (ถ้ามี) ใน `private` เปิด RLS เองเพราะ automatic RLS ทำเฉพาะ `public` (ผลตรวจ `kemi-dev` 30 ก.ย. 2026)
2. หน้าเว็บ **อ่าน** ผ่าน SELECT policy หรือ RPC อ่าน และ **เขียนผ่าน RPC เท่านั้น** (ไม่มี INSERT/UPDATE/DELETE policy)
3. RPC ที่หน้าเว็บเรียกเป็น `SECURITY DEFINER`, `SET search_path = ''`, อ้างชื่อเต็ม และตรวจสิทธิ์เองจาก `private.current_account()`; GRANT ให้ `authenticated` เท่านั้น; ฟังก์ชันช่วยใน `private` ที่ RLS policy เรียกเป็น `SECURITY DEFINER` + GRANT EXECUTE ให้ `authenticated` รายฟังก์ชัน โดยไม่ GRANT USAGE บน `private` (policy ต้องการแค่ EXECUTE — TECHNICAL_DESIGN 3.1 ข้อ 5) และใน policy เขียนเป็น `(select private.current_account())` ให้คำนวณครั้งเดียวต่อคำสั่ง ไม่ใช่ทุกแถว; pgTAP ต้องมีข้อยืนยันว่า `authenticated` เรียกฟังก์ชันช่วยตรงๆ ไม่ได้; RPC ที่ Edge Function เรียกด้วย service role (เช่น `finalize_attachment`) GRANT ให้ `service_role` เท่านั้น
4. เวลาเก็บเป็น `timestamptz` (UTC) และตัดสินด้วย `clock_timestamp()` หลังล็อกแถว; คะแนนและโทเคนเป็นจำนวนเต็ม คำนวณหักสายด้วย `(raw * (100 - pct) + 99) / 100`
5. ลำดับล็อก: `term_control` → `assignments` → `submissions` → `wallets`; ห้ามเรียกบริการภายนอกระหว่างถือล็อก
6. คำสั่งที่เสี่ยงกดซ้ำรับ `p_request_key uuid` และบันทึกใน `operation_receipts` (อายุ 24 ชม.) คำขอซ้ำคืนผลเดิม
7. ข้อผิดพลาดตามกติกา `RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '<รหัส>'` เช่น `storage_full`, `term_ended`, `score_locked`, `reason_required`, `stale_revision`, `rate_limited` แล้วหน้าเว็บแปลงเป็นข้อความตาม UX_DESIGN ส่วน 7.1; migration ที่เพิ่มรหัสใหม่ต้องแจ้งให้เพิ่มแถวในตารางนั้นก่อนหน้าเว็บจะใช้ และรหัสที่ไม่มีในตารางแสดงข้อความสำรองของตาราง
8. ทุก migration มีไฟล์ทดสอบ pgTAP คู่กันก่อน merge
9. `accounts.auth_user_id` **ไม่ใส่ foreign key ไป `auth.users`** เพราะ dump ไม่รวม schema `auth` และต้องกู้ข้ามโปรเจกต์ได้ ตอนกู้ตั้งค่านี้เป็น NULL แล้ว `ensure_account()` จับคู่ใหม่ด้วย `provider_subject` (TECHNICAL_DESIGN ส่วน 3.1 ข้อ 7)

ตัวอย่างโครง RPC:

```sql
create or replace function public.grade_submission(
  p_submission_id uuid, p_raw int, p_pass boolean,
  p_override_pct int, p_reason text, p_seen_revision int,
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
| 4 | `0004_classrooms.sql` | `classrooms`, `memberships`; ค้น/ผูกชื่อ (L3), แก้ผูก, สร้างห้อง/รหัส, เข้าห้องด้วยรหัสหรือลิงก์เชิญ, ปิด/เปิดการเข้าห้อง, จัดการบัญชีครู | 2 |
| 5 | `0005_posts_files.sql` | `posts`, `assignments`, `solutions`, `assets`, `attachments`, `upload_batches`, `storage_settings`, `backup_runs`, `backup_manifests`; สร้าง/แก้โพสต์ (K1, I4 lock, N2 + `content_updated_at`), จอง/ปล่อยพื้นที่, บันทึกรอบสำรอง | 3 |
| 6 | `0006_submissions.sql` | `submissions`, `revision_permissions`; `submit_assignment` ตามตารางรับการส่ง, ส่งแก้แบบเก็บไฟล์เดิม, เพิ่มงานลบไฟล์ที่ถูกแทนลง `jobs`, ตั้ง `pg_cron` + `pg_net` เรียก `process-jobs` | 3 |
| 7 | `0007_grading.sql` | `grades`, `grade_timing`, `comments`; ตรวจ (L2/L4/K2), เปิดสิทธิ์แก้ (K3), ความคิดเห็น/ยกเลิก (F5), เปลี่ยนกำหนดส่งสองทิศ (N3, I2)/ปิดรับ, เฉลยบันทึก/เผยแพร่/แก้ (K4), ลบงาน/ประกาศแบบ cascade (N4), ตารางคะแนน | 4 |
| 8 | `0008_rewards.sql` | `wallets`, `rarities`, `charms`, `owned_charms`, `student_equipment`; ให้รางวัลครั้งเดียว, สถานะเอฟเฟกต์ได้รับโทเคน, ปรับยอด, อัตราสุ่มจริง, สุ่ม (K6), สวมใส่, จัดการเครื่องราง | 5 |
| 9 | `0009_terms.sql` | `terms_start`, `terms_end` (J9, K5, I5), epoch และล้างยอด | 5 |
| 10 | `0010_notifications.sql` | `notifications`; สร้างแจ้งเตือนนักเรียน 5 / ครู 3 เหตุการณ์, งานเตือน 24 ชม. (J7, L5), เกณฑ์พื้นที่ | 6 |
| 11 | `0011_retention.sql` | `retention_requests`; รายการส่งออก, ยืนยันลบ (จำนวน/ไบต์ต้องตรง), ลบก่อนกำหนด (J10.4), ตรวจเทอมเปิดเกิน 6 เดือน | 6 |

เลขไฟล์จริงเรียงตามลำดับที่ push และ migration ที่ push แล้วแก้ไม่ได้ ถ้างานไหนต้องแยกไฟล์เพิ่ม เลขถัดไปเลื่อนตาม ให้ยึดกลุ่มเนื้อหาในตารางนี้ และอ้างชื่อไฟล์จริงใน PROGRESS

`seed.sql`: ระดับ 4 ระดับน้ำหนัก 60/25/10/5, เครื่องราง 12 ชิ้นตาม UX_DESIGN ส่วน 11 (J8), `storage_settings` (`quota_bytes` = 10 GB แบบที่ B2 คิด (1 GB = 1,000,000,000 ไบต์) ลบส่วนที่กันไว้ให้ bucket ทดสอบตามส่วน 3, 80/90%, `hard_stop_margin_bytes` **[ข้อเสนอ]** 300,000,000 ไบต์), `term_control` เริ่มต้น; บน prod ใส่เฉพาะข้อมูลตั้งต้น ไม่ใส่นักเรียนทดสอบ

## 5. RPC และ Edge Functions

**RPC ในฐานข้อมูล** (เรียกด้วย `supabase.rpc`) ครอบคลุมทุกคำสั่งในตาราง API ของ TECHNICAL_DESIGN ส่วน 10 ที่ไม่ต้องใช้กุญแจ B2 เช่น `ensure_account`, `search_roster`, `claim_identity`, `rebind_student`, `create_classroom`, `lookup_classroom`, `join_classroom`, `set_join_enabled`, `create_post`, `update_post`, `update_assignment`, `delete_post`, `submit_assignment`, `grade_submission`, `open_revision_permission`, `post_comment`, `retract_comment`, `change_due`, `close_assignment`, `save_solution`, `publish_solution`, `update_solution`, `wallet_adjust`, `get_draw_options`, `draw_charm`, `set_equipment`, `terms_start`, `terms_end`, `mark_notification_read`, `admin_add_teacher`, `admin_remove_teacher`

**Edge Functions** (ใช้เมื่อต้องใช้กุญแจ B2 เท่านั้น) — หลักคือ **สิทธิ์ตัดสินใน RPC ที่เรียกด้วย JWT ของผู้ใช้** ส่วนฟังก์ชันทำเฉพาะงานที่ต้องใช้กุญแจ:

| ฟังก์ชัน | เส้นทาง | ขั้นตอน |
| --- | --- | --- |
| `uploads` | `POST /uploads` | RPC `create_upload_batch` (ตรวจสิทธิ์ งาน `ended` พื้นที่ จำนวน/ขนาด J4–J6, เพดานครั้ง) → ลงลายเซ็น PUT ต่อไฟล์ใต้ `staging/` อายุ 5 นาที พร้อม `content-type` และ `content-length` |
| `uploads` | `POST /uploads/:id/complete` | HEAD เก็บ `staging_version_id` → GET แบบ Range ตรวจ magic number → ตั้ง `copying` → CopyObject ระบุเวอร์ชันต้นทาง + `REPLACE` content-type → เก็บ `version_id` ปลายทาง → ลบ staging ระบุเวอร์ชัน → RPC `finalize_attachment` (service role) |
| `files` | `POST /files/sign` | RPC `authorize_files(ids)` ตรวจสิทธิ์ตามวัตถุประสงค์ไฟล์ → presigned GET 10 นาทีระบุ `versionId` + `response-content-disposition` |
| `files` | `GET /submissions/:id/files` | RPC ครู/ผู้ดูแลในโหมดผู้ดูแล → รายการไฟล์ตามลำดับ + ลิงก์ + ชื่อ PDF `{เลขที่ 2 หลัก}_{ชื่อ}_{นามสกุล}.pdf` |
| `files` | `POST /exports` | RPC ครู → รายการไฟล์ภาคเรียนเป็นหน้า ๆ พร้อมลิงก์ สำหรับ ZIP ฝั่งเบราว์เซอร์ |
| `process-jobs` | เรียกจาก `pg_cron` | ตรวจรหัสลับจาก Vault → ดึงงานด้วย `FOR UPDATE SKIP LOCKED` → ทำงานตาม `kind` (ส่วน 10 ระยะ 6) |

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
| T04, T05 | `/t/c/:classId/grades`, `/t/c/:classId/roster` | 2–4 |
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
  "allowedHeaders": ["content-type", "authorization", "x-amz-*"],
  "exposeHeaders": ["ETag", "x-amz-version-id"],
  "maxAgeSeconds": 3600}]
```

   bucket ใช้จริงควรเอา `localhost` และ preview ออกเมื่อเปิดใช้; ตรวจรูปแบบ wildcard กับเอกสาร B2 **[ต้องพิสูจน์]**
5. Application keys: `kemi-edge` (list/read/write/delete เฉพาะ bucket), `kemi-backup-ro` (list/read เฉพาะ bucket) — ชื่อ capability ใช้ตาม B2 CLI รุ่นที่ติดตั้ง

**Cloudflare Pages**

1. เชื่อม repo: root `web`, build `npm ci && npm run build`, output `dist`, ตั้ง `NODE_VERSION`
2. ตัวแปร build แยก production/preview (ชี้ Supabase prod/dev); ระยะ 1–6 ทั้งสองชี้ `kemi-dev` ตามส่วน 3 และไฟล์ `web/.node-version` กำหนด Node 24
3. เปิด preview deployments เฉพาะ branch ที่ใช้ทดสอบ

**Google Drive สำรอง + rclone**

1. บัญชี Google แยกของโปรเจกต์ เปิดยืนยันสองขั้น สร้างโฟลเดอร์ `kemi-backup` ไม่แชร์ให้ใคร
2. โปรเจกต์ Google Cloud ในบัญชีนี้ → OAuth client แบบ Desktop สำหรับ rclone, scope `drive.file`, consent screen production (กัน token หมดอายุ 7 วัน)
3. `rclone config`: remote `gdrive` (drive, `drive.file`) → remote `gcrypt` (crypt ครอบ `gdrive:kemi-backup` เข้ารหัสชื่อไฟล์และเนื้อหา) และ remote `b2ro` (B2 ด้วยกุญแจอ่านอย่างเดียว); เก็บ config เป็น GitHub secret

**Healthchecks.io**

1. check `kemi-backup` รอบ 12 ชั่วโมง เผื่อ 3 ชั่วโมง ส่งอีเมลถึงผู้พัฒนา
2. check `kemi-restore-test` **[ข้อเสนอ]** รอบ 35 วัน เพื่อเตือนเมื่อไม่ได้ทดสอบกู้คืนตามรอบเดือน

## 8. GitHub Actions

| workflow | เมื่อไร | ทำอะไร |
| --- | --- | --- |
| `ci.yml` | ทุก push/PR | ติดตั้ง, lint, typecheck, Vitest, build หน้าเว็บ; เมื่อแก้ `supabase/**` รัน pgTAP กับฐานข้อมูลชั่วคราวใน runner (Supabase CLI เปิด Postgres ใน Docker แล้วใส่ migration ของ commit นั้น) — ไม่ใช้ secret และไม่แตะ `kemi-dev` |
| `deploy-db.yml` | กดรันเอง (`workflow_dispatch`) เลือก dev/prod | `supabase db push` และ `supabase functions deploy`; รอบ dev รัน pgTAP กับ `kemi-dev` หลัง push (รวมข้อที่พึ่ง automatic RLS ซึ่งฐานข้อมูลใน runner ไม่มี); prod รันหลังผ่าน dev แล้วเท่านั้น |
| `backup.yml` | `30 19 * * *`, `30 7 * * *` (02:30/14:30 น. ไทย) + กดรันเอง | สำรองตาม TECHNICAL_DESIGN ส่วน 12 |
| `restore-test.yml` | กดรันเอง เลือกจุดกู้คืนและชุดไฟล์ | กู้เข้า Supabase ชั่วคราวใน runner + ไฟล์ใน `kemi-dev-files` แล้วตรวจ ลบทิ้ง และบันทึกผลลง prod |

ประมาณการนาที: สำรอง ~5 นาที × 60 รอบ ≈ 300 นาที/เดือน + CI ≈ 300–500 นาที + `restore-test` ~15 นาทีต่อครั้ง รวมต่ำกว่า 2,000 นาทีฟรีของ repo private

**ขั้นตอน `backup.yml`** (สคริปต์ `ops/backup.sh`, ทุกขั้นล้มเหลวแล้ว ping `/fail` และปลดล็อก):

1. `concurrency: backup`; ping `/start`; ติดตั้ง `postgresql-client` รุ่นหลักตรงกับเซิร์ฟเวอร์จาก PGDG และ rclone
2. RPC: ตั้ง `maintenance_locks` (หมดอายุ 2 ชม.) และสร้าง `backup_runs` สถานะกำลังทำ
3. เปิด session A ผ่าน Session pooler: `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT pg_export_snapshot();` แล้วใน session เดียวกันรัน `ops/manifest.sql` (รายการ `final_key`, `version_id`, ขนาด, checksum ของ attachments/assets สถานะ `ready`)
4. session B: `pg_dump --snapshot=<id> --schema=public --schema=private` แยกไฟล์ schema และ data จากนั้น COMMIT session A — dump กับ manifest จึงมาจากจุดเดียวกัน **[ต้องพิสูจน์ผ่าน pooler]**
5. หาไฟล์ใหม่ = manifest ลบรายการที่มีในสำรองแล้ว → `rclone copy b2ro:<bucket> gcrypt:files --files-from new.txt`
6. `rclone cryptcheck b2ro:<bucket> gcrypt:files --files-from new.txt` + ตรวจการมีอยู่/ขนาดของไฟล์เดิมจาก `rclone lsjson`; ไฟล์ที่ขนาดไม่ตรง manifest ดึงตาม `version_id` ด้วย `aws s3api get-object --version-id` (endpoint B2) แล้วคัดลอกแทน; ยังไม่ครบ = ล้มเหลว
7. อัปโหลด dump + manifest ไป `gcrypt:runs/<เวลา>/` → RPC บันทึก `backup_runs` สำเร็จพร้อมจำนวน/ขนาด → ping สำเร็จ
8. ล้างรอบเก่ากว่า 7 วัน และไฟล์ที่ไม่มี manifest ใน 7 วันอ้างถึง ด้วย `--drive-use-trash=false` เฉพาะในโฟลเดอร์สำรอง
9. RPC ปลดล็อก และเรียก `ping()` ผ่าน Data API (ช่วยกันโปรเจกต์หลับ)

**ขั้นตอน `restore-test.yml`** (สคริปต์ `ops/restore-test.sh`, input: จุดกู้คืน และ `files: sample|all`):

1. ติดตั้ง Supabase CLI แล้ว `supabase start` ใน runner (Postgres รุ่นหลักเดียวกับ prod) — ฐานข้อมูลนี้อยู่แค่ในงานนี้และถูกทิ้งเมื่อจบ
2. ดึง dump + manifest ของจุดที่เลือกจาก `gcrypt:` → restore schema แล้ว data → ตั้ง `accounts.auth_user_id` เป็น NULL
3. อัปโหลดไฟล์จาก manifest (`sample` = สุ่มประมาณ 50 ไฟล์สำหรับรอบรายเดือน, `all` = ทุกไฟล์ ใช้ก่อนเปิดใช้จริงเมื่อข้อมูลยังเล็ก) เข้า `final_key` เดิมใน `kemi-dev-files` เก็บ `version_id` ใหม่ → อัปเดตในฐานข้อมูลชั่วคราวตาม TECHNICAL_DESIGN ส่วน 12 ตรวจขนาด/checksum
4. ตรวจยอดแถวหลัก ยอดโทเคน owned_charms และสร้าง presigned GET ของไฟล์ที่กู้แล้วดาวน์โหลดเทียบ checksum
5. ลบไฟล์ที่อัปโหลดในข้อ 3 จาก `kemi-dev-files` โดยระบุ `version_id` (ทำแม้ขั้นก่อนหน้าล้มเหลว) และหยุด `supabase stop`
6. บันทึกผล (ผ่าน/ไม่ผ่าน จุดกู้คืน จำนวนไฟล์ที่ตรวจ) ลง `backup_runs` ของ prod เป็นชนิด `restore_test` ผ่าน RPC เพื่อแสดง “ทดสอบกู้คืนล่าสุด” ใน D01 แล้ว ping `kemi-restore-test`

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

งาน: migration 3–4; นำเข้า Excel (ตัวอย่างก่อนบันทึก ตรวจซ้ำ ศูนย์นำหน้า); A02 (L3); A01 แบบมาจากลิงก์เชิญ + `/join/:code`; S01 + เข้าห้องด้วยรหัส; S06; T01, T09, T08 (แท็บสมาชิก + คัดลอกลิงก์เชิญ **[ข้อเสนอ]**), T10, T05 (แก้ผูก), T12; D01 ส่วนบัญชีครู + โหมดผู้ดูแล (L6)

ตรวจรับ:
- [ ] ค้นด้วยชื่อบางส่วนไม่เจอ ค้นเลขเต็ม/ชื่อเต็มเจอเป็นชื่อปิดบางส่วน + ห้อง + เลขที่; ค้นครั้งที่ 11 ใน 10 นาทีถูกปฏิเสธ (L3)
- [ ] สองบัญชียืนยันชื่อเดียวกันพร้อมกัน สำเร็จบัญชีเดียว
- [ ] แก้ผูกแล้วแท็บของบัญชีเดิมทำคำสั่งถัดไปไม่ได้
- [ ] เข้าห้องได้ทั้งด้วยรหัสและลิงก์เชิญ (ลิงก์เชิญยังต้องล็อกอินและเลือกชื่อก่อน); รหัสห้องผิดซ้ำถูกจำกัด; ปิดการเข้าห้องแล้วเข้าไม่ได้ทั้งรหัสและลิงก์แต่สมาชิกเดิมใช้ต่อได้; กดเข้าซ้ำไม่เกิดสมาชิกซ้ำ
- [ ] เอาบัญชีครูรายการสุดท้ายออกไม่ได้; โหมดผู้ดูแลมีแถบเตือนทุกหน้า และ RPC ฝั่งครูที่ผู้ดูแลเรียกโดยไม่ส่งโหมดถูกปฏิเสธ (L6)
- [ ] นำเข้าไฟล์ Excel จริงของครูได้ (เมื่อได้ไฟล์)

### ระยะ 3 — งานและไฟล์

งาน: migration 5–6; Edge Functions `uploads`, `files` และ `process-jobs` ขั้นต่ำ (ลบไฟล์ที่ถูกแทน, sweeper `copying` และ batch ค้าง) พร้อม `pg_cron`; ตั้ง CORS/lifecycle/keys ของ B2; โมดูลอัปโหลด; T02 (K1: คะแนนเต็มจำนวนเต็ม ≥ 1 ไม่มีเพดาน 100, ปุ่มตัวห้อย/ตัวยก, รายละเอียด/ไฟล์ไม่บังคับ) + โหมดแก้ไข (N2, N1), S02, S03 (ไฟล์โจทย์เปิดดู/ดาวน์โหลด, ส่ง/ส่งแก้/สถานะ), T08 รายการงาน, T03 รายการสถานะ + การ์ดโจทย์และไฟล์ + ตัวดูไฟล์เบื้องต้น; ระบบนับพื้นที่ + แถบพื้นที่เต็ม; **ตั้ง `backup.yml` แบบพื้นฐานกับ dev** (ใช้ `maintenance_locks`/`backup_runs` จาก migration 1 และ 5)

ตรวจรับ:
- [ ] PUT ที่ขนาดไม่ตรงลายเซ็นถูก B2 ปฏิเสธ; ไฟล์ที่ magic number ไม่ใช่ JPEG/PNG/PDF ถูกปฏิเสธตอน complete
- [ ] หลัง complete แล้วใช้ลิงก์เดิมอัปทับ staging ไฟล์ที่ระบบใช้ไม่เปลี่ยน (ตรวจ `version_id`)
- [ ] นักเรียนที่เป็นสมาชิกเปิดดูและดาวน์โหลดไฟล์โจทย์ได้ ชื่อไฟล์ภาษาไทยถูกต้องบนมือถือ แท็บเล็ต และคอม; คนที่ไม่ใช่สมาชิกห้องขอลิงก์ไม่ได้
- [ ] ขอลิงก์เปิดไฟล์ของนักเรียนคนอื่นได้ 403; เปิด URL ของ B2 โดยไม่มีลายเซ็นไม่ได้; เรียกจาก origin อื่นถูก CORS ปฏิเสธ
- [ ] สร้างการบ้านโดยไม่มีรายละเอียดและไฟล์ได้; แก้ชื่อ/รายละเอียด/ไฟล์หลังมีคนส่งได้ ไม่มีแจ้งเตือน นักเรียนเห็น “แก้ไขล่าสุด” และไฟล์ที่เอาออกเข้าคิวลบ; ช่องที่ล็อก (N2) แก้ผ่าน RPC ไม่ได้
- [ ] ตารางรับการส่งทั้ง 7 แถวผ่าน pgTAP; ส่งแก้ล้มเหลวชุดเดิมและเวลาเดิมอยู่ครบ
- [ ] ส่งแก้โดยเก็บรูปเดิม 2 รูปเปลี่ยนรูปที่ 3: ไม่อัปโหลด 2 รูปเดิมซ้ำ และลบเฉพาะรูปที่ถูกแทน (ระบุเวอร์ชัน)
- [ ] ตั้ง quota ต่ำบน dev: อัปโหลดใหม่ถูกหยุดพร้อมข้อความ J10.3 แต่ดู/ตรวจงานได้
- [ ] อุปกรณ์จริง: HEIC จาก iPhone, รูปต้นฉบับเกิน 20 MB ถูกปฏิเสธก่อนย่อแต่รูปที่ไม่เกินผ่าน, ตัวห้อย/ตัวยกอ่านชัดหลังย่อ, วัดเวลาอัปโหลดผ่าน Wi-Fi โรงเรียน (จุดสาธิต 2)

### ระยะ 4 — ตรวจงานและคะแนน

งาน: migration 7; T03 หน้าตรวจ (ตัวดูรูป/PDF, ซูม, หมุน, ดาวน์โหลด PDF), แผงคะแนน (L2, L4, K2), สิทธิ์แก้ (K3), ความคิดเห็น + ยกเลิก, M1 เปลี่ยนกำหนดส่งสองทิศ (N3), M2 ปิดรับ, M3 เฉลย (K4), ลบงาน/ประกาศ (N4), T04 + CSV, หน้าผลตรวจ/เฉลยของนักเรียน

ตรวจรับ:
- [ ] ชุดสูตรคะแนนในส่วน 9 ผ่านทั้งหน้าเว็บและฐานข้อมูล; คะแนนเกินเต็มถูกปฏิเสธ; คะแนนเต็ม 150 ใช้ได้ (K1)
- [ ] บันทึกเฉพาะผ่านไม่ล็อก; บันทึกคะแนนแรกล็อกคะแนนเต็มและ % หัก และแก้ผ่าน `update_assignment` ไม่ได้ (L4, K2)
- [ ] ปรับหักรายคนไม่มีเหตุผลบันทึกไม่ได้; เหตุผลขึ้นในความคิดเห็นที่นักเรียนเห็น; 0% = ยกเว้น (L2, J3)
- [ ] สิทธิ์แก้: ส่งล้มเหลวไม่ใช้สิทธิ์ ส่งสำเร็จใช้ครั้งเดียว ครั้งถัดไปต้องเปิดใหม่ (K3)
- [ ] แก้เฉลยหลังเผยแพร่: `published_at` คงเดิม แสดงเวลาแก้ล่าสุด คะแนน/โทเคน/`first_after_solution` ไม่เปลี่ยน (K4)
- [ ] I1 ไม่หักเพราะเวลาส่งแก้, I2 ขยายกำหนดไม่เขียนทับผลเดิม, I3 ผ่าน→ไม่ผ่านไม่ถอนโทเคน
- [ ] N3: เลื่อนกำหนดเร็วขึ้นแล้วงานที่ยังไม่ตรวจซึ่งส่งหลังกำหนดใหม่กลายเป็นสาย งานที่ตรวจแล้วคงผลและโทเคนเดิม หน้าต่างแสดงรายชื่อทั้งสองทิศก่อนบันทึก และงานเตือน 24 ชม. ถูกจัดใหม่/ยกเลิกถูกต้อง
- [ ] N4: ลบการบ้านที่มีงานส่ง คะแนน และความคิดเห็นแล้ว ข้อมูลที่เกี่ยวข้องหายครบใน transaction เดียว ยอดโทเคนคงเดิม ไฟล์ B2 เข้าคิวลบ จำนวนที่หน้าเว็บส่งมาไม่ตรงได้ conflict; ลบประกาศได้
- [ ] ครูบันทึกผลบนไฟล์รุ่นเก่าขณะนักเรียนส่งใหม่ ได้ conflict แล้วโหลดใหม่
- [ ] CSV เปิดใน Excel ภาษาไทยถูก; PDF รวมทุกหน้าตามลำดับ ชื่อ `12_ธนภัทร_ใจดี.pdf`

### ระยะ 5 — รางวัลและสะสม

งาน: migration 8–9; ให้รางวัลใน transaction เดียวกับผลตรวจ, เอฟเฟกต์เมื่อได้รับโทเคนแสดงครั้งเดียวเมื่อกลับมา (`reward_effect_seen`), ปรับยอด, S04 (อัตราจริง), สุ่ม + เอฟเฟกต์, S05, สวมใส่ + แสดงในแท็บสมาชิก, T06 (อัตรารวม 100, อัปโหลดรูปเครื่องราง), T07 เริ่ม/จบภาคเรียน

ตรวจรับ:
- [ ] เอฟเฟกต์ได้รับโทเคนแสดงครั้งเดียว ไม่มีรายการในกระดิ่ง
- [ ] ตรวจซ้ำ/พร้อมกันให้โทเคนครั้งเดียว; ผ่าน→ไม่ผ่าน→ผ่านไม่ได้ซ้ำ; ส่งช้าไม่ได้โทเคน; งานเทอมเก่าไม่ให้โทเคนเข้าเทอมใหม่ (I5)
- [ ] สุ่มสองแท็บพร้อมกันมี 1 โทเคน สำเร็จครั้งเดียว ยอดไม่ติดลบ; ไม่มีของซ้ำ
- [ ] ชิ้นที่ยังไม่มีในระดับเดียวกันโอกาสเท่ากัน (ทดสอบสถิติบน dev); ครบทุกชิ้น = completed; เหลือแต่น้ำหนัก 0 = unavailable ไม่หักโทเคน (K6)
- [ ] จบภาคเรียน: นักเรียนส่งงาน/ความคิดเห็นไม่ได้ (ปฏิเสธที่เซิร์ฟเวอร์) แต่สุ่มได้; ครูตรวจและเขียนความคิดเห็นได้; งานเข้าเกณฑ์ยังได้โทเคน (K5)
- [ ] เริ่มภาคเรียนใหม่ล้างยอดทุกห้องพร้อมกัน คง owned_charms; กดซ้ำคืนผลเดิม; ตรวจงานชนการเริ่มเทอมไม่ทำให้ยอดผิด

### ระยะ 6 — แจ้งเตือนและงานเบื้องหลัง

งาน: migration 10–11; เพิ่มงานใน `process-jobs`: เตือน 24 ชม. (J7, L5), สร้างแจ้งเตือน (นักเรียน 5 / ครู 3 เหตุการณ์, dedupe), เทียบยอดพื้นที่ B2 รายวัน, เกณฑ์ 80/90/100%, เทอมเปิดเกิน 6 เดือน, เสนอลบตามอายุ; C01, T11, แผงพื้นที่และรายการงานเบื้องหลังที่ล้มเหลวใน D01, แถวข้อมูลเก่าใน T07 + ZIP + ยืนยันลบ + ลบก่อนกำหนด (J10.4)

ตรวจรับ:
- [ ] เตือนเฉพาะคนยังไม่ส่ง 24 ชม. ก่อนกำหนด ครั้งเดียว; โพสต์เมื่อเหลือไม่ถึง 24 ชม. ไม่มีเตือน; ขยายจากเหลือ 10 ชม. เป็น 3 วันได้เตือน 1 ครั้ง; เคยเตือนแล้วขยายอีกไม่เตือนซ้ำ (L5)
- [ ] แจ้งเตือนไม่เก็บเนื้อความคิดเห็น; ความคิดเห็นที่ยกเลิกแล้วเปิดจากกระดิ่งเห็น “ข้อความนี้ถูกยกเลิก”
- [ ] เรียก `process-jobs` ซ้อนกันไม่ทำงานซ้ำ; มี `maintenance_locks` แล้วงานลบรอ
- [ ] เกณฑ์พื้นที่แจ้งครั้งเดียวต่อระดับ; ยอด B2 จริงลดลงหลังลบ (ตรวจวันถัดไป)
- [ ] ZIP ของภาคเรียนทดสอบมีไฟล์ครบตาม `manifest.csv`; ยืนยันลบด้วยจำนวน/ไบต์ไม่ตรงถูกปฏิเสธ

### ระยะ 7 — สำรองและความพร้อม

งาน: `backup.yml` ฉบับเต็ม + job `guard` + `restore-test.yml`; แผงสำรองและ “ทดสอบกู้คืนล่าสุด” ใน D01 จาก `backup_runs`; รายการความปลอดภัยส่วน 11; ทดสอบภาระ; ทดสอบอุปกรณ์และการเข้าถึง; เตรียม prod (migration, seed, allowlist ครู, storage settings, caps, redirect, CORS เฉพาะโดเมนจริง); ชื่อภาคเรียนแรกใน seed ของ prod ตั้งตามภาคเรียนจริงตอนเปิดใช้ (ถามครู); สลับตัวแปร Production ของ Pages เป็น `kemi-prod` พร้อม `VITE_DEPLOY_ENV=prod` แล้ว deploy ใหม่ และเอาโดเมน production ออกจาก Redirect URLs ของ `kemi-dev`

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
| 1 | B2 ต้องผูกบัตรไหม และ caps ตั้งที่ปริมาณฟรีได้ (ตรวจตอนสมัครข้อ 1) | 0 | ทบทวนแผนเก็บไฟล์กับผู้ใช้ก่อนทำต่อ |
| 2 | `pg_cron` + `pg_net` ใช้ในแผนฟรีได้ (ข้อ 2, 8) | 0 | ให้ GitHub Actions เรียก `process-jobs` แทน |
| 3 | บัญชี Google ของโรงเรียนล็อกอินได้ (ข้อ 3) | 1 | ใช้บัญชีส่วนตัว หรือขอโรงเรียนอนุญาต |
| 4 | Supabase ใช้ฟรีโดยไม่ผูกบัตร (ข้อ 4) | 0 | — |
| 5 | Healthchecks.io ส่งอีเมลจริง (ข้อ 5) | 3, 7 | เปลี่ยนช่องทางแจ้ง |
| 6 | Lifecycle rules แยก `files/` กับ `staging/` ได้ตามส่วน 7 (ข้อ 6) | 0, 3 | ใช้งานลบตามรอบใน `process-jobs` เป็นหลัก |
| 7 | CORS, ลายเซ็น `content-length`, CopyObject ระบุเวอร์ชันต้นทาง, เพดานดาวน์โหลดเดือนแรก (ข้อ 7) | 3 | ตรวจขนาดตอน complete อย่างเดียว / ดาวน์โหลดแล้วอัปโหลดแทนการคัดลอก / ปรับเพดาน |
| 8 | เวอร์ชัน Postgres, ต่อ Session pooler จาก Actions, rate limit ของ Auth (ข้อ 8) | 1, 3, 7 | ปรับวิธี dump / ปรับค่าใน Dashboard |
| 9 | ชนิดของ ETag ที่ B2 ส่งกลับ (ใช้เป็น checksum) | 3 | ใช้ขนาด + `cryptcheck` เป็นหลัก |
| 10 | `response-content-type` / `response-content-disposition` บน presigned GET ของ B2 | 3–4 | ตั้งชื่อไฟล์ฝั่งหน้าเว็บด้วย Blob |
| 11 | Safari บน iPhone แปลง HEIC เป็น JPEG เองเมื่อเลือกไฟล์ | 3 | โหลดตัวถอด HEIC ตามแผน |
| 12 | `pg_dump --snapshot` ผ่าน Session pooler | 3, 7 | dump ก่อนแล้วสร้าง manifest จาก dump ที่ restore ชั่วคราว หรืออาศัย `maintenance_locks` |
| 13 | การต่อฐานข้อมูลผ่าน pooler อย่างเดียวกันโปรเจกต์หลับได้ไหม | 7–8 (สังเกตช่วงปิดเทอม) | `ping()` ผ่าน Data API ทุกรอบสำรองอยู่แล้ว |
| 14 | token ของ rclone (`drive.file`, consent production) ไม่หมดอายุ 7 วัน | 0, 7 | ตรวจสถานะ consent screen และสร้าง token ใหม่; Healthchecks.io จะเตือนถ้าสำรองล้มเหลว |
| 15 | สร้าง ZIP ภาคเรียนขนาดหลาย GB ในเบราว์เซอร์ของครู | 6 | แบ่ง ZIP ตามห้อง/งาน |
| 16 | `supabase start` ใน runner ของ GitHub Actions ใช้ restore dump ของ prod ได้ (roles/ส่วนขยายตรงกัน) | 7 | ใช้ Postgres container รุ่นเดียวกันพร้อมสร้าง role ที่ต้องใช้เอง |
| 17 | ความเร็วจากประเทศไทยไปแต่ละภูมิภาคของ B2 | 0 (ก่อนสมัคร) | เลือกภูมิภาคที่เร็วรองลงมาที่ผ่านการวัด |

ผลการพิสูจน์แต่ละข้อให้บันทึกกลับใน SYSTEM_SPEC ส่วน 12 หรือ TECHNICAL_DESIGN ส่วนที่เกี่ยวข้องพร้อมวันที่
