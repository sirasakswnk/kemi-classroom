-- 0035_grade_reward: ให้รางวัลใน transaction เดียวกับผลตรวจ — migration กลุ่ม rewards ส่วนที่สอง (P5-02)
-- TECHNICAL_DESIGN ส่วน 6 ข้อ 6–8, ส่วน 7 (กระเป๋า/ลำดับล็อก/I5/K5); SYSTEM_SPEC I3, I5, K4, K5, N3, N4;
-- TECHNICAL_BUILD_PLAN 4.1 ข้อ 5, ส่วน 10 ระยะ 5 (ข้อตรวจรับส่วนโทเคนที่ย้ายมาจากระยะ 4)
-- grade_submission เหมือน 0026 ทุกอย่าง ยกเว้นขั้นให้รางวัลที่จุดต่อ:
--   - ให้เมื่อครบทุกข้อ: เวลาที่ใช้ตรวจนับเป็นส่งทัน (ส่งแรกหลังเฉลย = สายเสมอ), ครูยืนยันผ่าน,
--     ห้องของงานอยู่ในภาคเรียนของกระเป๋าปัจจุบัน (term_control.term_id — I5; จบภาคเรียนแล้วยังให้ได้ K5),
--     reward_granted = false และ reward_tokens ของงาน > 0 (งาน 0 โทเคน: ไม่ตั้ง reward_granted ไม่มีเอฟเฟกต์)
--   - จำนวน = assignments.reward_tokens (ล็อกตั้งแต่ส่งครั้งแรก — reward_locked_at 0020)
--   - ล็อกตามลำดับ term_control → assignments → submissions → wallets: เพิ่มยอดแถว (นักเรียน, เทอมปัจจุบัน)
--     ด้วย upsert (ไม่มีแถว = ยอด 0) + version + 1 แล้วตั้ง reward_granted = true ใน transaction เดียวกัน
--   - ให้ครั้งเดียวต่องานส่ง: reward_granted ไม่ย้อน (guard 0020) — ผ่าน→ไม่ผ่านไม่ถอน (I3) ผ่านซ้ำไม่ได้ซ้ำ;
--     ตรวจพร้อมกันรอล็อก submissions จึงเห็นค่าล่าสุดเสมอ
--   - เปลี่ยนกำหนดส่ง / แก้เฉลย / ลบงาน ไม่แตะ wallets (โทเคนที่ได้แล้วคงอยู่ — N3, K4, N4)
--   - ไม่สร้างแจ้งเตือน (ส่วน 6 ข้อ 8); เอฟเฟกต์ค้างที่ reward_granted and not reward_effect_seen (0034)
-- พารามิเตอร์และรหัสข้อผิดพลาดเหมือน 0026 · ผลเพิ่ม: reward_tokens_granted (จำนวนที่ให้ในคำขอนี้ 0 = ไม่ได้ให้), wallet_balance (ยอดหลังให้ หรือ null ถ้าไม่ได้ให้)

create or replace function public.grade_submission(
  p_submission_id uuid,
  p_raw integer,
  p_pass boolean,
  p_override_pct integer,
  p_reason text,
  p_seen_revision integer,
  p_expected_version integer,
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
  v_reason text;
  v_operation text;
  v_prior jsonb;
  v_teacher_id uuid;
  v_assignment public.assignments;
  v_sub public.submissions;
  v_old public.grades;
  v_grade public.grades;
  v_timing text;
  v_override integer;
  v_reason_needed boolean;
  v_comment_id uuid;
  v_pct integer;
  v_net integer;
  v_now timestamptz;
  v_locked_now boolean := false;
  v_wallet_term_id uuid;
  v_classroom_term_id uuid;
  v_granted integer := 0;
  v_balance integer;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_submission_id is null or p_pass is null or p_seen_revision is null or p_expected_version is null
     or p_expected_version < 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_reason := private.trim_text(p_reason);
  if length(v_reason) > 2000 then
    raise exception using errcode = 'P0001', message = 'comment_too_long';
  end if;

  v_operation := 'grade_submission:' || md5(jsonb_build_object(
    'submission_id', p_submission_id, 'raw', p_raw, 'pass', p_pass, 'override_pct', p_override_pct,
    'reason', v_reason, 'seen_revision', p_seen_revision, 'expected_version', p_expected_version)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ครูเจ้าของห้อง หรือผู้ดูแลในโหมดผู้ดูแล (require_teacher ตรวจโหมดแล้ว) — ไม่ล็อกแถวห้อง
  -- เพื่อคงลำดับล็อก term_control → assignments → submissions (BUILD_PLAN 4.1 ข้อ 5); งานส่งที่ไม่มี = forbidden
  select c.teacher_id, c.term_id into v_teacher_id, v_classroom_term_id
    from public.submissions s
    join public.posts p on p.id = s.assignment_id
    join public.classrooms c on c.id = p.classroom_id
   where s.id = p_submission_id;
  if not found or (v_account.role = 'teacher' and v_teacher_id is distinct from v_account.teacher_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  -- ลำดับล็อก (ส่วน 6 ข้อ 2): term_control → assignments → submissions → wallets
  -- term_control แบบ share: การเริ่ม/จบภาคเรียน (0039) ล็อก exclusive จึงไม่ชนกลางการให้รางวัล
  -- และเทอมกระเป๋าที่อ่านตรงนี้คงเดิมจนจบ transaction
  select c.term_id into v_wallet_term_id from public.term_control c where c.singleton for share;
  -- งาน: exclusive เฉพาะตอนที่อาจต้องตั้ง full_score_locked_at (L4) ไม่อย่างนั้นแค่ share
  -- (ล็อกแล้วไม่ปลด — trigger 0010 — จึงไม่ต้องอัปเกรดภายหลัง); การเปลี่ยนกำหนดส่ง (P4-03) ล็อก FOR UPDATE จึงรอกัน
  select a.* into v_assignment
    from public.assignments a join public.submissions s on s.assignment_id = a.post_id
   where s.id = p_submission_id;
  if p_raw is not null and v_assignment.full_score_locked_at is null then
    select a.* into v_assignment from public.assignments a where a.post_id = v_assignment.post_id for no key update;
  else
    select a.* into v_assignment from public.assignments a where a.post_id = v_assignment.post_id for share;
  end if;
  -- งานส่ง: ล็อกเดียวกับ submit_assignment จึงไม่ตรวจทับไฟล์ที่นักเรียนกำลังส่งใหม่ (ส่วน 6 ข้อ 1)
  select s.* into v_sub from public.submissions s where s.id = p_submission_id for update;
  if v_sub.content_revision <> p_seen_revision then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  select g.* into v_old from public.grades g where g.submission_id = p_submission_id for update;
  if coalesce(v_old.version, 0) <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;

  -- K1: คะแนนดิบเป็นจำนวนเต็ม 0–คะแนนเต็มของงาน
  if p_raw is not null and (p_raw < 0 or p_raw > v_assignment.full_score) then
    raise exception using errcode = 'P0001', message = 'score_invalid';
  end if;
  if p_override_pct is not null and (p_override_pct < 0 or p_override_pct > 100) then
    raise exception using errcode = 'P0001', message = 'late_penalty_invalid';
  end if;

  -- ทัน/สายจากเวลาส่งครั้งแรกเทียบกำหนดปัจจุบัน (I1/I2; ส่งแรกหลังเฉลยสายเสมอ)
  v_timing := private.submission_timing(v_sub.first_submitted_at, v_sub.first_after_solution, v_assignment.due_at);
  -- L2 (ฉบับ 17 ต.ค.): ตั้ง/เปลี่ยนค่าได้เฉพาะงานสาย; ค่าเดิมคงอยู่เมื่องานกลายเป็นทัน (ส่งกลับมาได้)
  -- การเปลี่ยนใด ๆ รวมการล้างต้องมีเหตุผลเสมอ
  v_override := p_override_pct;
  v_reason_needed := v_override is distinct from v_old.penalty_override_pct;
  if v_timing = 'on_time' and v_reason_needed and v_override is not null then
    raise exception using errcode = 'P0001', message = 'penalty_not_late';
  end if;
  if v_reason_needed and v_reason is null then
    raise exception using errcode = 'P0001', message = 'reason_required';
  end if;
  if not v_reason_needed and v_reason is not null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_now := clock_timestamp();
  -- J3: เหตุผลเป็นความคิดเห็นส่วนตัวของครูที่นักเรียนเห็น บันทึกพร้อมผลตรวจ
  if v_reason_needed then
    insert into public.comments (assignment_id, student_id, author_account_id, body, created_at)
    values (v_sub.assignment_id, v_sub.student_id, v_account.id, v_reason, v_now)
    returning id into v_comment_id;
  else
    v_comment_id := v_old.override_comment_id;
  end if;

  -- งานทันไม่หัก แม้มี override เก็บไว้
  v_pct := case when v_timing = 'late' then coalesce(v_override, v_assignment.late_penalty_pct) else 0 end;
  v_net := case when p_raw is not null then private.grade_net_score(p_raw, v_pct) end;

  insert into public.grades as g (
    submission_id, raw_score, passed, penalty_override_pct, override_comment_id,
    timing, timing_due_at, timing_basis_at, timing_i1,
    applied_penalty_pct, deduction, net_score, graded_revision, graded_at, graded_by_account_id, version)
  values (
    v_sub.id, p_raw, p_pass, v_override, v_comment_id,
    v_timing, v_assignment.due_at, v_sub.first_submitted_at,
    v_timing = 'on_time' and v_sub.last_submitted_at > v_assignment.due_at,
    v_pct, p_raw - v_net, v_net, v_sub.content_revision, v_now, v_account.id, 1)
  on conflict (submission_id) do update
    set raw_score = excluded.raw_score,
        passed = excluded.passed,
        penalty_override_pct = excluded.penalty_override_pct,
        override_comment_id = excluded.override_comment_id,
        timing = excluded.timing,
        timing_due_at = excluded.timing_due_at,
        timing_basis_at = excluded.timing_basis_at,
        timing_i1 = excluded.timing_i1,
        applied_penalty_pct = excluded.applied_penalty_pct,
        deduction = excluded.deduction,
        net_score = excluded.net_score,
        graded_revision = excluded.graded_revision,
        graded_at = excluded.graded_at,
        graded_by_account_id = excluded.graded_by_account_id,
        version = g.version + 1
  returning g.* into v_grade;

  -- L4/K2: คะแนนดิบครั้งแรกของงานล็อกคะแนนเต็มและ % หักพร้อมกัน
  if p_raw is not null and v_assignment.full_score_locked_at is null then
    update public.assignments set full_score_locked_at = v_now where post_id = v_assignment.post_id;
    v_locked_now := true;
  end if;

  -- ขั้นให้รางวัล (ส่วน 6 ข้อ 6–7): ทัน + ผ่าน + เทอมกระเป๋าปัจจุบัน (I5) + ยังไม่เคยให้ + งานมีโทเคน
  if v_timing = 'on_time' and p_pass and not v_sub.reward_granted and v_assignment.reward_tokens > 0
     and v_classroom_term_id = v_wallet_term_id then
    insert into public.wallets as w (student_id, term_id, balance)
    values (v_sub.student_id, v_wallet_term_id, v_assignment.reward_tokens)
    on conflict (student_id, term_id) do update
      set balance = w.balance + excluded.balance, version = w.version + 1, updated_at = v_now
    returning w.balance into v_balance;
    update public.submissions set reward_granted = true where id = v_sub.id;
    v_sub.reward_granted := true;
    v_granted := v_assignment.reward_tokens;
  end if;

  v_result := jsonb_build_object(
    'submission_id', v_grade.submission_id,
    'raw_score', v_grade.raw_score,
    'passed', v_grade.passed,
    'penalty_override_pct', v_grade.penalty_override_pct,
    'override_comment_id', v_grade.override_comment_id,
    'timing', v_grade.timing,
    'timing_due_at', v_grade.timing_due_at,
    'timing_basis_at', v_grade.timing_basis_at,
    'timing_i1', v_grade.timing_i1,
    'applied_penalty_pct', v_grade.applied_penalty_pct,
    'deduction', v_grade.deduction,
    'net_score', v_grade.net_score,
    'graded_revision', v_grade.graded_revision,
    'graded_at', v_grade.graded_at,
    'version', v_grade.version,
    'full_score_locked', v_assignment.full_score_locked_at is not null or v_locked_now,
    'reward_granted', v_sub.reward_granted,
    'reward_tokens_granted', v_granted,
    'wallet_balance', v_balance);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.grade_submission(uuid, integer, boolean, integer, text, integer, integer, uuid, boolean)
  from public, anon;
grant execute on function public.grade_submission(uuid, integer, boolean, integer, text, integer, integer, uuid, boolean)
  to authenticated;
