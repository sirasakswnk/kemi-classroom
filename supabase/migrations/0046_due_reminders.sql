-- 0046_due_reminders: งานเตือน 24 ชม. ก่อนกำหนดส่ง — ตั้ง/เลื่อน/ยกเลิก + ฟังก์ชันสร้างแจ้งเตือน (P6-02a)
-- TECHNICAL_DESIGN ส่วน 11 · SYSTEM_SPEC J7, L5, N3
-- หลัก:
--   - งานเตือนหนึ่งแถวต่องานใน private.jobs (kind = 'due_reminder', dedupe_key = assignment_id)
--     run_at = due_at − 24 ชม. · payload { assignment_id, due_at } = กำหนดที่ตั้งงานเตือนไว้
--   - ตั้งเมื่อโพสต์งานถ้ากำหนดห่างจาก published_at ตั้งแต่ 24 ชม. (J7: เหลือน้อยกว่า 24 ชม. ไม่เตือน)
--   - เปลี่ยนกำหนด/ปิดรับ/เปิดรับอีกครั้ง: ประเมินใหม่จากเวลาที่ทำคำสั่ง (L5, N3 ทั้งสองทิศ)
--       กำหนดห่างตั้งแต่ 24 ชม. และยังรับงาน → ตั้งใหม่ที่ new_due − 24 ชม. (แม้งานเดิมทำไปแล้ว — คนที่เคยได้เตือนถูกข้าม
--       ด้วย dedupe_key ของแจ้งเตือน reminder:{assignment_id}:{student_id} จึงเตือนไม่เกินครั้งเดียวต่อคนต่องาน)
--       ไม่ถึง 24 ชม. หรือปิดรับแล้ว → ยกเลิกงานที่ยังรอ (status done, last_error 'cancelled')
--   - ลบงาน → ยกเลิกงานที่ยังรอ
--   - ตั้ง/เลื่อนเฉพาะคำสั่งของผู้ใช้ (เหมือน 0045) ส่วนการยกเลิกทำเสมอ
--   - จุดเชื่อม private.assignment_event (0028) ยังว่างไว้: trigger ครอบเหตุการณ์ชุดเดียวกันแล้ว
--   - private.send_due_reminders ตรวจสถานะล่าสุดก่อนสร้าง (กำหนดตรง payload, ยังไม่ถึงกำหนด, ยังรับงาน, ภาคเรียนปัจจุบัน)
--     ตัวรันใน process-jobs เรียกผ่าน RPC ของ service_role ใน P6-02b

-- ---------------------------------------------------------------------------
-- 1. ตั้ง/เลื่อน/ยกเลิก (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
create function private.cancel_due_reminder(p_assignment_id uuid)
returns void
language sql
set search_path = ''
as $$
  update private.jobs j
     set status = 'done', locked_at = null, last_error = 'cancelled', updated_at = clock_timestamp()
   where j.kind = 'due_reminder' and j.dedupe_key = p_assignment_id::text and j.status in ('pending', 'running')
$$;

-- p_basis: เวลาที่ใช้วัดว่ากำหนดห่างพอไหม (published_at ตอนโพสต์ · clock_timestamp() ตอนเปลี่ยน)
create function private.schedule_due_reminder(p_assignment_id uuid, p_basis timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_now timestamptz := clock_timestamp();
begin
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  if not found or v_assignment.due_at - p_basis < interval '24 hours'
     or private.assignment_intake(p_assignment_id, v_now) <> 'open' then
    perform private.cancel_due_reminder(p_assignment_id);
    return;
  end if;
  insert into private.jobs (kind, payload, dedupe_key, run_at)
  values ('due_reminder',
          jsonb_build_object('assignment_id', p_assignment_id, 'due_at', v_assignment.due_at),
          p_assignment_id::text, v_assignment.due_at - interval '24 hours')
  on conflict (kind, dedupe_key) do update
     set payload = excluded.payload, run_at = excluded.run_at, status = 'pending', attempts = 0,
         locked_at = null, last_error = null, updated_at = v_now;
end
$$;

create function private.assignments_due_reminder()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform private.cancel_due_reminder(old.post_id);
    return null;
  end if;
  if auth.uid() is null then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform private.schedule_due_reminder(new.post_id,
                                          (select p.published_at from public.posts p where p.id = new.post_id));
  else
    perform private.schedule_due_reminder(new.post_id, clock_timestamp());
  end if;
  return null;
end
$$;
create trigger assignments_due_reminder_insert after insert on public.assignments
  for each row execute function private.assignments_due_reminder();
create trigger assignments_due_reminder_update after update of due_at, closed_at, after_solution_closed_at
  on public.assignments
  for each row when (old.due_at is distinct from new.due_at
                     or old.closed_at is distinct from new.closed_at
                     or old.after_solution_closed_at is distinct from new.after_solution_closed_at)
  execute function private.assignments_due_reminder();
create trigger assignments_due_reminder_delete after delete on public.assignments
  for each row execute function private.assignments_due_reminder();

-- เผยแพร่เฉลย = ปิดรับตามกติกา (หรือช่วงหลังเฉลยซึ่งเลยกำหนดแล้ว) → ยกเลิก
create function private.solutions_due_reminder()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.cancel_due_reminder(new.assignment_id);
  return null;
end
$$;
create trigger solutions_due_reminder_insert after insert on public.solutions
  for each row when (new.published_at is not null)
  execute function private.solutions_due_reminder();
create trigger solutions_due_reminder_update after update of published_at on public.solutions
  for each row when (old.published_at is null and new.published_at is not null)
  execute function private.solutions_due_reminder();

-- ---------------------------------------------------------------------------
-- 2. สร้างแจ้งเตือน “ใกล้กำหนด” (ไม่ GRANT ใคร — P6-02b ห่อเป็น RPC ของ service_role)
-- ---------------------------------------------------------------------------
-- ผล: จำนวนแจ้งเตือนที่สร้างใหม่ (0 เมื่องานเตือนไม่เกี่ยวข้องแล้ว หรือทุกคนเคยได้เตือน/ส่งแล้ว)
create function private.send_due_reminders(p_assignment_id uuid, p_due_at timestamptz,
                                           p_now timestamptz default clock_timestamp())
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_assignment public.assignments;
  v_classroom public.classrooms;
  v_count integer;
begin
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id for share;
  if not found or v_assignment.due_at is distinct from p_due_at or p_now >= v_assignment.due_at
     or p_now < v_assignment.due_at - interval '24 hours'
     or private.assignment_intake(p_assignment_id, p_now) <> 'open' then
    return 0;
  end if;
  select c.* into v_classroom
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id;
  if not exists (select 1 from public.term_control t
                  where t.singleton and t.status = 'active' and t.term_id = v_classroom.term_id) then
    return 0;
  end if;
  insert into public.notifications (recipient_student_id, kind, post_id, dedupe_key, created_at, updated_at)
  select m.student_id, 'due_reminder', p_assignment_id, 'reminder:' || p_assignment_id || ':' || m.student_id, p_now, p_now
    from public.memberships m
   where m.classroom_id = v_classroom.id
     and not exists (select 1 from public.submissions s
                      where s.assignment_id = p_assignment_id and s.student_id = m.student_id)
  on conflict (dedupe_key) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;
