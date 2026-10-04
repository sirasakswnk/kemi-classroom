-- 0006_teachers_read: ครูและผู้ดูแลอ่านรายชื่อครูได้ — ชื่อครูบนแถบบนของหน้าครู และให้ผู้ดูแลในโหมดผู้ดูแล
-- เลือกครูเจ้าของห้องตอนสร้างชั้นเรียน (T09); นักเรียนไม่ได้อ่านตารางนี้ตรง (ชื่อครูของห้องมากับ RPC/การอ่านห้อง)
grant select on public.teachers to authenticated;

create policy teachers_select on public.teachers
  for select to authenticated
  using ((select private.is_teacher_or_admin()));
