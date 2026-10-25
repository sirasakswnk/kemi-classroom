# กู้คืนด้วยมือ 1 ครั้ง (P7-02a) — ขั้นตอนฝั่งผู้ใช้

พิสูจน์ว่าสำรองของ `kemi-dev` ใช้กู้ได้จริง และรหัส crypt + salt จาก**สำเนาออฟไลน์**เปิดไฟล์ได้ (TECHNICAL_BUILD_PLAN ส่วน 10 แผนเปิดใช้เร็ว ข้อ 2, ส่วน 13 ข้อ 16 แบบย่อ)

> **กติกา:**
> - รหัส crypt + salt วางเองที่ `Read-Host -AsSecureString` ในข้อ 3 เท่านั้น (ขึ้นเป็น `*`) — **ห้ามวางในแชต ห้ามใส่ในคำสั่ง ห้ามบันทึกลงไฟล์** · ค่าอยู่ในตัวแปรสภาพแวดล้อมของหน้าต่างนี้ชั่วคราวและถูกลบในข้อ 5
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

## 3. remote ชั่วคราว: `gdrive` ใน config + `gcrypt` จากตัวแปรสภาพแวดล้อม

**`gdrive` (มี token จึงอยู่ใน config ชั่วคราว):**

```powershell
rclone config
```

`n` → name `gdrive` → Storage `drive` → client_id: วาง Client ID → client_secret: วาง Client secret → scope: **`drive.file`** → service_account_file: Enter → Edit advanced config: `n` → Use web browser to automatically authenticate: `y` → **ล็อกอินบัญชีสำรอง** → Allow → Configure this as a Shared Drive: `n` → Keep: `y` → `q`

**`gcrypt` (ไม่สร้างใน config):** สำเนาออฟไลน์ของ dev เก็บค่า**แบบ obscured** (ยาว 79 ตัว — ยืนยันด้วย workflow `crypt-check` 25 ต.ค.) ซึ่งใส่ในช่อง “type in my own password” ของ `rclone config` ไม่ได้ (ช่องนั้นรับรหัสจริง 43 ตัว) แต่ rclone รับค่า obscured ทางตัวแปรสภาพแวดล้อมได้โดยตรง — วางทั้งก้อนแล้ววางค่าจากสำเนาเมื่อถูกถาม:

```powershell
function Read-Secret([string]$label) {
  $sec = Read-Host -AsSecureString $label
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
$env:RCLONE_CONFIG_GCRYPT_TYPE = 'crypt'
$env:RCLONE_CONFIG_GCRYPT_REMOTE = 'gdrive:kemi-backup'
$env:RCLONE_CONFIG_GCRYPT_PASSWORD = Read-Secret 'password (obscured)'
$env:RCLONE_CONFIG_GCRYPT_PASSWORD2 = Read-Secret 'password2 (obscured)'
rclone lsf --dirs-only gcrypt:
```

บรรทัดสุดท้ายต้องเห็น `files/` และ `runs/` (ค่า filename_encryption `standard` / directory_name_encryption `true` เป็นค่าเริ่มต้นอยู่แล้ว)

## 4. ดึงจุดกู้คืนล่าสุด + ไฟล์ตัวอย่าง 3 ไฟล์ (อ่านอย่างเดียว)

```powershell
rclone lsf --dirs-only gcrypt:runs
```

ต้องเห็นชื่อรอบเป็นเวลา (เช่น `20261025T053012Z/`) — **ถ้าไม่มีรายการ หรือมีข้อความ `Skipping undecryptable` / `directory not found`** แปลว่ารหัส/salt ไม่ตรง: หยุดแล้วบอก Claude (อย่าเดาซ้ำหลายรอบ)

```powershell
$run = (rclone lsf --dirs-only gcrypt:runs | Sort-Object | Select-Object -Last 1).TrimEnd('/')
rclone copy "gcrypt:runs/$run" "$w\run" -v
$m = Import-Csv "$w\run\manifest.csv"
$pick = foreach ($ext in '.pdf', '.jpg', '.png') { $m | Where-Object { $_.final_key.EndsWith($ext) } | Select-Object -First 1 }
foreach ($f in $pick) { rclone copyto "gcrypt:$($f.final_key)" "$w\$($f.final_key)" -v }
Get-ChildItem -Recurse $w -File | Select-Object FullName, Length
```

ต้องเห็น `run\schema.dump`, `run\data.dump`, `run\manifest.csv`, `run\meta.json` และไฟล์ใต้ `files\` 2–3 ไฟล์ (ถ้า manifest ไม่มีบางชนิด จะได้น้อยกว่า 3)

## 5. ลบ config และตัวแปรชั่วคราว (ทำทันที แม้ข้อ 4 ไม่สำเร็จ)

```powershell
Remove-Item "$w\rclone-temp.conf"
Remove-Item Env:RCLONE_CONFIG, Env:RCLONE_CONFIG_GCRYPT_TYPE, Env:RCLONE_CONFIG_GCRYPT_REMOTE, Env:RCLONE_CONFIG_GCRYPT_PASSWORD, Env:RCLONE_CONFIG_GCRYPT_PASSWORD2
Test-Path "$w\rclone-temp.conf"
(Get-ChildItem Env: | Where-Object Name -like 'RCLONE_*').Count
```

สองบรรทัดสุดท้ายต้องเป็น `False` และ `0` (หรือปิดหน้าต่าง PowerShell นี้ไปเลย ตัวแปรก็หายด้วย) · ถ้าสร้าง client secret ใหม่ในข้อ 2 ลบ secret **ตัวใหม่** ทิ้งได้ที่หน้า Clients (ตัวเดิมห้ามแตะ)

## 6. แจ้ง Claude

พิมพ์ในแชตแค่ว่า “ดึงแล้ว” พร้อมชื่อรอบ (`$run`) — **ไม่ต้องส่งรหัสหรือเนื้อไฟล์** Claude จะอ่านโฟลเดอร์ `%TEMP%\kemi-restore` เอง แล้ว:

1. กู้ `schema.dump` + `data.dump` ลง Supabase ในเครื่อง (Docker) — schema ด้วย `pg_restore --clean --if-exists` แล้ว data ด้วย `--disable-triggers` ในชื่อ `supabase_admin` จากนั้นตั้ง `accounts.auth_user_id` เป็น NULL
2. เทียบ `meta.json` (จำนวน/ขนาดไฟล์) กับ `manifest.csv` และ `assets` ที่ ready ในฐานข้อมูลที่กู้ + นับแถวตารางหลัก
3. เทียบขนาด/MD5 ของไฟล์ตัวอย่างกับ `manifest.csv` และเปิดไฟล์ดูว่าเป็น PDF/รูปจริง
4. รายงานผลเป็นตาราง แล้ว `npm run db:reset` คืนฐานข้อมูลในเครื่อง และลบ `%TEMP%\kemi-restore` (ข้อมูลทดสอบสมมติ ไม่ใช่ข้อมูลจริง แต่ไม่เก็บไว้)
