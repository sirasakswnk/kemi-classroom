# PROGRESS — ห้องเคมี

ไฟล์นี้คือบันทึกงานทีละขั้นตาม `CLAUDE.md` ส่วน 1 · รายละเอียดแต่ละงานดู `TECHNICAL_BUILD_PLAN.md` ส่วน 10 ของระยะนั้น
รูปแบบบรรทัด: `- [ ] รหัส งาน · (ต้องมี: …)` — ทำเสร็จแล้วเปลี่ยนเป็น `[x]` และต่อท้ายโน้ตสั้น `→ วันที่: ผล/ข้อควรรู้`
ระดับ effort: ค่าเริ่มต้นใช้ **กลาง**; งานที่ติด **[effort สูง]** (สิทธิ์ฐานข้อมูล คะแนน/โทเคน/สุ่ม ไฟล์ B2 งานเบื้องหลัง สำรอง/กู้คืน) ใช้สูง; งานเล็กอย่างแก้ข้อความหรือจัดรูปแบบใช้ต่ำได้

## สถานะล่าสุด

- ระยะปัจจุบัน: 1 (มีโครง `web/` แล้ว)
- งานถัดไป: P1-08 (งานระยะ 1 ทำบน branch `phase-1`) · P2-01a ทำได้ก่อน/พร้อม P2-01 · P1-08: ใส่ teacher + allowlist ของ kemi-dev ด้วย SQL **ถามผู้ใช้ก่อน** (ห้ามมีอีเมลจริงในไฟล์ที่ commit)
- **ข้อสรุปฟังก์ชันช่วยของ RLS (ผู้ใช้ตัดสิน 30 ก.ย.):** อยู่ใน `private` ไม่ย้ายไป `public` (ไม่งั้นกลายเป็น `/rest/v1/rpc/…` ที่นักเรียนเรียกเองได้) — SECURITY DEFINER + GRANT EXECUTE ให้ `authenticated` รายฟังก์ชัน, **ไม่ GRANT USAGE บน `private`** (policy ต้องการแค่ EXECUTE; เรียกตรงถูกปฏิเสธ “permission denied for schema private”), ใน policy เขียน `(select private.current_account())`; P1-07 ต้องมี pgTAP บน `kemi-dev` (PG17) ยืนยันว่า policy ทำงานโดยไม่มี USAGE และ `authenticated` เรียกฟังก์ชันช่วยตรง ๆ ไม่ได้ (TECHNICAL_DESIGN 3.1 ข้อ 5, BUILD_PLAN 4.1 ข้อ 3)
- **ดีไซน์ (ผู้ใช้ตัดสิน 30 ก.ย.):** ใช้แบบ v2 (`exports/chemistry-design-v2.html`) ตามเดิม — P1-03/P1-04 ไม่ต้องรอแล้ว
- บริการที่ตั้งแล้ว (30 ก.ย. 2026): Supabase `kemi-dev` · Google OAuth client `kemi-dev` (Web application) ใส่ใน Supabase → Google provider แล้ว · หน้าขอสิทธิ์ Google อยู่สถานะ **Testing** (ล็อกอินได้เฉพาะบัญชีใน Test users)
- งานค้าง: —
- รอผู้ใช้: บัญชี Google ของผู้ดูแลและอีเมลครู · Google OAuth อยู่สถานะ Testing: บัญชีที่จะล็อกอินทดสอบต้องเพิ่มใน Test users ก่อน · เปิดบัญชีบริการตาม `ops/SIGNUP_CHECKLIST.md` · รัน `node ops/b2-latency.mjs --rounds 10 --label school` ที่ Wi-Fi โรงเรียน และ `--label mobile` ที่เน็ตมือถือ (หลายช่วงเวลา) แล้วส่งบรรทัด “สรุป” มา ก่อนสมัคร B2 · ทดสอบ Sheet/Modal บนเครื่องจริงเมื่อมี preview บน Pages ใน P1-09: **iPhone (Safari)** หน้าหลังไม่เลื่อนตามนิ้ว และปิดแล้วกลับตำแหน่งเดิม · **Android (Chrome)** กดปุ่ม/ท่าทางย้อนกลับขณะเปิดกล่อง A02 แล้วกล่องต้องไม่ปิด (เปิดกลับทันที) และกล่องที่ปิดได้ต้องปิดโดยไม่ออกจากหน้า
- ค่าบริการที่ไม่ใช่ความลับ (กรอกเมื่อได้): Supabase dev URL `https://igchlnmxbghsigyziomk.supabase.co` (ref `igchlnmxbghsigyziomk`, publishable key `sb_publishable_kpY6n1jpQSDKeqLBXZPAYQ_LY_pyyYR`, ภูมิภาค Singapore ยืนยันแล้ว; pg_cron/pg_net มีให้เปิด; รหัสฐานข้อมูลเปลี่ยนใหม่แล้ว 30 ก.ย.) · prod URL — (สร้างในระยะ 7) · Postgres รุ่น 17.6 (ใช้ `pg_dump` รุ่น 17) · B2 ภูมิภาค/endpoint — · GitHub repo `sirasakswnk/kemi-classroom` (private, remote `origin`, push `main` + `phase-1` แล้ว 30 ก.ย.; ติดตั้ง `gh` 2.102 ล็อกอินแล้ว — ถ้า bash หา `gh` ไม่เจอให้เติม PATH `/c/Program Files/GitHub CLI`) · ชื่อเว็บ `kemi-classroom` (→ kemi-classroom.pages.dev ยืนยันใน P1-09)

## ระยะ 0 — เตรียมบริการ (ผู้ใช้เปิดบัญชีเอง Claude ช่วยเตรียม)

- [x] P0-01 สคริปต์ `ops/b2-latency.mjs` วัดเวลาเชื่อมต่อไปยัง endpoint S3 ของทุกภูมิภาค B2 ให้ผู้ใช้รันที่ Wi-Fi โรงเรียนและเน็ตมือถือ → 30 ก.ย. 2026: Node built-in ล้วน วัด TCP/TLS/ตอบแรก (HEAD) มัธยฐานหลายรอบ + บรรทัด “สรุป” ให้คัดลอก; ภูมิภาคที่สมัครได้ us-west-004, us-east-005, eu-central-003, ca-east-006 (+ us-west-001/002 เก่าไว้เทียบ); ทดสอบที่เน็ตบ้านผู้พัฒนา 3 รอบ: EU Central 747, CA East 759, US East 1039, US West 1701 ms — ค่าแกว่งมาก ต้องวัดหลายครั้ง
- [x] P0-02 เช็กลิสต์สมัคร `ops/SIGNUP_CHECKLIST.md` ตาม BUILD_PLAN ส่วน 7 + รายการตรวจ 8 ข้อของ SYSTEM_SPEC ส่วน 12 (ผู้ใช้ทำตาม) → 30 ก.ย. 2026: เขียนจาก Claude app ก่อนสร้าง git; ผู้ใช้กำลังทำตาม
- [ ] P0-03 บันทึกผลตรวจตอนสมัครและค่าที่ไม่ใช่ความลับลง “สถานะล่าสุด” และ SYSTEM_SPEC ส่วน 12 · (ต้องมี: ผลจากผู้ใช้)

## ระยะ 1 — โครงระบบและล็อกอิน

- [x] P1-01 `git init`, `.gitignore` (node_modules, dist, `.env*`, `.work/`, `*.xlsx`, `*.csv`, dump/backup, `supabase/.temp`), README สั้น, commit เอกสารเดิม → 30 ก.ย. 2026: repo บน `main` (Node 24.20.0, Git 2.51); เพิ่ม `.gitattributes` บังคับ LF; `.gitignore` กันเพิ่ม `*.xls`, `*.pem`, `*.key` (ยกเว้น `.env.example`); ยังไม่มี remote
- [x] P1-02 scaffold `web/` (Vite + React + TS strict, ESLint, Prettier, Vitest, npm scripts) แล้วปรับคำสั่งใน CLAUDE.md ส่วน 6 → 30 ก.ย. 2026: create-vite `react-ts` (Vite 8.3, React 19.3, TS 6.0) template ใหม่ใช้ oxlint จึงเปลี่ยนเป็น ESLint 10 ตามแผน; `build.target` es2021+safari15 ([ข้อเสนอ]); ยังไม่ลง Router/Supabase/TanStack Query (ลงตอนใช้) และไม่ลง jsdom/testing-library — ทดสอบ React ด้วย `react-dom/server`; lint/typecheck/test/build/format:check ผ่าน
- [x] P1-03 `tokens.css` + ฟอนต์ Anuphan/Mitr + คอมโพเนนต์ Button, Card, Chip, Field จากแบบ v2 → 30 ก.ย. 2026: `styles/tokens.css` (สีตาม UX 13 + มุม/ระยะ/เงา [ข้อเสนอ]) + `styles/base.css`; ฟอนต์ `@fontsource` (Anuphan 400/500/600, Mitr 500) รวมใน build ไม่เรียก Google Fonts; `ui/` Button (primary/soft/ghost/gold/danger, sm, block, icon), Card (padding ยืดตามจอ), Chip (7 โทน + ไอคอน), Field + Input/Textarea (ผูก label/hint/error/aria อัตโนมัติ) ด้วย CSS Modules + `lucide-react`; hover อยู่ใน `(hover: hover)`, ปุ่มเล็ก 44 px เมื่อ `pointer: coarse`; ตัวอักษรหน่วย rem, เนื้อหา/ช่องกรอก 16 px (แบบ v2 ใช้ 15 px — ใช้ 16 ตาม UX 13 และกัน iOS ซูม); หน้า DevGallery เฉพาะโหมดพัฒนา (ไม่อยู่ใน build) — Vitest 8 ข้อ, lint/typecheck/format/build ผ่าน; Playwright (ติดตั้งใน scratchpad ไม่อยู่ใน repo) ที่ 390/820/1180/1280: console ไม่มี error/warning, ไม่มีคำขอออกนอกเว็บ, ไม่ล้นแนวนอน, ฟอนต์โหลดครบ, 1/2/3 คอลัมน์ตามจอ
- [x] P1-04 คอมโพเนนต์ Sheet, Modal, Toast, Stepper + หน้าแสดงคอมโพเนนต์ (เฉพาะโหมดพัฒนา) → 30 ก.ย. 2026: Sheet/Modal บน `<dialog>.showModal()` (`ui/DialogBase.tsx`): Esc ดักที่ keydown ระดับเอกสาร (กัน Chrome ข้าม cancel ครั้งที่สอง), ถ้าเบราว์เซอร์ปิดเองแบบปิดไม่ได้จะเปิดกลับ, วน Tab/Shift+Tab ในกล่อง (APG), คืนโฟกัส, แตะพื้นหลังปิด, `dismissible={false}` ไม่มีปุ่ม X (A02); Sheet ≥768 px เป็นแผ่นลอยกลางจอ; ล็อกเลื่อนด้วย `body{position:fixed}` (`lib/useScrollLock.ts`); Toast `role="status"` + `pointer-events:none` + safe-area + `--toast-offset` ไม่มีแบบข้อผิดพลาด; Stepper = ปุ่ม −/+ (`aria-label` “ลด/เพิ่ม…”, ค่าใน `<output aria-live>`, ถึงขอบใช้ `aria-disabled` ให้โฟกัสไม่หลุด); Steps = แถบขั้นตอน `aria-current="step"` + ข้อความสถานะสำหรับเครื่องอ่านหน้าจอ; reduced motion ใช้กฎรวมใน base.css — Vitest 15 ข้อ; Playwright 57/57: Chromium 4 ขนาดจอ (ภาพ/อยู่ในจอ/console สะอาด) + คีย์บอร์ด (Tab วนในกล่อง, Esc ปิด+คืนโฟกัส, A02 ไม่ปิดเมื่อ Esc 5 ครั้ง/Esc ขณะพิมพ์/แตะพื้นหลัง, Stepper หยุดที่ขอบ) + reduced motion + WebKit แบบ iPhone 13 (ล็อกเลื่อนและคืนตำแหน่ง, A02 ไม่ปิด) — **ยังไม่ได้ทดสอบบน iPhone จริง**
    - ข้อเสนอ: ข้อความเครื่องอ่านหน้าจอของ Steps (“เสร็จแล้ว”, “ข้ามขั้นนี้”) ไม่มีใน UX; Toast ที่แสดงตอนเปิด Sheet/Modal อยู่ใต้พื้นหลังของกล่อง (top layer)
- [x] P1-05 `.github/workflows/ci.yml` (lint, typecheck, test, build) → 30 ก.ย. 2026: job `web` (Node 24, checkout/setup-node v7, cache npm) รัน `npm ci` → lint → format:check → typecheck → test → build; ข้ามเมื่อแก้แค่ `*.md`/`exports/` และยกเลิกรอบเก่าเมื่อ push ซ้ำ (ประหยัดนาที); ตรวจ YAML + รันลำดับเดียวกันบนเครื่องผ่าน — CI รอบแรกบน GitHub (`phase-1` @ f321803) ผ่านใน 36 วินาที (checkout 404 ครั้งแรกหลัง push ใหม่แล้ว retry ผ่านเอง); job pgTAP บน `main` เพิ่มใน P1-06
- [x] P1-06 **[effort สูง]** `supabase init` + migration `0001_base` + วิธีรัน pgTAP + ทดสอบพื้นฐาน · (ต้องมี: Supabase `kemi-dev`) · ตอนสร้างโปรเจกต์ผู้ใช้ตั้ง **ปิด Automatically expose new tables** และ **เปิด automatic RLS** ตามคำแนะนำ (ผู้ใช้ยืนยันแล้ว 30 ก.ย.) — ยังตรวจด้วย SQL ก่อน (event trigger และ default privileges) และเพราะตารางใหม่ไม่ได้สิทธิ์อัตโนมัติ migration ต้อง GRANT ให้ `authenticated` เองทุกตาราง/ฟังก์ชันที่หน้าเว็บใช้
  - [x] P1-06a Supabase CLI + `supabase init` → 30 ก.ย. 2026: CLI 2.118.0 เป็น devDependency ใน `package.json` ที่ root (แยกจาก `web/` เพื่อไม่ให้ CI/Pages โหลด CLI) เรียกด้วย `npx supabase …`; `config.toml` ตั้ง `project_id = "kemi-classroom"`, Postgres 17
  - [x] P1-06b ผู้ใช้ `npx supabase login` + `npx supabase link --project-ref igchlnmxbghsigyziomk` แล้วตรวจ `kemi-dev` ด้วย SQL (event trigger ของ automatic RLS, default privileges, ส่วนขยายที่มี) จดผล → 30 ก.ย. 2026 (อ่านอย่างเดียวผ่าน `db query --linked`, PG 17.6, `public` ยังว่าง):
    - automatic RLS = event trigger `ensure_rls` → `public.rls_auto_enable()` (SECURITY DEFINER, เจ้าของ postgres) เปิด RLS ให้ตารางใหม่ **เฉพาะ schema `public`** → ตารางใน `private` ต้อง `enable row level security` เอง; ฟังก์ชันนี้ anon/authenticated execute ได้ (เรียกตรงไม่ได้เพราะคืน event_trigger) → เสนอ REVOKE ใน 0001
    - default privileges ของ `postgres` ใน `public`: ตารางใหม่ให้ anon/authenticated/service_role แค่ `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN ไม่มี SELECT/เขียน) → 0001 ควร REVOKE ALL จาก anon/authenticated ด้วย; ฟังก์ชันยังได้ EXECUTE ให้ `PUBLIC` จากค่าระดับระบบ → ต้อง REVOKE ระดับระบบตาม BUILD_PLAN 4.1
    - ส่วนขยาย: `pgcrypto` ติดตั้งแล้วใน `extensions`; `pgtap` 1.3.3, `pg_cron` 1.6.4, `pg_net` 0.20.4 มีให้เปิดแต่ยังไม่ติดตั้ง; ยังไม่มี schema `private`
  - [x] P1-06c migration `0001_base` + pgTAP คู่กัน + กำหนดวิธีรันทดสอบ แล้ว push ไป `kemi-dev` และรันทดสอบผ่าน → 30 ก.ย. 2026: ตารางกลางทั้ง 5 อยู่ใน `private` (เปิด RLS ไม่มี policy), default privileges `for role postgres` ครอบ tables/sequences/functions ทั้ง public/private + ถอน EXECUTE จาก PUBLIC ระดับระบบ, ถอน EXECUTE `rls_auto_enable()`, `ping()` ให้ `service_role` เท่านั้น; pgTAP 33 ข้อผ่านทั้งในเครื่อง (ข้าม 2 ข้อที่พึ่ง automatic RLS) และบน `kemi-dev` (ครบ) — ลองใส่สิทธิ์ผิด 3 แบบ เทสต์จับได้ครบ; pgtap ไม่ค้างบน dev; Security Advisor เหลือแค่ INFO “RLS enabled no policy” ของตาราง private (ตั้งใจ)
    - ค่าที่เลือกเอง: `operation_receipts` PK = (account_id, request_key) กันใช้ request_key ของคนอื่น, `jobs` unique (kind, dedupe_key), ยังไม่มีเพดานจำนวนครั้งลองใหม่ (เพิ่มตอนทำ job runner)
  - [x] P1-06d job pgTAP ใน `ci.yml` ~~(เฉพาะ `main`) + ชื่อ GitHub Secrets ที่ผู้ใช้ต้องใส่~~ → 30 ก.ย. 2026 (ผู้ใช้เปลี่ยนเป็นไม่ใช้ secret): job `db` รันเมื่อแก้ `supabase/**`, `package*.json` ที่ root หรือ `ci.yml` (ทุก branch/PR; job `web` ตัดสินแล้วส่ง output จึงไม่เสียนาทีเปิด runner เมื่อไม่ต้องรัน) → `npm ci` ที่ root → `supabase db start` → `npm run db:test`; ไม่แตะ `kemi-dev`; รอบแรกบน GitHub ผ่าน 33 ข้อ (db 1m48s ส่วนใหญ่เป็นการโหลด image — `db start` โหลด image ของ gotrue/storage/realtime มาเตรียม schema ด้วย แม้ไม่เปิดทั้งชุด); ตรวจเงื่อนไขข้าม/รันกับ commit เก่าแล้วถูก 4 กรณี; ยืนยันบน GitHub 30 ก.ย.: push ที่แก้แค่เว็บ (`c3b279a`, run 36739609229) → `web` success, `db` **skipped**
- [x] P1-07 **[effort สูง]** migration `0002_accounts` + `ensure_account()` + ทดสอบ (allowlist, ไม่เชื่อ user_metadata, anon ถูกปฏิเสธ) · (ต้องมี: kemi-dev) → 30 ก.ย. 2026: `public.accounts`/`public.teachers` + `private.teacher_allowlist`; `private.current_account()` (DEFINER, EXECUTE ให้ authenticated, ไม่มี USAGE) ใช้ใน policy `accounts_select_own`; `require_teacher(p_admin_mode)`/`require_admin()` ไม่ GRANT ใคร; ensure_account อ่านตัวตนจาก `auth.identities` เท่านั้น — pgTAP 0002 50 ข้อ (รวม 83) ผ่านในเครื่องและบน `kemi-dev` PG17; ลองสิทธิ์ผิด 3 แบบ (ให้ USAGE / ถอน EXECUTE → policy พัง “permission denied for function” / policy `true`) เทสต์จับได้ครบ; dev ไม่มีข้อมูลทดสอบค้าง; Advisor ไม่มี error มี WARN `authenticated_security_definer_function_executable` ของ `ensure_account()` (ตามแบบ: RPC ทุกตัวจะขึ้น WARN นี้)
    - ค่าที่เลือกเอง: allowlist อยู่ใน `private`; ตรึงด้วยอีเมลเฉพาะรายการที่ยังไม่มี provider_subject และเฉพาะอีเมลที่ Google ยืนยันแล้ว; บัญชี provider `email` เป็นครูได้ด้วย provider_subject เท่านั้น (กันเปิด allow_test_logins ผิดที่แล้วอ้างอีเมลครู); ถูกเอาออกจาก allowlist → เป็นนักเรียนตอนเรียก ensure_account ครั้งถัดไป (RPC จัดการครูใน 0003 ต้องอัปเดต accounts ทันทีด้วย); รหัสข้อผิดพลาดใหม่ `not_authenticated`, `provider_not_allowed`, `account_conflict`, `account_required`, `forbidden`, `admin_mode_required`
- [ ] P1-08 หน้าเว็บ: Supabase client, ล็อกอิน Google, callback, แยกหน้าตามบทบาท, หน้า A01 · (ต้องมี: Google OAuth + kemi-dev)
  - [x] P1-08.0 Toast แสดงเหนือ Sheet/Modal ที่เปิดอยู่ + เทสต์ → 30 ก.ย. 2026: `ui/dialogStack.ts` (store กล่องที่เปิด ใช้ร่วมกับ Esc/Tab) + ช่อง toast (`role="status"`) ในทุกกล่องที่เปิดและในหน้าหลัก แสดงรายการในช่องของกล่องบนสุดเท่านั้น (ไม่ใช้ popover เพราะ modal ทำให้ส่วนอื่น inert → เครื่องอ่านหน้าจอไม่อ่าน) — Vitest store 2 ข้อ (รวม 17); Playwright 61/61: toast จากในกล่องอยู่ใน `dialog[open]` และเป็นองค์ประกอบบนสุด ณ ตำแหน่งนั้น, ปิดกล่องแล้วย้ายกลับหน้าหลักและยังมองเห็น
  - [ ] P1-08a `lib/`: Supabase client (PKCE), รับ path กลับหลังล็อกอินแบบปลอดภัย, แปลงรหัสข้อผิดพลาดตาม UX 7.1 + Vitest; `.env.example`; type จากฐานข้อมูล
  - [ ] P1-08b router + AuthProvider (`ensure_account()`) + A01 + `/auth/callback` + หน้าว่างตามบทบาท (นักเรียน `/`, ครู `/t`, ผู้ดูแล `/admin`)
  - [ ] P1-08c ผู้ใช้ตั้ง Supabase Dashboard (Site URL/Redirect URLs localhost) + allowlist 3 บัญชีบน kemi-dev ด้วย SQL (ถามผู้ใช้ก่อน ไม่ลงไฟล์) + ผู้ใช้ลองล็อกอินทั้ง 3 บัญชีบน localhost
- [ ] P1-09 Cloudflare Pages + `_headers` (CSP) + ตัวแปร build แล้วตรวจรับระยะ 1 (จุดสาธิต 1: ทดสอบบัญชีโรงเรียน) · (ต้องมี: ชื่อเว็บ, GitHub remote)

## ระยะ 2 — บัญชี รายชื่อ ห้อง

- [ ] P2-01 migration `0003` ส่วนแรก: terms, term_control, students, roster_entries + RPC นำเข้า + ทดสอบ
  - โน้ต: policy ฝั่งครูใน 0003 ต้องใช้ฟังก์ชันช่วยใน `private` ที่ **คืน boolean** (เช่น `private.is_teacher_or_admin()`) แบบ SECURITY DEFINER + GRANT EXECUTE ให้ authenticated — `require_teacher()` ใช้ใน policy ไม่ได้เพราะ raise error
  - [ ] P2-01a **[effort สูง]** (ทำหลัง P1-03 หรือพร้อม P2-01) pgTAP เทียบรายชื่อฟังก์ชันที่ `authenticated`/`anon` execute ได้ใน public/private กับรายการที่ตั้งใจไว้ ล้มเมื่อมีตัวเกิน (TECHNICAL_BUILD_PLAN §11)
- [ ] P2-02 T05 นำเข้า Excel (ตัวอย่างก่อนบันทึก ตรวจซ้ำ ศูนย์นำหน้า) · (ต้องมี: ไฟล์ Excel ตัวอย่าง)
- [ ] P2-03 **[effort สูง]** `search_roster` + `claim_identity` (L3, rate limit) + ทดสอบชิงชื่อพร้อมกัน
- [ ] P2-04 A02 ป๊อปอัปเลือกชื่อ
- [ ] P2-05 **[effort สูง]** classrooms, memberships, สร้างรหัส, lookup/join ด้วยรหัสและลิงก์เชิญ, ปิด/เปิดการเข้าห้อง + ทดสอบ
- [ ] P2-06 T01, T09, T08 (แท็บสมาชิก), T10
- [ ] P2-07 S01 เข้าห้อง + `/join/:code` + A01 แบบลิงก์เชิญ + S06
- [ ] P2-08 **[effort สูง]** แก้ผูก (ลบ session เดิม) + UI ใน T05 + ทดสอบ
- [ ] P2-09 allowlist ครู (≥ 1 บัญชี) + D01 ส่วนบัญชีครู + โหมดผู้ดูแลและแถบเตือน (L6) + T12
- [ ] P2-10 ตรวจรับระยะ 2 ตาม BUILD_PLAN ส่วน 10

## ระยะ 3 — งานและไฟล์

- [ ] P3-01 migration `0004` (posts, assignments, solutions, assets, attachments, upload_batches, storage_settings, backup_runs, backup_manifests) + ทดสอบ
- [ ] P3-02 T02 สร้างงาน/ประกาศ (K1, ตัวห้อย/ตัวยก, รายละเอียด/ไฟล์ไม่บังคับ) + รายการโพสต์ใน S02
- [ ] P3-02b โหมดแก้ไขงาน/ประกาศหลังโพสต์ (N2 ช่องที่ล็อก, N1 ไม่มีแจ้งเตือน + “แก้ไขล่าสุด”) + ทดสอบ
- [ ] P3-03 ไฟล์ตั้งค่า B2 (`ops/b2/cors.json`, `lifecycle.json`) + `_shared/b2.ts` + `uploads` ขั้นสร้าง batch · (ต้องมี: B2 + key ใน secrets)
- [ ] P3-04 **[effort สูง]** `uploads` ขั้น complete (HEAD, Range, CopyObject ระบุเวอร์ชัน, finalize) + ทดสอบกับ bucket dev
- [ ] P3-05 **[effort สูง]** `files` (sign GET โหมดเปิดดู/ดาวน์โหลด ชื่อไฟล์ไทย) + `authorize_files` + ทดสอบข้ามคน
- [ ] P3-06 โมดูลอัปโหลดฝั่งเว็บ (ตรวจไฟล์, HEIC, ย่อรูป, PUT แสดงความคืบหน้า) + unit test
- [ ] P3-07 **[effort สูง]** migration `0005` submissions + ตารางรับการส่ง 7 แถว + ทดสอบ
- [ ] P3-08 S03 ไฟล์โจทย์ (เปิดดู/ดาวน์โหลด) + ส่ง/ส่งแก้/สถานะ
- [ ] P3-09 T08 รายการงาน + T03 รายการสถานะ + การ์ดโจทย์และไฟล์ + ตัวดูไฟล์เบื้องต้น
- [ ] P3-10 **[effort สูง]** `process-jobs` ขั้นต่ำ + `pg_cron` (ลบไฟล์ที่ถูกแทน, sweeper) + นับพื้นที่ + หน้าจอพื้นที่เต็ม
- [ ] P3-11 `backup.yml` แบบพื้นฐานกับ dev · (ต้องมี: บัญชี Drive สำรอง, rclone config, Healthchecks.io)
- [ ] P3-12 ทดสอบอุปกรณ์จริงและตรวจรับระยะ 3 (จุดสาธิต 2)

## ระยะ 4 — ตรวจงานและคะแนน

- [ ] P4-01 **[effort สูง]** migration `0006` grades/comments + `grade_submission` (L2, L4, K1, K2) + ทดสอบชุดสูตรคะแนน
- [ ] P4-02 **[effort สูง]** สิทธิ์แก้ (K3) + ความคิดเห็น/ยกเลิก (F5) + ทดสอบ
- [ ] P4-03 **[effort สูง]** เปลี่ยนกำหนดส่งสองทิศ (N3, I2) / ปิดรับ / เฉลย (K4) + ทดสอบ
- [ ] P4-04 T03 หน้าตรวจ: ตัวดูรูป/PDF + แผงคะแนน + ปรับหักรายคน
- [ ] P4-05 T03 ความคิดเห็น + ปุ่มสิทธิ์แก้ + หน้าต่าง M1–M3
- [ ] P4-06 S03 ฝั่งนักเรียน: ผลตรวจ เฉลย ความคิดเห็น
- [ ] P4-07 T04 ตารางคะแนน + CSV (UTF-8 BOM)
- [ ] P4-08 รายการไฟล์ของการส่ง + ดาวน์โหลด PDF รวม
- [ ] P4-09 **[effort สูง]** ลบงาน/ประกาศแบบ cascade (N4) + หน้าต่างยืนยัน + ทดสอบ
- [ ] P4-10 ตรวจรับระยะ 4

## ระยะ 5 — รางวัลและสะสม

- [ ] P5-01 **[effort สูง]** migration `0007` + ให้รางวัลในรอบเดียวกับผลตรวจ + seed ระดับ/เครื่องราง 12 ชิ้น + ทดสอบ
- [ ] P5-02 **[effort สูง]** สุ่ม (K6) + อัตราจริง + ปรับยอด + ทดสอบคำขอพร้อมกัน
- [ ] P5-03 S04 สุ่ม + เอฟเฟกต์ + เอฟเฟกต์ได้รับโทเคนครั้งเดียว
- [ ] P5-04 S05 ตู้สะสม + สวมใส่ + แสดงในแท็บสมาชิก
- [ ] P5-05 T06 จัดการเครื่องราง + อัตรา + อัปโหลดรูป
- [ ] P5-06 **[effort สูง]** migration `0008` เริ่ม/จบภาคเรียน (K5, J9, I5) + ทดสอบ
- [ ] P5-07 T07 หน้าภาคเรียน + สถานะหลังจบภาคเรียนในทุกหน้าที่เกี่ยวข้อง
- [ ] P5-08 ตรวจรับระยะ 5 (จุดสาธิต 3)

## ระยะ 6 — แจ้งเตือนและงานเบื้องหลัง

- [ ] P6-01 migration `0009` notifications + สร้างเหตุการณ์ (นักเรียน 5 / ครู 3) + ทดสอบ
- [ ] P6-02 **[effort สูง]** งานเตือน 24 ชม. (J7, L5) ใน `process-jobs` + ทดสอบ
- [ ] P6-03 C01 + T11 กระดิ่ง
- [ ] P6-04 เทียบยอดพื้นที่ B2 + เกณฑ์ 80/90/100% + แผงพื้นที่และงานล้มเหลวใน D01
- [ ] P6-05 **[effort สูง]** migration `0010` เก็บตามอายุ/ส่งออก/ยืนยันลบ/ลบก่อนกำหนด + ทดสอบ
- [ ] P6-06 T07 แถวข้อมูลเก่า + ดาวน์โหลด ZIP
- [ ] P6-07 ตรวจรับระยะ 6

## ระยะ 7 — สำรองและความพร้อม

- [ ] P7-01 **[effort สูง]** `backup.yml` ฉบับเต็ม + job `guard`
- [ ] P7-02 **[effort สูง]** `restore-test.yml` (Supabase ชั่วคราวใน runner)
- [ ] P7-03 แผงสำรองและผลทดสอบกู้คืนใน D01
- [ ] P7-04 **[effort สูง]** รายการความปลอดภัย BUILD_PLAN ส่วน 11 + แก้สิ่งที่พบ
- [ ] P7-05 ทดสอบภาระ อุปกรณ์จริง และการเข้าถึง
- [ ] P7-05b หน้าแรกสาธารณะและหน้านโยบายความเป็นส่วนตัว `/privacy` (ข้อมูลที่เก็บ ที่เก็บ สิงคโปร์/สหรัฐฯ อายุข้อมูล ผู้เห็นข้อมูล ช่องทางติดต่อ) · (ต้องมี: นโยบายของโรงเรียน J9.3 และข้อความที่ผู้ใช้ตรวจแล้ว)
- [ ] P7-06 เตรียมระบบใช้จริง (migration, seed, allowlist, caps, CORS, redirect) + ใส่ homepage/privacy URL แล้วเผยแพร่ OAuth consent ของ Google เป็น In production · (ต้องได้รับอนุญาตจากผู้ใช้ทุกขั้น)
- [ ] P7-07 ตรวจรับระยะ 7 (จุดสาธิต 4)

## ระยะ 8 — นำร่องและเปิดใช้

- [ ] P8-01 นำเข้ารายชื่อห้องนำร่อง + ครูตั้งห้องและโพสต์งานจริง (ทำร่วมกับผู้ใช้)
- [ ] P8-02 ติดตามและแก้ปัญหาระหว่างนำร่อง (เพิ่มงานย่อยตามที่พบ)
- [ ] P8-03 สรุปผลตามข้อ 65 และเปิดครบ 3 ห้อง (จุดสาธิต 5)

## บันทึกการตัดสินใจระหว่างพัฒนา

- (เพิ่มเมื่อใช้ค่า [ข้อเสนอ] หรือผู้ใช้ตัดสินใจเรื่องทางเทคนิค: วันที่ · เรื่อง · ผล)
