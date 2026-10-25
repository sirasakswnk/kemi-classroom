# กู้คืนด้วยมือ 1 ครั้ง (P7-02a) — ขั้นตอนฝั่งผู้ใช้

พิสูจน์ว่าสำรองของ `kemi-dev` ใช้กู้ได้จริง และรหัส crypt + salt จาก**สำเนาออฟไลน์**เปิดไฟล์ได้ (TECHNICAL_BUILD_PLAN ส่วน 10 แผนเปิดใช้เร็ว ข้อ 2, ส่วน 13 ข้อ 16 แบบย่อ)

> **กติกา:**
> - รหัส crypt + salt พิมพ์เองที่ช่องรหัสของ `rclone config` เท่านั้น (ตัวอักษรไม่ขึ้นบนจอ) — **ห้ามวางในแชต ห้ามใส่ในคำสั่ง ห้ามบันทึกลงไฟล์**
> - ทุกคำสั่งในนี้**อ่านจาก Drive อย่างเดียว** — ห้ามรัน `rclone mkdir`, `copy … gcrypt:`, `delete`, `purge`, `sync` กับ remote ชุดนี้
> - ไม่แตะ `kemi-dev` และ B2 (ไฟล์ตัวอย่างอ่านจากสำเนาใน Drive)
> - config ชั่วคราวลบทิ้งในข้อ 5 · **อย่าเพิกถอนสิทธิ์แอปใน Google Account** (จะทำให้ token ของงานสำรองใน GitHub ใช้ไม่ได้ด้วย)

ใช้ PowerShell บนเครื่องตัวเอง (ติดตั้ง rclone แล้วตาม `ops/backup-setup.md` ข้อ 3.2) — เปิดหน้าต่างเดียวทำตั้งแต่ข้อ 1 ถึง 5

## 1. โฟลเดอร์งานและ config ชั่วคราว

```powershell
$w = "$env:TEMP\kemi-restore"
New-Item -ItemType Directory -Force $w | Out-Null
$env:RCLONE_CONFIG = "$w\rclone-temp.conf"
rclone config file
```

บรรทัดสุดท้ายต้องพิมพ์ที่อยู่ `...\kemi-restore\rclone-temp.conf` (ไม่ใช่ไฟล์ config เดิม) — ถ้าไม่ใช่ ให้หยุดแล้วบอก Claude

## 2. client ID/secret ของ OAuth client `rclone`

Google Cloud (ล็อกอินบัญชีสำรอง) → โปรเจกต์ `kemi-backup` → **Google Auth Platform → Clients → `rclone`**

- คัดลอก **Client ID**
- Client secret: ถ้าหน้าแสดงค่าเดิมไม่ได้ ให้กด **Add secret** สร้างค่าใหม่ — **ห้ามลบหรือปิด secret เดิม** (งานสำรองใน GitHub ใช้อยู่) — หลังจบงานนี้จะลบ secret ใหม่ทิ้งก็ได้ (ข้อ 5)

## 3. `rclone config` — สร้าง remote ชั่วคราว 2 ตัว

```powershell
rclone config
```

**remote `gdrive`:** `n` → name `gdrive` → Storage `drive` → client_id: วาง Client ID → client_secret: วาง Client secret → scope: **`drive.file`** → service_account_file: Enter → Edit advanced config: `n` → Use web browser to automatically authenticate: `y` → **ล็อกอินบัญชีสำรอง** → Allow → Configure this as a Shared Drive: `n` → Keep: `y`

**remote `gcrypt`:** `n` → name `gcrypt` → Storage `crypt` → remote: **`gdrive:kemi-backup`**
- filename_encryption: `standard` → directory_name_encryption: `true`
- password: เลือก **`y` (Yes, type in my own password)** → พิมพ์**รหัส crypt จากสำเนาออฟไลน์** → พิมพ์ยืนยันอีกครั้ง
- password2 (salt): เลือก **`y`** → พิมพ์ **salt จากสำเนาออฟไลน์** → ยืนยัน
- Edit advanced config: `n` → Keep: `y` → `q`

## 4. ดึงจุดกู้คืนล่าสุด + ไฟล์ตัวอย่าง 3 ไฟล์ (อ่านอย่างเดียว)

```powershell
rclone lsf --dirs-only gcrypt:runs
```

ต้องเห็นชื่อรอบเป็นเวลา (เช่น `20261025T053012Z/`) — **ถ้าไม่มีรายการ หรือมีข้อความ `failed to decrypt`** แปลว่ารหัส/salt ไม่ตรง: หยุดแล้วบอก Claude (อย่าเดาซ้ำหลายรอบ)

```powershell
$run = (rclone lsf --dirs-only gcrypt:runs | Sort-Object | Select-Object -Last 1).TrimEnd('/')
rclone copy "gcrypt:runs/$run" "$w\run" -v
$m = Import-Csv "$w\run\manifest.csv"
$pick = foreach ($ext in '.pdf', '.jpg', '.png') { $m | Where-Object { $_.final_key.EndsWith($ext) } | Select-Object -First 1 }
foreach ($f in $pick) { rclone copyto "gcrypt:$($f.final_key)" "$w\$($f.final_key)" -v }
Get-ChildItem -Recurse $w -File | Select-Object FullName, Length
```

ต้องเห็น `run\schema.dump`, `run\data.dump`, `run\manifest.csv`, `run\meta.json` และไฟล์ใต้ `files\` 2–3 ไฟล์ (ถ้า manifest ไม่มีบางชนิด จะได้น้อยกว่า 3)

## 5. ลบ config ชั่วคราว (ทำทันที แม้ข้อ 4 ไม่สำเร็จ)

```powershell
Remove-Item "$w\rclone-temp.conf"
Remove-Item Env:RCLONE_CONFIG
Test-Path "$w\rclone-temp.conf"
```

บรรทัดสุดท้ายต้องเป็น `False` · ถ้าสร้าง client secret ใหม่ในข้อ 2 ลบ secret **ตัวใหม่** ทิ้งได้ที่หน้า Clients (ตัวเดิมห้ามแตะ)

## 6. แจ้ง Claude

พิมพ์ในแชตแค่ว่า “ดึงแล้ว” พร้อมชื่อรอบ (`$run`) — **ไม่ต้องส่งรหัสหรือเนื้อไฟล์** Claude จะอ่านโฟลเดอร์ `%TEMP%\kemi-restore` เอง แล้ว:

1. กู้ `schema.dump` + `data.dump` ลง Supabase ในเครื่อง (Docker) — schema ด้วย `pg_restore --clean --if-exists` แล้ว data ด้วย `--disable-triggers` ในชื่อ `supabase_admin` จากนั้นตั้ง `accounts.auth_user_id` เป็น NULL
2. เทียบ `meta.json` (จำนวน/ขนาดไฟล์) กับ `manifest.csv` และ `assets` ที่ ready ในฐานข้อมูลที่กู้ + นับแถวตารางหลัก
3. เทียบขนาด/MD5 ของไฟล์ตัวอย่างกับ `manifest.csv` และเปิดไฟล์ดูว่าเป็น PDF/รูปจริง
4. รายงานผลเป็นตาราง แล้ว `npm run db:reset` คืนฐานข้อมูลในเครื่อง และลบ `%TEMP%\kemi-restore` (ข้อมูลทดสอบสมมติ ไม่ใช่ข้อมูลจริง แต่ไม่เก็บไว้)
