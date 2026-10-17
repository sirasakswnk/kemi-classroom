-- 0030_reopen: เปิดรับอีกครั้ง / เปลี่ยนหรือยกเลิกเวลาปิดรับ (M2) — P4-03c (ผู้ใช้ยืนยัน 17 ต.ค. 2026)
-- TECHNICAL_DESIGN ส่วน 5, 10 (POST /assignments/:id/close); UX_DESIGN ส่วน 9 (M2)
-- หลัก:
--   - ก่อนเผยแพร่เฉลย ครูเปิดรับอีกครั้งได้: ล้าง closed_at (ปิดทันที) และตั้ง close_at ใหม่หรือไม่ตั้ง (null = รับสาย
--     จนกว่าครูปิด) — ใช้ทั้ง "เปิดรับอีกครั้งหลังปิด" และ "ยกเลิก/เปลี่ยนเวลาปิดที่ตั้งไว้" ด้วยคำสั่งเดียว
--   - หลังเผยแพร่เฉลยเปิดรับอีกไม่ได้ (ใช้ตัวเลือกรับงานหลังเฉลยแทน) → solution_published; ตัวกันระดับตาราง
--     (assignments_guard) ยอมล้าง closed_at เฉพาะตอนยังไม่เผยแพร่เฉลย; after_solution_closed_at ยังล้างไม่ได้
--   - หลังเปิดรับ นักเรียนส่งได้ตามตารางรับการส่งเดิม (แถว 2/3 ตามเวลาเทียบกำหนดส่ง)
--   - ระยะ 6: private.assignment_event(…, 'reopened', { close_at }) → แจ้ง "ครูเปลี่ยนวันปิดรับงาน"
--
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: solution_published (เปิดรับอีกครั้งหลังเผยแพร่เฉลย — ใช้การรับงานหลังเฉลยแทน)
-- รหัสเดิมที่ใช้: close_at_invalid, close_before_due, forbidden, admin_mode_required
-- รหัสภายใน: invalid_request, request_key_required, request_key_conflict, immutable_field

-- ---------------------------------------------------------------------------
-- 1. ตัวกัน: closed_at ล้างได้เฉพาะก่อนเผยแพร่เฉลย (แทน 0028)
-- ---------------------------------------------------------------------------
create or replace function private.assignments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.posts p where p.id = new.post_id and p.kind = 'homework') then
      raise exception using errcode = 'P0001', message = 'post_not_homework';
    end if;
    if new.closed_at is not null or new.after_solution_closed_at is not null then
      raise exception using errcode = 'P0001', message = 'immutable_field';
    end if;
    return new;
  end if;

  -- ล็อกแล้วปลดหรือเลื่อนเวลาล็อกไม่ได้ ("ไม่ปลดล็อกเพราะเปลี่ยนผลตรวจ" — I4); ปิดช่วงหลังเฉลยแล้วเปิดใหม่ไม่ได้
  if new.post_id <> old.post_id
     or (old.reward_locked_at is not null and new.reward_locked_at is distinct from old.reward_locked_at)
     or (old.full_score_locked_at is not null
         and new.full_score_locked_at is distinct from old.full_score_locked_at)
     or (old.after_solution_closed_at is not null
         and new.after_solution_closed_at is distinct from old.after_solution_closed_at) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  -- ปิดรับทันที: ล้างได้ (เปิดรับอีกครั้ง) เฉพาะก่อนเผยแพร่เฉลย; เปลี่ยนเวลาปิดที่ตั้งแล้วเป็นเวลาอื่นไม่ได้ (0030)
  if old.closed_at is not null and new.closed_at is distinct from old.closed_at
     and (new.closed_at is not null
          or exists (select 1 from public.solutions s
                      where s.assignment_id = old.post_id and s.published_at is not null)) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  -- I4: จำนวนรางวัลแก้ได้จนมีการส่งครั้งแรก
  if old.reward_locked_at is not null and new.reward_tokens <> old.reward_tokens then
    raise exception using errcode = 'P0001', message = 'reward_locked';
  end if;
  -- J2/L4/K2: คะแนนเต็มและ % หักล็อกพร้อมกันเมื่อบันทึกคะแนนแรก
  if old.full_score_locked_at is not null
     and (new.full_score <> old.full_score or new.late_penalty_pct <> old.late_penalty_pct) then
    raise exception using errcode = 'P0001', message = 'full_score_locked';
  end if;
  -- N2: "รับงานหลังเผยแพร่เฉลย" แก้ได้จนเผยแพร่เฉลย
  -- (คำสั่งเผยแพร่เฉลยต้องล็อกแถวงานนี้ FOR UPDATE ก่อน จึงไม่ชนกับการแก้งานพร้อมกัน)
  if new.accept_after_solution <> old.accept_after_solution
     and exists (select 1 from public.solutions s
                  where s.assignment_id = old.post_id and s.published_at is not null) then
    raise exception using errcode = 'P0001', message = 'after_solution_locked';
  end if;
  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. เปิดรับอีกครั้ง / เปลี่ยนหรือยกเลิกเวลาปิดรับ
-- ---------------------------------------------------------------------------
-- p_close_at: null = เปิดรับโดยไม่ตั้งเวลาปิด; มีค่า = เวลาปิดใหม่ (อนาคต และไม่ก่อนกำหนดส่ง)
-- งานที่เปิดรับอยู่แล้วและค่าเท่าเดิม → คืนสถานะเดิม (ไม่เรียก assignment_event)
-- ผล: { assignment_id, intake, close_at, closed_at, after_solution_closed_at, changed }
create function public.reopen_assignment(
  p_assignment_id uuid,
  p_close_at timestamptz,
  p_request_key uuid,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_operation text;
  v_prior jsonb;
  v_assignment public.assignments;
  v_now timestamptz;
  v_changed boolean;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'reopen_assignment:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'close_at', p_close_at)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  perform private.require_post_teacher(p_assignment_id, p_admin_mode);
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if exists (select 1 from public.solutions s where s.assignment_id = p_assignment_id and s.published_at is not null) then
    raise exception using errcode = 'P0001', message = 'solution_published';
  end if;
  v_now := clock_timestamp();
  if p_close_at is not null then
    if not isfinite(p_close_at) or p_close_at <= v_now then
      raise exception using errcode = 'P0001', message = 'close_at_invalid';
    end if;
    if p_close_at < v_assignment.due_at then
      raise exception using errcode = 'P0001', message = 'close_before_due';
    end if;
  end if;

  v_changed := v_assignment.closed_at is not null or v_assignment.close_at is distinct from p_close_at;
  if v_changed then
    update public.assignments set closed_at = null, close_at = p_close_at where post_id = p_assignment_id;
    perform private.assignment_event(p_assignment_id, 'reopened', jsonb_build_object('close_at', p_close_at));
  end if;

  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  v_result := jsonb_build_object(
    'assignment_id', p_assignment_id,
    'intake', private.assignment_intake(p_assignment_id, v_now),
    'close_at', v_assignment.close_at,
    'closed_at', v_assignment.closed_at,
    'after_solution_closed_at', v_assignment.after_solution_closed_at,
    'changed', v_changed);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.reopen_assignment(uuid, timestamptz, uuid, boolean) from public, anon;
grant execute on function public.reopen_assignment(uuid, timestamptz, uuid, boolean) to authenticated;
