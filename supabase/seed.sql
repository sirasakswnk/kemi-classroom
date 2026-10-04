-- ข้อมูลตั้งต้นของระบบ (TECHNICAL_BUILD_PLAN 4.2 — seed.sql)
-- Supabase ในเครื่องรันอัตโนมัติตอน `npm run db:reset`; kemi-dev/prod รันเองด้วย `npx supabase db query --linked -f supabase/seed.sql`
-- ทุกคำสั่งต้องรันซ้ำได้โดยไม่เกิดข้อมูลซ้ำ และห้ามมีข้อมูลนักเรียน (จริงหรือสมมติ)

-- ภาคเรียนแรก + ตัวควบคุมเทอม — ภาคเรียนถัดไปครูเริ่มเองในหน้าภาคเรียน (ระยะ 5)
-- [ข้อเสนอ] ชื่อภาคเรียนแรก รอผู้ใช้ยืนยัน
with first_term as (
  insert into public.terms (name)
  select 'ภาคเรียนที่ 2/2569'
   where not exists (select 1 from public.term_control)
  returning id
)
insert into public.term_control (term_id)
select id from first_term;
