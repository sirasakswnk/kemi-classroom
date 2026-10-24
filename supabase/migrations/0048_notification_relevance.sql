-- 0048_notification_relevance: กระดิ่งแสดงตามสถานะปัจจุบันของเป้าหมาย (P6-03a) — TECHNICAL_DESIGN 11, UX 12
-- รายการที่หมดความเกี่ยวข้องแล้วยังอยู่ในรายการ (จาง ไม่ดึงความสนใจ) แต่ไม่นับเป็น “ยังไม่อ่าน” บนกระดิ่ง:
--   due_reminder    = ส่งแล้ว หรือไม่ได้รับงานตามปกติแล้ว (ปิดรับ/เผยแพร่เฉลย)
--   teacher_comment / student_comment = ความคิดเห็นถูกยกเลิก (แสดง “ข้อความนี้ถูกยกเลิก”)
--   pending_review  = ตรวจครบแล้ว
-- งานที่ถูกลบหายจากกระดิ่งอยู่แล้ว (on delete cascade, N4) · read_at ที่เก็บไว้ไม่เปลี่ยน

-- ---------------------------------------------------------------------------
-- 1. ความเกี่ยวข้องตอนนี้ (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
create function private.notification_relevant(p_kind text, p_post_id uuid, p_comment_id uuid,
                                              p_student_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case p_kind
           when 'due_reminder' then
             not exists (select 1 from public.submissions s
                          where s.assignment_id = p_post_id and s.student_id = p_student_id)
             and coalesce(private.assignment_intake(p_post_id, clock_timestamp()) = 'open', false)
           when 'teacher_comment' then
             not exists (select 1 from public.comments c
                          where c.id = p_comment_id and c.retracted_at is not null)
           when 'student_comment' then
             not exists (select 1 from public.comments c
                          where c.id = p_comment_id and c.retracted_at is not null)
           when 'pending_review' then
             exists (select 1 from public.submissions s
                      where s.assignment_id = p_post_id and not private.submission_latest_graded(s.id))
           else true
         end
$$;

-- ---------------------------------------------------------------------------
-- 2. GET /notifications (แทน 0043) — relevant มาจากข้อ 1, เพิ่ม submitted (due_reminder), unread_count นับเฉพาะที่เกี่ยวข้อง
-- ---------------------------------------------------------------------------
-- ผล: { unread_count, items: [{ id, kind, at, read, relevant, submitted,
--        post_id, post_kind, title, classroom_id, classroom_name, due_at,
--        comment_id, comment_retracted, student_id, student_name, pending_count, level }] }
--   submitted: due_reminder เท่านั้น (ส่งแล้ว → หน้าเว็บบอก “ส่งแล้ว”, ไม่ใช่ → ปิดรับแล้ว) อื่น ๆ null
create or replace function public.my_notifications(p_before timestamptz default null,
                                                   p_limit integer default 30)
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
    'unread_count', public.unread_notification_count(),
    'items', coalesce((
      select jsonb_agg(x.item order by x.at desc, x.id desc)
        from (
          select v.id, v.updated_at as at,
                 jsonb_build_object(
                   'id', v.id,
                   'kind', v.kind,
                   'at', v.updated_at,
                   'read', v.read_at is not null,
                   'relevant', private.notification_relevant(v.kind, v.post_id, v.comment_id,
                                                             v.recipient_student_id),
                   'submitted', case when v.kind = 'due_reminder' then exists (
                                  select 1 from public.submissions s
                                   where s.assignment_id = v.post_id
                                     and s.student_id = v.recipient_student_id) end,
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

-- ตัวเลขบนกระดิ่ง (แทน 0043): ยังไม่อ่าน และยังเกี่ยวข้อง — mark_notifications_read คืนค่านี้ด้วย
create or replace function public.unread_notification_count()
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
           where v.read_at is null
             and private.notification_relevant(v.kind, v.post_id, v.comment_id,
                                               v.recipient_student_id));
end
$$;
