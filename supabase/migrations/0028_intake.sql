-- 0028_intake: เปลี่ยนกำหนดส่งสองทิศ (M1) และปิดรับ (M2) — migration กลุ่ม grading ส่วนที่สาม (P4-03a)
-- TECHNICAL_DESIGN ส่วน 5 (N3, I2, ตารางรับการส่ง + ลำดับตรวจ), 10 (POST /assignments/:id/due, /close), 11 (L5/J7);
-- SYSTEM_SPEC N3, I2; UX_DESIGN ส่วน 9 (M1, M2)
-- หลัก:
--   - assignments.closed_at = ครูกด "ปิดรับทันที" (ปิดได้แม้ยังไม่ถึงกำหนดส่ง — ครูตัดสินเอง); close_at เดิม = ตั้งเวลาปิดรับ
--     assignments.after_solution_closed_at = ครูปิดช่วงรับหลังเฉลย (ส่วน 5: "ครูปิดช่วงนี้ได้")
--     ทั้งสองตั้งแล้วไม่ปลด (ไม่มีคำสั่งเปิดรับอีกครั้งในแบบ v2) — trigger กัน
--   - private.assignment_intake (จุดเดียวของ "ปิดรับ" ที่ submission_outcome/สถานะทุกหน้าใช้) รวมปิดรับทันทีและการปิด
--     ช่วงรับหลังเฉลย; submission_rule และลำดับตรวจ (ภาคเรียน → สมาชิก → ปิดรับ/เฉลย → แถวเวลา) ไม่เปลี่ยน
--   - เปลี่ยนกำหนดส่ง: preview_due_change (อ่านอย่างเดียว) คืนรายชื่องานที่ยังไม่ตรวจ (รุ่นล่าสุดยังไม่มีผลตรวจ) ซึ่งจะ
--     เปลี่ยน สาย→ทัน และ ทัน→สาย; change_due รับรายชื่อ (submission id) ที่ครูเห็นตอน preview คำนวณซ้ำหลังล็อกงาน
--     FOR UPDATE (การส่ง/การตรวจถือล็อก share/no key update ของงานอยู่ จึงรอกัน) ไม่ตรง → preview_changed;
--     ผลตรวจที่บันทึกแล้วคงเดิม (I2 — grades เก็บ timing_* ของตัวเอง); ส่งแรกหลังเฉลยสายเสมอจึงไม่อยู่ในรายชื่อ
--   - ระยะ 6 (แจ้งเตือน "เปลี่ยนกำหนดส่ง/ปิดรับ/เผยแพร่เฉลย" และจัดงานเตือน 24 ชม. ใหม่ตาม L5/J7) เติมที่
--     private.assignment_event จุดเดียว — ตอนนี้ไม่ทำอะไร; เรียกภายใน transaction เดียวกับการเปลี่ยน
--   - ส่วนโทเคนไม่เกี่ยว (ระยะ 5)
--
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: preview_changed (รายชื่อที่ได้รับผลเปลี่ยนไปหลังเปิดหน้าต่าง — ให้ดูผลใหม่ก่อนยืนยัน)
-- รหัสเดิมที่ใช้: due_at_invalid, close_at_invalid, close_before_due, stale_revision, forbidden, admin_mode_required
-- รหัสภายใน: invalid_request (กำหนดใหม่เท่าเดิม / รายชื่อไม่ส่งมา), request_key_required, request_key_conflict, immutable_field

-- ---------------------------------------------------------------------------
-- 1. คอลัมน์และตัวกัน
-- ---------------------------------------------------------------------------
alter table public.assignments
  add column closed_at timestamptz,
  add column after_solution_closed_at timestamptz;

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

  -- ล็อกแล้วปลดหรือเลื่อนเวลาล็อกไม่ได้ ("ไม่ปลดล็อกเพราะเปลี่ยนผลตรวจ" — I4); ปิดรับแล้วเปิดใหม่ไม่ได้ (0028)
  if new.post_id <> old.post_id
     or (old.reward_locked_at is not null and new.reward_locked_at is distinct from old.reward_locked_at)
     or (old.full_score_locked_at is not null
         and new.full_score_locked_at is distinct from old.full_score_locked_at)
     or (old.closed_at is not null and new.closed_at is distinct from old.closed_at)
     or (old.after_solution_closed_at is not null
         and new.after_solution_closed_at is distinct from old.after_solution_closed_at) then
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
-- 2. สถานะรับงาน (แทน 0020) — ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
--   'after_solution' = เผยแพร่เฉลยแล้ว งานตั้งรับหลังเฉลย และครูยังไม่ปิดช่วงนี้
--   'closed'         = เผยแพร่เฉลยแล้วแต่ไม่รับ/ปิดช่วงหลังเฉลยแล้ว, ครูกดปิดรับทันที, หรือเลยวันปิดรับที่ตั้งไว้
--                      (close_at รับถึงวินาทีนั้นพอดี เหมือน due_at)
--   'open'           = อื่น ๆ
create or replace function private.assignment_intake(p_assignment_id uuid, p_now timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select case
           when exists (select 1 from public.solutions s
                         where s.assignment_id = a.post_id and s.published_at is not null)
             then case when a.accept_after_solution and a.after_solution_closed_at is null
                       then 'after_solution' else 'closed' end
           when a.closed_at is not null then 'closed'
           when a.close_at is not null and p_now > a.close_at then 'closed'
           else 'open'
         end
    from public.assignments a
   where a.post_id = p_assignment_id
$$;

-- ---------------------------------------------------------------------------
-- 3. จุดเชื่อมระยะ 6 (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- p_event: due_changed { previous_due_at, due_at } · closed {} · close_scheduled { close_at } · after_solution_closed {}
--          · solution_published {} (P4-03b)
-- ระยะ 6 เติม: แจ้งเตือนนักเรียนในห้อง (dedupe ตามส่วน 11) และจัด/ยกเลิกงานเตือน 24 ชม. (L5/J7) — ทำใน transaction
-- ของคำสั่งที่เรียก ห้ามเรียกบริการภายนอก
create function private.assignment_event(p_assignment_id uuid, p_event text, p_detail jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  null;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. เปลี่ยนกำหนดส่ง (POST /assignments/:id/due)
-- ---------------------------------------------------------------------------
-- ตรวจกำหนดใหม่: นาทีเต็ม (due_at_invalid), ต่างจากเดิม (invalid_request), ไม่หลังวันปิดรับที่ตั้งไว้ (close_before_due)
create function private.due_change_check(p_assignment public.assignments, p_due_at timestamptz)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_due_at is null or not isfinite(p_due_at) or mod(extract(epoch from p_due_at), 60) <> 0 then
    raise exception using errcode = 'P0001', message = 'due_at_invalid';
  end if;
  if p_due_at = p_assignment.due_at then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if p_assignment.close_at is not null and p_assignment.close_at < p_due_at then
    raise exception using errcode = 'P0001', message = 'close_before_due';
  end if;
end
$$;

-- ผลของการเปลี่ยนกำหนดต่องานที่ยังไม่ตรวจ:
-- { to_on_time: [{ submission_id, student_id, roll_number, display_name }], to_late: […], graded_count }
-- เรียงเลขที่ (รายชื่อภาคเรียนของห้อง) ไม่มีเลขที่ไว้ท้าย แล้วชื่อ
create function private.due_change_effects(p_assignment_id uuid, p_old_due timestamptz, p_new_due timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'to_on_time', coalesce(jsonb_agg(x.person order by x.roll_number nulls last, x.display_name, x.submission_id)
                             filter (where not x.graded and x.old_timing = 'late' and x.new_timing = 'on_time'), '[]'),
    'to_late', coalesce(jsonb_agg(x.person order by x.roll_number nulls last, x.display_name, x.submission_id)
                          filter (where not x.graded and x.old_timing = 'on_time' and x.new_timing = 'late'), '[]'),
    'graded_count', count(*) filter (where x.graded))
    from (
      select s.id as submission_id, st.display_name, e.roll_number,
             jsonb_build_object('submission_id', s.id, 'student_id', st.id, 'roll_number', e.roll_number,
                                'display_name', st.display_name) as person,
             private.submission_latest_graded(s.id) as graded,
             private.submission_timing(s.first_submitted_at, s.first_after_solution, p_old_due) as old_timing,
             private.submission_timing(s.first_submitted_at, s.first_after_solution, p_new_due) as new_timing
        from public.submissions s
        join public.students st on st.id = s.student_id
        join public.posts p on p.id = s.assignment_id
        join public.classrooms c on c.id = p.classroom_id
        left join public.roster_entries e on e.student_id = st.id and e.term_id = c.term_id
       where s.assignment_id = p_assignment_id
    ) x
$$;

-- M1 ก่อนยืนยัน (อ่านอย่างเดียว ไม่ต้องโหมดผู้ดูแล — สิทธิ์อ่านเดียวกับ teacher_submission_list)
-- ผล: { assignment_id, due_at, new_due_at, close_at, to_on_time, to_late, graded_count }
create function public.preview_due_change(p_assignment_id uuid, p_due_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_assignment public.assignments;
begin
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  if not found or private.post_access(p_assignment_id) is distinct from 'teacher' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.due_change_check(v_assignment, p_due_at);
  return jsonb_build_object(
    'assignment_id', p_assignment_id,
    'due_at', v_assignment.due_at,
    'new_due_at', p_due_at,
    'close_at', v_assignment.close_at)
    || private.due_change_effects(p_assignment_id, v_assignment.due_at, p_due_at);
end
$$;
revoke all on function public.preview_due_change(uuid, timestamptz) from public, anon;
grant execute on function public.preview_due_change(uuid, timestamptz) to authenticated;

-- M1 ยืนยัน: p_expected_to_on_time / p_expected_to_late = submission id ในรายชื่อที่ครูเห็นตอน preview (ลำดับไม่สำคัญ)
-- ผล: { assignment_id, due_at, previous_due_at, to_on_time, to_late, graded_count }
create function public.change_due(
  p_assignment_id uuid,
  p_due_at timestamptz,
  p_expected_to_on_time uuid[],
  p_expected_to_late uuid[],
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
  v_effects jsonb;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null or p_expected_to_on_time is null or p_expected_to_late is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'change_due:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'due_at', p_due_at,
    'to_on_time', (select coalesce(jsonb_agg(x order by x), '[]') from unnest(p_expected_to_on_time) x),
    'to_late', (select coalesce(jsonb_agg(x order by x), '[]') from unnest(p_expected_to_late) x))::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  perform private.require_post_teacher(p_assignment_id, p_admin_mode);
  -- exclusive: รอการส่ง/การตรวจที่ถือล็อกงานอยู่ให้จบ แล้วคำนวณผลจากข้อมูลที่นิ่งแล้ว
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.due_change_check(v_assignment, p_due_at);

  v_effects := private.due_change_effects(p_assignment_id, v_assignment.due_at, p_due_at);
  if (select coalesce(array_agg(x order by x), '{}') from unnest(p_expected_to_on_time) x)
       is distinct from (select coalesce(array_agg((e ->> 'submission_id')::uuid order by (e ->> 'submission_id')::uuid), '{}')
                           from jsonb_array_elements(v_effects -> 'to_on_time') e)
     or (select coalesce(array_agg(x order by x), '{}') from unnest(p_expected_to_late) x)
       is distinct from (select coalesce(array_agg((e ->> 'submission_id')::uuid order by (e ->> 'submission_id')::uuid), '{}')
                           from jsonb_array_elements(v_effects -> 'to_late') e) then
    raise exception using errcode = 'P0001', message = 'preview_changed';
  end if;

  update public.assignments set due_at = p_due_at where post_id = p_assignment_id;
  perform private.assignment_event(p_assignment_id, 'due_changed',
                                   jsonb_build_object('previous_due_at', v_assignment.due_at, 'due_at', p_due_at));

  v_result := jsonb_build_object(
    'assignment_id', p_assignment_id,
    'due_at', p_due_at,
    'previous_due_at', v_assignment.due_at) || v_effects;
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.change_due(uuid, timestamptz, uuid[], uuid[], uuid, boolean) from public, anon;
grant execute on function public.change_due(uuid, timestamptz, uuid[], uuid[], uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. ปิดรับ (POST /assignments/:id/close)
-- ---------------------------------------------------------------------------
-- p_close_at null = ปิดทันที: ยังไม่เผยแพร่เฉลย → closed_at; อยู่ในช่วงรับหลังเฉลย → after_solution_closed_at;
--   ปิดอยู่แล้ว → คืนสถานะเดิม (กดซ้ำได้)
-- p_close_at มีค่า = ตั้งเวลาปิดรับ (แทนเวลาที่ตั้งไว้เดิมได้): ต้องอยู่ในอนาคต (close_at_invalid) และไม่ก่อนกำหนดส่ง
--   (close_before_due); งานที่ปิดแล้ว/เผยแพร่เฉลยแล้ว → stale_revision (หน้าจอเห็นสถานะเก่า)
-- ผล: { assignment_id, intake, close_at, closed_at, after_solution_closed_at }
create function public.close_assignment(
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
  v_intake text;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'close_assignment:' || md5(jsonb_build_object(
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
  v_now := clock_timestamp();
  v_intake := private.assignment_intake(p_assignment_id, v_now);

  if p_close_at is null then
    if v_intake = 'after_solution' then
      update public.assignments set after_solution_closed_at = v_now where post_id = p_assignment_id;
      perform private.assignment_event(p_assignment_id, 'after_solution_closed', '{}'::jsonb);
    elsif v_assignment.closed_at is null
          and not exists (select 1 from public.solutions s
                           where s.assignment_id = p_assignment_id and s.published_at is not null) then
      update public.assignments set closed_at = v_now where post_id = p_assignment_id;
      perform private.assignment_event(p_assignment_id, 'closed', '{}'::jsonb);
    end if;
  else
    if v_intake <> 'open' then
      raise exception using errcode = 'P0001', message = 'stale_revision';
    end if;
    if not isfinite(p_close_at) or p_close_at <= v_now then
      raise exception using errcode = 'P0001', message = 'close_at_invalid';
    end if;
    if p_close_at < v_assignment.due_at then
      raise exception using errcode = 'P0001', message = 'close_before_due';
    end if;
    update public.assignments set close_at = p_close_at where post_id = p_assignment_id;
    perform private.assignment_event(p_assignment_id, 'close_scheduled', jsonb_build_object('close_at', p_close_at));
  end if;

  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  v_result := jsonb_build_object(
    'assignment_id', p_assignment_id,
    'intake', private.assignment_intake(p_assignment_id, v_now),
    'close_at', v_assignment.close_at,
    'closed_at', v_assignment.closed_at,
    'after_solution_closed_at', v_assignment.after_solution_closed_at);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.close_assignment(uuid, timestamptz, uuid, boolean) from public, anon;
grant execute on function public.close_assignment(uuid, timestamptz, uuid, boolean) to authenticated;
