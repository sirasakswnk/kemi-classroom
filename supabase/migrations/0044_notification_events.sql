-- 0044_notification_events: สร้างแจ้งเตือนจากคำสั่งเดิม (P6-01b) — TECHNICAL_DESIGN ส่วน 11, SYSTEM_SPEC ส่วน 9
-- หลัก:
--   - สร้างใน trigger AFTER บนตารางที่คำสั่งเดิมเขียน จึงอยู่ในทรานแซกชันเดียวกับคำสั่ง:
--     คำสั่งล้ม → แจ้งเตือนย้อนตาม · คำสั่งเรียกซ้ำด้วย request_key เดิมคืนผลเก่าโดยไม่เขียนใหม่ trigger จึงไม่ทำงานซ้ำ
--     และทุกแถวมี dedupe_key (on conflict) กันซ้ำอีกชั้น
--   - การสร้างแจ้งเตือนอยู่ในบล็อก exception ของตัวเอง: ล้มแล้วย้อนเฉพาะแจ้งเตือน (raise warning) คำสั่งเดิมสำเร็จตามปกติ
--   - trigger เป็น SECURITY DEFINER: เขียนตาราง notifications ได้ไม่ว่าคำสั่งเดิมทำในนาม role ใด
--   - ผู้ทำคำสั่งเอง (ตัวคนของ auth.uid()) ไม่ได้แจ้งเตือนของตัวเอง
--   - ผู้รับฝั่งนักเรียน = สมาชิกห้อง ณ ตอนเกิดเหตุการณ์; ฝั่งครู = ครูเจ้าของห้อง
--   - “ใกล้กำหนด” (due_reminder) มาจาก P6-02 · “พื้นที่” (storage_threshold) มาจาก P6-04b
-- ชนิดที่รวมเป็นแถวเดียวแล้วเลื่อนเวลา + กลับเป็นยังไม่อ่านเมื่อเกิดซ้ำ:
--   pending_review (ต่องาน) · student_comment (ต่องานต่อนักเรียน) · due_changed / intake_closed (ต่องานต่อนักเรียน)
-- ชนิดที่เกิดครั้งเดียวต่อเป้าหมาย: post_published, solution_published (ต่องานต่อนักเรียน), teacher_comment (ต่อความคิดเห็น),
--   revision_opened (ต่อสิทธิ์แก้ที่เปิด)

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------

-- ตัวคนของผู้ทำคำสั่ง (ว่างทั้งคู่เมื่อไม่มีผู้ใช้ เช่นงานเบื้องหลัง หรือผู้ดูแล)
create function private.notify_actor(out student_id uuid, out teacher_id uuid)
language sql
stable
set search_path = ''
as $$
  -- คืนหนึ่งแถวเสมอ (ไม่มีผู้ใช้ → null ทั้งคู่) ไม่งั้นตัวแปร record ฝั่งผู้เรียกไม่ถูกกำหนดค่า
  select s.id, a.teacher_id
    from (select 1) one
    left join public.accounts a on a.auth_user_id = auth.uid()
    left join public.students s on s.account_id = a.id
$$;

-- แจ้งนักเรียนหลายคน: dedupe_key = p_key || ':' || student_id · p_bump = เกิดซ้ำแล้วเลื่อนเวลา/กลับเป็นยังไม่อ่าน
create function private.notify_students(
  p_kind text,
  p_post_id uuid,
  p_key text,
  p_student_ids uuid[],
  p_comment_id uuid default null,
  p_bump boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_actor record;
  v_now timestamptz := clock_timestamp();
begin
  v_actor := private.notify_actor();
  insert into public.notifications as n
         (recipient_student_id, kind, post_id, comment_id, dedupe_key, created_at, updated_at)
  select s.id, p_kind, p_post_id, p_comment_id, p_key || ':' || s.id, v_now, v_now
    from (select distinct x as id from unnest(p_student_ids) x where x is not null) s
   where s.id is distinct from v_actor.student_id
  on conflict (dedupe_key) do update
     set updated_at = excluded.updated_at, read_at = null
   where p_bump;
end
$$;

-- แจ้งครูเจ้าของห้องของโพสต์ (รวมเป็นแถวเดียวต่อ p_key แล้วเลื่อนเวลา/กลับเป็นยังไม่อ่านเสมอ)
create function private.notify_teacher(
  p_kind text,
  p_post_id uuid,
  p_key text,
  p_comment_id uuid default null,
  p_subject_student_id uuid default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_actor record;
  v_teacher_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  v_actor := private.notify_actor();
  select c.teacher_id into v_teacher_id
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_post_id;
  if v_teacher_id is null or v_teacher_id is not distinct from v_actor.teacher_id then
    return;
  end if;
  insert into public.notifications as n
         (recipient_teacher_id, kind, post_id, comment_id, subject_student_id, dedupe_key, created_at, updated_at)
  values (v_teacher_id, p_kind, p_post_id, p_comment_id, p_subject_student_id,
          p_key || ':' || v_teacher_id, v_now, v_now)
  on conflict (dedupe_key) do update
     set updated_at = excluded.updated_at, read_at = null, comment_id = excluded.comment_id;
end
$$;

-- สมาชิกห้องของโพสต์ (p_unsent_only = เฉพาะคนที่ยังไม่ส่งงานนี้)
create function private.post_members(p_post_id uuid, p_unsent_only boolean default false)
returns uuid[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(m.student_id), '{}')
    from public.posts p
    join public.memberships m on m.classroom_id = p.classroom_id
   where p.id = p_post_id
     and (not p_unsent_only
          or not exists (select 1 from public.submissions s
                          where s.assignment_id = p_post_id and s.student_id = m.student_id))
$$;

-- ---------------------------------------------------------------------------
-- 2. trigger ตามเหตุการณ์ — ทุกตัวกลืนข้อผิดพลาดของตัวเอง (ส่วน 11: แจ้งเตือนล้มไม่ทำให้คำสั่งล้ม)
-- ---------------------------------------------------------------------------

-- ครูโพสต์งาน/ประกาศใหม่ (ไม่มีงานร่าง: เพิ่มแถว = เผยแพร่) · แก้โจทย์ไม่แจ้ง (N1) จึงไม่มี trigger ตอนแก้
create function private.posts_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform private.notify_students('post_published', new.id, 'post_published:' || new.id,
                                    private.post_members(new.id));
  exception when others then
    raise warning 'notification_failed post_published: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger posts_notify after insert on public.posts
  for each row execute function private.posts_notify();

-- ความคิดเห็น: นักเรียนเจ้าของงานเขียน → ครู (รวมต่องานต่อนักเรียน) · ครู/ผู้ดูแลเขียน (รวมเหตุผลปรับหักคะแนน) → นักเรียน
create function private.comments_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if exists (select 1 from public.students s where s.id = new.student_id and s.account_id = new.author_account_id) then
      perform private.notify_teacher('student_comment', new.assignment_id,
                                     'student_comment:' || new.assignment_id || ':' || new.student_id,
                                     new.id, new.student_id);
    else
      perform private.notify_students('teacher_comment', new.assignment_id, 'teacher_comment:' || new.id,
                                      array[new.student_id], new.id);
    end if;
  exception when others then
    raise warning 'notification_failed comment: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger comments_notify after insert on public.comments
  for each row execute function private.comments_notify();

-- ครูเปิดสิทธิ์ส่งแก้ (หนึ่งแจ้งเตือนต่อสิทธิ์ที่เปิด)
create function private.revision_permissions_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub public.submissions;
begin
  begin
    select s.* into v_sub from public.submissions s where s.id = new.submission_id;
    perform private.notify_students('revision_opened', v_sub.assignment_id, 'revision_opened:' || new.id,
                                    array[v_sub.student_id]);
  exception when others then
    raise warning 'notification_failed revision_opened: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger revision_permissions_notify after insert on public.revision_permissions
  for each row execute function private.revision_permissions_notify();

-- งานรอตรวจ: ส่งครั้งแรกหรือส่งแก้ → แถวเดียวต่องานของครู (ตัวเลขอ่านจากสถานะปัจจุบันใน my_notifications)
create function private.submissions_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.last_submitted_at is not distinct from old.last_submitted_at then
    return null;
  end if;
  begin
    perform private.notify_teacher('pending_review', new.assignment_id, 'pending_review:' || new.assignment_id);
  exception when others then
    raise warning 'notification_failed pending_review: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger submissions_notify after insert or update of last_submitted_at on public.submissions
  for each row execute function private.submissions_notify();

-- เปลี่ยนกำหนดส่ง/วันปิดรับ/เปิดรับอีกครั้ง → ทุกคนในห้อง (N3: ทัน/สายของงานที่ส่งแล้วเปลี่ยนได้)
-- ปิดรับทันที (หรือปิดรับหลังเฉลย) → เฉพาะคนที่ยังไม่ส่ง
create function private.assignments_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if (old.closed_at is null and new.closed_at is not null)
       or (old.after_solution_closed_at is null and new.after_solution_closed_at is not null) then
      perform private.notify_students('intake_closed', new.post_id, 'intake_closed:' || new.post_id,
                                      private.post_members(new.post_id, true), null, true);
    end if;
    if new.due_at is distinct from old.due_at or new.close_at is distinct from old.close_at
       or (old.closed_at is not null and new.closed_at is null) then
      perform private.notify_students('due_changed', new.post_id, 'due_changed:' || new.post_id,
                                      private.post_members(new.post_id), null, true);
    end if;
  exception when others then
    raise warning 'notification_failed assignment: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger assignments_notify after update of due_at, close_at, closed_at, after_solution_closed_at
  on public.assignments
  for each row execute function private.assignments_notify();

-- เผยแพร่เฉลยครั้งแรก (แก้หลังเผยแพร่ไม่แจ้ง)
create function private.solutions_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.published_at is null or (tg_op = 'UPDATE' and old.published_at is not null) then
    return null;
  end if;
  begin
    perform private.notify_students('solution_published', new.assignment_id,
                                    'solution_published:' || new.assignment_id,
                                    private.post_members(new.assignment_id));
  exception when others then
    raise warning 'notification_failed solution_published: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$$;
create trigger solutions_notify after insert or update of published_at on public.solutions
  for each row execute function private.solutions_notify();
