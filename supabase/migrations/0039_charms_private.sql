-- 0039_charms_private: ปิดตาราง charms จากนักเรียน (ผู้ใช้ตัดสิน 24 ต.ค. 2026)
-- ครู/ผู้ดูแลอ่านได้ทั้งหมด (T06, แท็บสมาชิกของครู); นักเรียนได้ข้อมูลเครื่องรางผ่าน RPC เท่านั้น:
--   my_collection (เฉพาะชิ้นที่มี), ผล draw_charm (ชิ้นที่เพิ่งได้), classroom_view (ชิ้นที่สมาชิกเลือกแสดง),
--   get_draw_options (อัตราตามระดับ ไม่มีรายชิ้น) — ชื่อ/สัญลักษณ์/คำอธิบายของชิ้นที่ยังไม่ได้รับจึงไม่ถึงนักเรียน
-- rarities ยังเปิดอ่าน (ชื่อระดับและน้ำหนักแสดงใน S04 อยู่แล้ว)
drop policy charms_select_all on public.charms;
create policy charms_select_staff on public.charms
  for select to authenticated
  using ((select private.is_teacher_or_admin()));
