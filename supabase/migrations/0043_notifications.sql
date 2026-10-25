-- 0043_notifications: ตารางกระดิ่ง (C01 นักเรียน / T11 ครู) + RPC อ่านรายการและทำเครื่องหมายอ่านแล้ว (P6-01a)
-- TECHNICAL_DESIGN ส่วน 2 (notifications), 10 (GET /notifications, POST /notifications/:id/read), 11; UX 12
-- หลัก:
--   - ผู้รับเป็น “ตัวคน” (students.id / teachers.id) ไม่ใช่บัญชี — ผูกบัญชีใหม่ (rebind) หรือครูมีหลายบัญชีก็เห็นกระดิ่งเดียวกัน
--   - ไม่เก็บเนื้อความคิดเห็นหรือข้อความใด ๆ — อ้างรหัสเป้าหมาย แล้วอ่านสถานะปัจจุบันตอนแสดง (ส่วน 11)
--   - dedupe_key ไม่ซ้ำทั้งตาราง (มีผู้รับอยู่ในคีย์) — ตัวสร้างเหตุการณ์ (P6-01b, P6-02) ใช้ on conflict กันซ้ำ
--   - หน้าเว็บอ่าน/แก้ผ่าน RPC เท่านั้น: เปิด RLS ไม่มี policy และไม่ GRANT ตารางให้ใคร
--   - ชนิดแยกละเอียดกว่า 5/3 กลุ่มของ UX 12 เพื่อให้ถ้อยคำต่างกันได้ แต่ไม่มีชนิดนอกกลุ่ม:
--       นักเรียน  งาน/ประกาศใหม่ = post_published · ใกล้ส่ง = due_reminder
--                 ครูแสดงความคิดเห็น/เปิดแก้ = teacher_comment, revision_opened
--                 เปลี่ยนกำหนดหรือปิดรับ = due_changed, intake_closed · เผยแพร่เฉลย = solution_published
--       ครู       งานรอตรวจ (รวมต่องาน) = pending_review · ความคิดเห็นจากนักเรียน = student_comment
--                 พื้นที่เก็บไฟล์ = storage_threshold (P6-04b)
-- ผู้ดูแล (ไม่มี teacher_id) ยังไม่มีกระดิ่ง — เกณฑ์ 80% ของผู้ดูแลตัดสินใน P6-04b

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_student_id uuid references public.students (id),
  recipient_teacher_id uuid references public.teachers (id),
  kind text not null check (kind in (
    'post_published', 'due_reminder', 'teacher_comment', 'revision_opened',
    'due_changed', 'intake_closed', 'solution_published',
    'pending_review', 'student_comment', 'storage_threshold')),
  -- โพสต์/งานเป้าหมาย — ลบโพสต์แล้วแจ้งเตือนหายตาม (N4)
  post_id uuid references public.posts (id) on delete cascade,
  -- ความคิดเห็นเป้าหมาย (ยกเลิกแล้วแถวยังอยู่ แสดง “ข้อความนี้ถูกยกเลิก” จาก retracted_at)
  comment_id uuid references public.comments (id) on delete cascade,
  -- นักเรียนที่เหตุการณ์ของครูพูดถึง (student_comment: เปิดงานของคนนี้พร้อมช่องความคิดเห็น)
  subject_student_id uuid references public.students (id),
  -- storage_threshold: ระดับที่ถึง (ครั้งเดียวต่อระดับ)
  level integer check (level in (80, 90, 100)),
  dedupe_key text not null unique check (length(dedupe_key) between 1 and 200),
  created_at timestamptz not null default clock_timestamp(),
  -- เวลาเหตุการณ์ล่าสุด: เรียงกระดิ่งตามค่านี้; pending_review ที่มีงานส่งเพิ่มเลื่อนค่านี้และกลับเป็นยังไม่อ่าน
  updated_at timestamptz not null default clock_timestamp(),
  read_at timestamptz,
  check ((recipient_student_id is null) <> (recipient_teacher_id is null)),
  check (case
           when kind in ('post_published', 'due_reminder', 'revision_opened', 'due_changed',
                         'intake_closed', 'solution_published')
             then recipient_student_id is not null and post_id is not null and comment_id is null
                  and subject_student_id is null and level is null
           when kind = 'teacher_comment'
             then recipient_student_id is not null and post_id is not null and comment_id is not null
                  and subject_student_id is null and level is null
           when kind = 'pending_review'
             then recipient_teacher_id is not null and post_id is not null and comment_id is null
                  and subject_student_id is null and level is null
           when kind = 'student_comment'
             then recipient_teacher_id is not null and post_id is not null and comment_id is not null
                  and subject_student_id is not null and level is null
           else recipient_teacher_id is not null and post_id is null and comment_id is null
                and subject_student_id is null and level is not null
         end)
);
create index notifications_student_idx on public.notifications (recipient_student_id, updated_at desc)
  where recipient_student_id is not null;
create index notifications_teacher_idx on public.notifications (recipient_teacher_id, updated_at desc)
  where recipient_teacher_id is not null;
create index notifications_post_id_idx on public.notifications (post_id);
create index notifications_comment_id_idx on public.notifications (comment_id);
create index notifications_subject_student_id_idx on public.notifications (subject_student_id);

alter table public.notifications enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ฟังก์ชันช่วย (ไม่ GRANT ใคร — ใช้ภายใน RPC ที่เป็น SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- เจ้าของกระดิ่งของผู้เรียก: ครู → teacher_id · นักเรียนที่ผูกชื่อแล้ว → student_id · อื่น ๆ (ผู้ดูแล, ยังไม่ผูกชื่อ) → ว่างทั้งคู่
create function private.bell_owner(out student_id uuid, out teacher_id uuid)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account public.accounts;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  if v_account.role = 'teacher' then
    teacher_id := v_account.teacher_id;
  elsif v_account.role = 'student' then
    select s.id into student_id from public.students s where s.account_id = v_account.id;
  end if;
end
$$;

-- แจ้งเตือนที่เจ้าของเห็นได้ขณะนี้: นักเรียนเห็นเฉพาะของห้องที่ยังเป็นสมาชิก (ถูกเอาออกแล้วหายทันที)
-- ครูเห็นเฉพาะของห้องที่ตนสอน; storage_threshold ไม่มีห้อง
create function private.visible_notifications(p_student_id uuid, p_teacher_id uuid)
returns setof public.notifications
language sql
stable
set search_path = ''
as $$
  select n.*
    from public.notifications n
    left join public.posts p on p.id = n.post_id
   where (p_student_id is not null and n.recipient_student_id = p_student_id
          and exists (select 1 from public.memberships m
                       where m.classroom_id = p.classroom_id and m.student_id = p_student_id))
      or (p_teacher_id is not null and n.recipient_teacher_id = p_teacher_id
          and (n.post_id is null
               or exists (select 1 from public.classrooms c
                           where c.id = p.classroom_id and c.teacher_id = p_teacher_id)))
$$;

-- ---------------------------------------------------------------------------
-- 3. GET /notifications — กระดิ่งของเจ้าของเอง เรียงจากเหตุการณ์ล่าสุด
-- ---------------------------------------------------------------------------
-- p_before: ค่า at ของรายการสุดท้ายในหน้าก่อน (null = หน้าแรก) · p_limit 1–100 (ค่าเริ่มต้น 30)
-- ผล: { unread_count, items: [{ id, kind, at, read, relevant,
--        post_id, post_kind, title, classroom_id, classroom_name, due_at,
--        comment_id, comment_retracted, student_id, student_name, pending_count, level }] }
--   relevant (สถานะปัจจุบัน ไม่ใช่ค่าที่เก็บ): due_reminder = ยังไม่ส่ง · pending_review = ยังมีงานรอตรวจ · อื่น ๆ = true
--   ไม่มีเนื้อความคิดเห็นในผลเลย (ส่วน 11)
create function public.my_notifications(p_before timestamptz default null, p_limit integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner record;
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_owner := private.bell_owner();
  return jsonb_build_object(
    'unread_count', (select count(*)::integer
                       from private.visible_notifications(v_owner.student_id, v_owner.teacher_id) v
                      where v.read_at is null),
    'items', coalesce((
      select jsonb_agg(x.item order by x.at desc, x.id desc)
        from (
          select v.id, v.updated_at as at,
                 jsonb_build_object(
                   'id', v.id,
                   'kind', v.kind,
                   'at', v.updated_at,
                   'read', v.read_at is not null,
                   'relevant', case v.kind
                                 when 'due_reminder' then not exists (
                                   select 1 from public.submissions s
                                    where s.assignment_id = v.post_id and s.student_id = v.recipient_student_id)
                                 when 'pending_review' then pc.n > 0
                                 else true
                               end,
                   'post_id', v.post_id,
                   'post_kind', p.kind,
                   'title', p.title,
                   'classroom_id', c.id,
                   'classroom_name', c.name,
                   'due_at', a.due_at,
                   'comment_id', v.comment_id,
                   'comment_retracted', case when v.comment_id is null then null
                                             else cm.retracted_at is not null end,
                   'student_id', v.subject_student_id,
                   'student_name', st.display_name,
                   'pending_count', pc.n,
                   'level', v.level
                 ) as item
            from private.visible_notifications(v_owner.student_id, v_owner.teacher_id) v
            left join public.posts p on p.id = v.post_id
            left join public.classrooms c on c.id = p.classroom_id
            left join public.assignments a on a.post_id = v.post_id
            left join public.comments cm on cm.id = v.comment_id
            left join public.students st on st.id = v.subject_student_id
            left join lateral (
              select count(*)::integer as n
                from public.submissions s
               where v.kind = 'pending_review' and s.assignment_id = v.post_id
                 and not private.submission_latest_graded(s.id)
            ) pc on v.kind = 'pending_review'
           where p_before is null or v.updated_at < p_before
           order by v.updated_at desc, v.id desc
           limit p_limit
        ) x
    ), '[]'::jsonb)
  );
end
$$;
revoke all on function public.my_notifications(timestamptz, integer) from public, anon;
grant execute on function public.my_notifications(timestamptz, integer) to authenticated;

-- ตัวเลขบนกระดิ่งที่แถบบน (เรียกบ่อย จึงแยกจากรายการ)
create function public.unread_notification_count()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner record;
begin
  v_owner := private.bell_owner();
  return (select count(*)::integer
            from private.visible_notifications(v_owner.student_id, v_owner.teacher_id) v
           where v.read_at is null);
end
$$;
revoke all on function public.unread_notification_count() from public, anon;
grant execute on function public.unread_notification_count() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. POST /notifications/:id/read — อ่านแล้วรายการที่เลือก หรือ “อ่านทั้งหมด” (p_ids = null)
-- ---------------------------------------------------------------------------
-- แตะเฉพาะรายการที่เจ้าของเห็นได้ขณะนี้; รหัสของคนอื่นหรือที่ไม่มีอยู่ถูกข้ามเงียบ ๆ (ไม่บอกว่ามีอยู่จริงไหม)
-- ผล: จำนวนที่ยังไม่อ่านหลังทำ
create function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner record;
begin
  if p_ids is not null and cardinality(p_ids) > 200 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_owner := private.bell_owner();
  update public.notifications n
     set read_at = clock_timestamp()
   where n.read_at is null
     and (p_ids is null or n.id = any (p_ids))
     and n.id in (select v.id from private.visible_notifications(v_owner.student_id, v_owner.teacher_id) v);
  return public.unread_notification_count();
end
$$;
revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
