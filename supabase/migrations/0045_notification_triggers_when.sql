-- 0045_notification_triggers_when: เงื่อนไขของ trigger แจ้งเตือน (0044) ย้ายไปที่ WHEN (P6-01c)
-- - ทำงานเฉพาะคำสั่งของผู้ใช้ (auth.uid() มีค่า): งานเป็นชุดที่ไม่มีผู้ใช้ในคำขอ — กู้ข้อมูล (pg_restore), seed,
--   SQL ตรงของผู้ดูแลระบบ, Edge Function ในนาม service_role — ไม่สร้างแจ้งเตือน
--   (เตือนใกล้กำหนดของ P6-02 สร้างโดยตัวรันงาน ไม่ผ่าน trigger เหล่านี้)
-- - trigger แบบ update ทำงานเมื่อคอลัมน์ที่เกี่ยวข้องเปลี่ยนจริง (IS DISTINCT FROM) ไม่ใช่แค่อยู่ในคำสั่ง SET
-- - แก้โจทย์/ชื่อ/ไฟล์ของงานไม่แจ้ง (N1): posts มีแค่ trigger ตอนเพิ่ม และ attachments ไม่มี trigger แจ้งเตือน
-- - หนึ่งโพสต์อยู่ห้องเดียว (posts.classroom_id) งานรอตรวจต่องานจึงเป็นต่อห้องอยู่แล้ว

drop trigger posts_notify on public.posts;
create trigger posts_notify after insert on public.posts
  for each row when (auth.uid() is not null)
  execute function private.posts_notify();

drop trigger comments_notify on public.comments;
create trigger comments_notify after insert on public.comments
  for each row when (auth.uid() is not null)
  execute function private.comments_notify();

drop trigger revision_permissions_notify on public.revision_permissions;
create trigger revision_permissions_notify after insert on public.revision_permissions
  for each row when (auth.uid() is not null)
  execute function private.revision_permissions_notify();

drop trigger submissions_notify on public.submissions;
create trigger submissions_notify_insert after insert on public.submissions
  for each row when (auth.uid() is not null)
  execute function private.submissions_notify();
create trigger submissions_notify_update after update of last_submitted_at on public.submissions
  for each row when (auth.uid() is not null and old.last_submitted_at is distinct from new.last_submitted_at)
  execute function private.submissions_notify();

drop trigger assignments_notify on public.assignments;
create trigger assignments_notify after update of due_at, close_at, closed_at, after_solution_closed_at
  on public.assignments
  for each row when (auth.uid() is not null
                     and (old.due_at is distinct from new.due_at
                          or old.close_at is distinct from new.close_at
                          or old.closed_at is distinct from new.closed_at
                          or old.after_solution_closed_at is distinct from new.after_solution_closed_at))
  execute function private.assignments_notify();

drop trigger solutions_notify on public.solutions;
create trigger solutions_notify_insert after insert on public.solutions
  for each row when (auth.uid() is not null and new.published_at is not null)
  execute function private.solutions_notify();
create trigger solutions_notify_update after update of published_at on public.solutions
  for each row when (auth.uid() is not null and old.published_at is null and new.published_at is not null)
  execute function private.solutions_notify();
