# ตั้งค่า Backblaze B2 สำหรับ kemi-dev (P3-03)

ทำกับ bucket `kemi-dev-files` เท่านั้น (`kemi-files` ของจริงตั้งในระยะ 7)

## กติกาความลับ

- ห้ามวางกุญแจในแชต และห้ามเก็บกุญแจลงไฟล์ใน repo
- สคริปต์ในโฟลเดอร์นี้ถามกุญแจแบบซ่อนตัวอักษร ต้องรันใน **PowerShell หรือ Windows Terminal** (ไม่ใช่ Git Bash)
- สคริปต์ไม่พิมพ์กุญแจหรือลิงก์ที่ลงลายเซ็นแล้ว ส่วนที่พิมพ์ออกมาส่งให้ Claude ได้ทั้งหมด
- เพดานรายวันของ B2 ใช้ร่วมกันทั้งบัญชี เทสต์กับ B2 จริงจึงรันด้วยมือเมื่อจำเป็นเท่านั้น ไม่รันใน CI

## 1. สร้าง bucket (หน้าเว็บ Backblaze)

1. ไปที่ **B2 Cloud Storage → Buckets → Create a Bucket**
2. ตั้งค่าดังนี้:
   - Bucket Unique Name: `kemi-dev-files`
   - Files in Bucket are: **Private**
   - Default Encryption: **Disable** (ข้อเสนอ)
   - Object Lock: **Disable** เพราะระบบต้องลบไฟล์ตาม version ได้
3. ดูการ์ดของ bucket ช่อง **Endpoint** ต้องเป็น `s3.eu-central-003.backblazeb2.com` ถ้าไม่ใช่ให้หยุดแล้วแจ้ง Claude

## 2. ตั้ง CORS และ lifecycle (สคริปต์)

ใช้ค่าจาก `cors.json` และ `lifecycle.json` ในโฟลเดอร์นี้

```powershell
node ops/b2/apply-settings.mjs
```

1. สคริปต์ถาม **Master keyID** และ **Master applicationKey**
   - หาได้ที่ Application Keys → Master Application Key
   - ถ้าไม่มีค่าเดิมเก็บไว้ ให้กด Generate New Master Application Key (ค่าเก่าจะใช้ไม่ได้)
2. สคริปต์ใช้กุญแจหลักเพื่อสร้างกุญแจชั่วคราวเท่านั้น กุญแจชั่วคราว:
   - ใช้ได้เฉพาะ bucket นี้
   - มีสิทธิ์ `listBuckets` และ `writeBuckets`
   - อายุ 1 ชั่วโมง
3. สคริปต์ใช้กุญแจชั่วคราวตั้ง CORS และ lifecycle แล้วอ่านค่ากลับมาแสดง
4. สุดท้ายสคริปต์ลบกุญแจชั่วคราวทิ้งเสมอ แม้ขั้นก่อนหน้าจะล้ม
5. ส่งผลที่พิมพ์ออกมาให้ Claude (ไม่มีค่าลับ)

## 3. สร้างกุญแจของ Edge Function (หน้าเว็บ Backblaze)

1. ไปที่ **Application Keys → Add a New Application Key** แล้วตั้งค่าดังนี้:
   - Name of Key: `kemi-edge-dev`
   - Allow access to Bucket(s): `kemi-dev-files` (ห้ามเลือก All)
   - Type of Access: **Read and Write**
   - Allow List All Bucket Names: ไม่ติ๊ก
   - File name prefix และ Duration: เว้นว่าง
2. หลังกด Create New Key ให้ดูกล่อง **“Success! Your new application key has been created…”** ที่**บนสุดของหน้า** (อาจต้องเลื่อนขึ้น)
   - `applicationKey` อยู่ในกล่องนี้เท่านั้น และแสดง**ครั้งเดียว** ให้เปิดหน้านี้ค้างไว้จนจบขั้น 4–5
   - รายการกุญแจด้านล่าง (keyID, keyName, bucketName, capabilities, expiration, namePrefix) ไม่มี `applicationKey`
   - ถ้ากล่องหายไปแล้ว (รีเฟรชหรือออกจากหน้า) จะดูค่าเดิมไม่ได้อีก ให้กด Delete ที่กุญแจนั้นแล้วสร้างใหม่

## 4. ใส่ค่าใน Supabase Edge Function secrets (kemi-dev)

ไปที่ Supabase Dashboard → โปรเจกต์ **kemi-dev** → **Edge Functions → Secrets** แล้วเพิ่มค่าเหล่านี้:

| ชื่อ | ค่า |
| --- | --- |
| `B2_KEY_ID` | keyID จากขั้น 3 |
| `B2_APP_KEY` | applicationKey จากขั้น 3 |
| `B2_BUCKET` | `kemi-dev-files` |
| `B2_ENDPOINT` | `https://s3.eu-central-003.backblazeb2.com` |

## 5. พิสูจน์พฤติกรรมของ B2 (สคริปต์ รันด้วยมือ)

```powershell
node ops/b2/proof.mjs
```

1. วาง keyID และ applicationKey ของ `kemi-edge-dev` ในช่องที่ซ่อนตัวอักษร
2. สคริปต์ใช้คำขอประมาณนี้:
   - PUT 3 ครั้งและ DELETE 1 ครั้ง (Class A ไม่นับเพดาน)
   - GET 1 ครั้งขนาด 16 ไบต์ (Class B)
   - OPTIONS 4 ครั้ง
3. สิ่งที่ตรวจ:
   - PUT ที่ชนิดหรือขนาดไม่ตรงลายเซ็นถูกปฏิเสธ
   - GET แบบ Range ได้ `x-amz-version-id` และ `Content-Range`
   - `response-cache-control`, `response-content-type` และ `response-content-disposition` (ชื่อไทย) ทำงาน
   - ชนิดของ ETag
   - CORS
   - ลบตาม version ได้
4. ไฟล์ทดสอบอยู่ใต้ `staging/` และถูกลบท้ายสคริปต์ ถ้าลบไม่ได้ lifecycle จะล้างให้ภายใน 2 วัน
5. ส่งผลที่พิมพ์ออกมาให้ Claude แล้วปิดหน้ากุญแจของ B2

## หมายเหตุ

- **สิทธิ์ของกุญแจ:**
  - ตัวเลือก Read and Write ในหน้าเว็บให้สิทธิ์อ่าน เขียน ลบ และ list ไฟล์ใน bucket นี้ (รวม `shareFiles` และการอ่าน/เขียนค่าเข้ารหัสของ bucket)
  - ไม่มี `writeBuckets` หรือ `deleteBuckets` และไม่มีสิทธิ์จัดการกุญแจ
  - ถ้าต้องการให้แคบลงเหลือ `listBuckets, readFiles, writeFiles, deleteFiles` ต้องสร้างผ่าน API หรือ CLI (ทำได้ในระยะ 7)
- **เกินเพดาน:** B2 ตอบ HTTP 403 รหัส `cap_exceeded` หรือ `download_cap_exceeded` พร้อมข้อความ "… cap exceeded …"
  - เพดานดาวน์โหลดกันการคัดลอกฝั่งเซิร์ฟเวอร์ (CopyObject) ด้วย
  - ห้ามทดสอบด้วยการใช้จนเกินเพดานจริง
- **CORS ของ bucket ใช้จริง:** ระยะ 7 ใช้เฉพาะ `https://kemi-classroom.pages.dev` (เอา preview และ localhost ออก)
