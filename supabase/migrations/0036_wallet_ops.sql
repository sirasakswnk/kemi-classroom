-- 0036_wallet_ops: เอฟเฟกต์ได้รับโทเคน + ปรับยอดมือ + ข้อมูลรางวัลในสถานะงาน (P5-03)
-- TECHNICAL_DESIGN ส่วน 7 (ปรับมือ: รุ่นยอด ไม่ติดลบ ไม่มีประวัติ; เอฟเฟกต์ reward_effect_seen), ส่วน 10 wallet/adjust,
-- UX_DESIGN ส่วน 7 (สถานะรางวัล + เอฟเฟกต์รวมยอดหลายงาน), ส่วน 9 (ผลที่คาดก่อนบันทึกผ่าน), ส่วน 10 (ปรับโทเคนรายคน)
--   - reward_effects(): เอฟเฟกต์ที่ยังไม่ดูของนักเรียน รวมยอดครั้งเดียว — เฉพาะงานในห้องของเทอมกระเป๋าปัจจุบัน
--     (งานเทอมก่อนที่ยังไม่ดู ยอดถูกล้างไปแล้ว จึงไม่แสดง “+n” ที่ไม่มีอยู่จริง)
--   - mark_reward_effect_seen(ids): ตั้งดูแล้วเฉพาะรายการที่หน้าเว็บได้แสดงไป (ไม่ใช่ “ทั้งหมด”) เพื่อไม่กลืน
--     รางวัลที่เพิ่งได้ระหว่างแสดงเอฟเฟกต์; id ที่ไม่ใช่ของตน/ไม่ค้าง ข้ามเงียบ ๆ (เรียกซ้ำได้)
--   - wallet_adjust: ครู/ผู้ดูแลในโหมดผู้ดูแล เพิ่ม/ลดยอดเทอมกระเป๋าปัจจุบัน; รุ่นยอดที่เห็น (ไม่มีแถว = 0)
--     ไม่ตรง → stale_revision, ผลติดลบ → insufficient_balance (รหัสใหม่); ไม่มีเหตุผล ไม่เก็บประวัติ
--     ล็อก term_control (share) → wallets ตามลำดับเดียวกับ grade_submission; จบภาคเรียนแล้วยังปรับได้ (K5 ไม่ห้าม)
--   - submission_status / teacher_submission_list / roster_overview: เพิ่มข้อมูลรางวัลและยอด (ผลเดิมคงอยู่)

-- ---------------------------------------------------------------------------
-- 1. เอฟเฟกต์ได้รับโทเคน (นักเรียน)
-- ---------------------------------------------------------------------------
-- ผล: { tokens, works, submission_ids } — works = 0 ไม่มีเอฟเฟกต์ค้าง
create function public.reward_effects()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  perform private.require_student_account();
  v_student_id := private.current_student();
  select jsonb_build_object(
           'tokens', coalesce(sum(a.reward_tokens), 0)::integer,
           'works', count(*)::integer,
           'submission_ids', coalesce(jsonb_agg(s.id order by s.id), '[]'::jsonb))
    into v_result
    from public.submissions s
    join public.assignments a on a.post_id = s.assignment_id
    join public.posts p on p.id = s.assignment_id
    join public.classrooms c on c.id = p.classroom_id
    join public.term_control tc on tc.singleton and tc.term_id = c.term_id
   where v_student_id is not null and s.student_id = v_student_id
     and s.reward_granted and not s.reward_effect_seen;
  return v_result;
end
$$;
revoke all on function public.reward_effects() from public, anon;
grant execute on function public.reward_effects() to authenticated;

-- ผล: { marked } จำนวนที่ตั้งดูแล้วในครั้งนี้
create function public.mark_reward_effect_seen(p_submission_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_marked integer := 0;
begin
  perform private.require_student_account();
  if p_submission_ids is null or cardinality(p_submission_ids) = 0 or cardinality(p_submission_ids) > 500 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_student_id := private.current_student();
  if v_student_id is not null then
    update public.submissions s
       set reward_effect_seen = true
     where s.id = any (p_submission_ids) and s.student_id = v_student_id
       and s.reward_granted and not s.reward_effect_seen;
    get diagnostics v_marked = row_count;
  end if;
  return jsonb_build_object('marked', v_marked);
end
$$;
revoke all on function public.mark_reward_effect_seen(uuid[]) from public, anon;
grant execute on function public.mark_reward_effect_seen(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. ปรับยอดมือ (POST /students/:id/wallet/adjust)
-- ---------------------------------------------------------------------------
-- p_delta: จำนวนเต็มไม่เป็น 0 ไม่เกิน ±1,000 ต่อครั้ง (เพดานกันพิมพ์ผิด เท่าโทเคนรางวัลต่องาน)
-- p_expected_version: รุ่นยอดที่หน้าจอเห็น (0 = ยังไม่มีแถว = ยอด 0)
-- ผล: { student_id, term_id, balance, version }
create function public.wallet_adjust(
  p_student_id uuid,
  p_delta integer,
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
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_wallet public.wallets;
  v_now timestamptz;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_student_id is null or p_delta is null or p_delta = 0 or abs(p_delta) > 1000
     or p_expected_version is null or p_expected_version < 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'wallet_adjust:' || md5(jsonb_build_object(
    'student_id', p_student_id, 'delta', p_delta, 'expected_version', p_expected_version)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  if not exists (select 1 from public.students s where s.id = p_student_id) then
    raise exception using errcode = 'P0001', message = 'student_not_found';
  end if;

  -- ลำดับล็อก (ส่วน 7): term_control → wallets; การเริ่ม/จบภาคเรียน (0039) ล็อก exclusive จึงรอกัน
  select c.term_id into v_term_id from public.term_control c where c.singleton for share;
  select w.* into v_wallet from public.wallets w
   where w.student_id = p_student_id and w.term_id = v_term_id for update;
  if coalesce(v_wallet.version, 0) <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  if coalesce(v_wallet.balance, 0) + p_delta < 0 then
    raise exception using errcode = 'P0001', message = 'insufficient_balance';
  end if;

  v_now := clock_timestamp();
  if v_wallet.student_id is null then
    -- แถวแรกของเทอม: ถ้ามีคำขออื่นสร้างแถวไปพร้อมกัน (ตรวจงานหรือปรับมือ) ยอดที่หน้าจอเห็นไม่ใช่ยอดล่าสุดแล้ว
    insert into public.wallets as w (student_id, term_id, balance, version, updated_at)
    values (p_student_id, v_term_id, p_delta, 1, v_now)
    on conflict (student_id, term_id) do nothing
    returning w.* into v_wallet;
    if v_wallet.student_id is null then
      raise exception using errcode = 'P0001', message = 'stale_revision';
    end if;
  else
    update public.wallets w
       set balance = w.balance + p_delta, version = w.version + 1, updated_at = v_now
     where w.student_id = p_student_id and w.term_id = v_term_id
    returning w.* into v_wallet;
  end if;

  v_result := jsonb_build_object(
    'student_id', v_wallet.student_id,
    'term_id', v_wallet.term_id,
    'balance', v_wallet.balance,
    'version', v_wallet.version);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.wallet_adjust(uuid, integer, integer, uuid, boolean) from public, anon;
grant execute on function public.wallet_adjust(uuid, integer, integer, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. ข้อมูลรางวัลในสถานะงาน
-- ---------------------------------------------------------------------------
-- S03 (เดิม 0021) + reward_tokens, reward_granted, current_term (ห้องของงานอยู่ในเทอมกระเป๋าปัจจุบัน — false = งานภาคเรียนก่อน)
create or replace function public.submission_status(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_classroom_id uuid;
  v_assignment public.assignments;
  v_student_id uuid;
  v_sub public.submissions;
  v_now timestamptz := clock_timestamp();
  v_verdict jsonb;
begin
  perform private.require_student_account();
  select p.classroom_id into v_classroom_id from public.posts p where p.id = p_assignment_id and p.kind = 'homework';
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  v_student_id := private.require_member(v_classroom_id);
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  select s.* into v_sub from public.submissions s
   where s.assignment_id = p_assignment_id and s.student_id = v_student_id;
  v_verdict := private.submission_verdict(p_assignment_id, v_student_id, v_now);
  return jsonb_build_object(
    'assignment_id', p_assignment_id,
    'classroom_id', v_classroom_id,
    'server_now', v_now,
    'due_at', v_assignment.due_at,
    'close_at', v_assignment.close_at,
    'intake', private.assignment_intake(p_assignment_id, v_now),
    'solution_published', exists (select 1 from public.solutions s
                                   where s.assignment_id = p_assignment_id and s.published_at is not null),
    'permission_open', v_sub.id is not null and exists (select 1 from public.revision_permissions r
                                                         where r.submission_id = v_sub.id and r.status = 'open'),
    'outcome', v_verdict -> 'outcome',
    'blocked', v_verdict -> 'blocked',
    'reward_tokens', v_assignment.reward_tokens,
    'reward_granted', coalesce(v_sub.reward_granted, false),
    'current_term', exists (select 1 from public.classrooms c join public.term_control tc on tc.singleton
                             where c.id = v_classroom_id and tc.term_id = c.term_id),
    'submission', case when v_sub.id is null then null else jsonb_build_object(
      'submission_id', v_sub.id,
      'content_revision', v_sub.content_revision,
      'first_submitted_at', v_sub.first_submitted_at,
      'last_submitted_at', v_sub.last_submitted_at,
      'first_after_solution', v_sub.first_after_solution,
      'timing', private.submission_timing(v_sub.first_submitted_at, v_sub.first_after_solution, v_assignment.due_at),
      'files', private.submission_files_json(v_sub.id)) end);
end
$$;

-- T03 (เดิม 0022) + reward_tokens, current_term ระดับงาน และ reward_granted ต่อแถว — หน้าตรวจใช้แสดงผลที่คาด
-- ก่อนบันทึกผ่าน (ได้โทเคน / ได้แล้ว / ส่งสาย / งานเทอมเก่า)
create or replace function public.teacher_submission_list(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_classroom_id uuid;
  v_term_id uuid;
  v_due timestamptz;
  v_reward integer;
  v_now timestamptz := clock_timestamp();
begin
  select c.id, c.term_id, a.due_at, a.reward_tokens into v_classroom_id, v_term_id, v_due, v_reward
    from public.posts p
    join public.assignments a on a.post_id = p.id
    join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id;
  if v_classroom_id is null or not private.can_teach_classroom(v_classroom_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return jsonb_build_object(
    'assignment_id', p_assignment_id,
    'classroom_id', v_classroom_id,
    'server_now', v_now,
    'intake', private.assignment_intake(p_assignment_id, v_now),
    'solution_published', exists (select 1 from public.solutions x
                                   where x.assignment_id = p_assignment_id and x.published_at is not null),
    'reward_tokens', v_reward,
    'current_term', exists (select 1 from public.term_control tc where tc.singleton and tc.term_id = v_term_id),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'student_id', st.id,
               'roll_number', e.roll_number,
               'display_name', st.display_name,
               'member', x.member,
               'submission_id', s.id,
               'first_submitted_at', s.first_submitted_at,
               'last_submitted_at', s.last_submitted_at,
               'content_revision', s.content_revision,
               'timing', case when s.id is not null
                              then private.submission_timing(s.first_submitted_at, s.first_after_solution, v_due) end,
               'graded', s.id is not null and private.submission_latest_graded(s.id),
               'reward_granted', coalesce(s.reward_granted, false),
               'file_count', (select count(*) from public.attachments t where t.submission_id = s.id)::integer)
               order by e.roll_number nulls last, st.display_name, st.id)
        from private.assignment_people(p_assignment_id) x
        join public.students st on st.id = x.student_id
        left join public.roster_entries e on e.student_id = st.id and e.term_id = v_term_id
        left join public.submissions s on s.assignment_id = p_assignment_id and s.student_id = st.id), '[]'::jsonb));
end
$$;

-- T05 (เดิม 0008) + wallet_balance, wallet_version ของเทอมกระเป๋าปัจจุบัน (ไม่มีแถว = 0, 0) สำหรับช่องปรับโทเคน
create or replace function public.roster_overview(p_admin_mode boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_teacher(p_admin_mode);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'student_id', s.id,
             'display_name', s.display_name,
             'student_code', s.student_code,
             'group_name', e.group_name,
             'roll_number', e.roll_number,
             'bound', s.account_id is not null,
             'account_email', private.mask_email(a.email),
             'classrooms', coalesce((
               select jsonb_agg(c.name order by c.name)
                 from public.memberships m
                 join public.classrooms c on c.id = m.classroom_id and c.term_id = e.term_id
                where m.student_id = s.id), '[]'::jsonb),
             'wallet_balance', coalesce(w.balance, 0),
             'wallet_version', coalesce(w.version, 0)
           ) order by e.group_name, e.roll_number)
      from public.roster_entries e
      join public.term_control tc on tc.singleton and tc.term_id = e.term_id
      join public.students s on s.id = e.student_id
      left join public.accounts a on a.id = s.account_id
      left join public.wallets w on w.student_id = s.id and w.term_id = tc.term_id
  ), '[]'::jsonb);
end
$$;
