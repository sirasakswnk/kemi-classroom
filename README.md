# ห้องเคมี (kemi-classroom)

เว็บส่งการบ้านเคมีสำหรับครู 1 คน และนักเรียน ม.5 ประมาณ 125 คน (3 ห้อง): นักเรียนส่งรูป/PDF ครูตรวจและให้คะแนน นักเรียนได้โทเคนไปสุ่มเครื่องราง

- บริการ: Cloudflare Pages + Supabase (สิงคโปร์) + Backblaze B2 + สำรองลง Google Drive
- หน้าเว็บ: React + TypeScript (Vite) อยู่ใน `web/`

## เอกสาร

| ไฟล์ | เนื้อหา |
| --- | --- |
| `SYSTEM_SPEC.md` | กติกาธุรกิจ (ความจริงสูงสุด) |
| `TECHNICAL_DESIGN.md` | แบบข้อมูล สิทธิ์ API ไฟล์ สำรอง |
| `UX_DESIGN.md` + `exports/chemistry-design-v2.html` | หน้าจอและข้อความ |
| `TECHNICAL_BUILD_PLAN.md` | ลำดับงาน วิธีสร้าง ตรวจรับ |
| `DEVELOPMENT_PLAN.md` | ภาพรวมแผน |
| `PROGRESS.md` | สถานะงานทีละขั้น |
| `CLAUDE.md` | กฎการทำงานสำหรับ Claude Code |

## ข้อห้าม

ห้าม commit ความลับ (`.env*`, key, token) และข้อมูลนักเรียนจริง (Excel/CSV รายชื่อ คะแนน dump รูปงาน)
