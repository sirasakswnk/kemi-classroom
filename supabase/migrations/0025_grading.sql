-- 0025_grading: ผลตรวจและความคิดเห็น — migration กลุ่ม grading ส่วนแรก (P4-01)
-- TECHNICAL_DESIGN ส่วน 2 (grades, grade_timing, comments), 5 (I1–I3, "รุ่นล่าสุดมีผลตรวจแล้ว"), 6 ข้อ 1–5;
-- SYSTEM_SPEC K1, K2, L2, L4, J2, J3, I1–I3; TECHNICAL_BUILD_PLAN 4.1, 4.2 แถว 8, ส่วน 10 ระยะ 4 (ขอบเขตกับระยะ 5)
-- หลัก:
--   - grades = ผลตรวจหนึ่งแถวต่องานส่ง เก็บรุ่นงานที่ตรวจ (graded_revision); ส่งแก้แล้วผลเดิมยังอยู่แต่เป็นของรุ่นก่อน
--     ("รอตรวจใหม่" — ส่วน 5 ข้อเสนอท้ายส่วน) จนครูบันทึกใหม่; ผ่าน/ไม่ผ่านบันทึกทุกครั้ง คะแนนดิบว่างได้
--   - ภาพกติกาที่ใช้ตรวจ (grade_timing ในส่วน 2) เก็บเป็นคอลัมน์ timing_* ของ grades (1:1 จึงไม่แยกตาราง):
--     ทัน/สาย กำหนดที่ใช้ ฐานเวลา และข้อยกเว้น I1 — หน้าจอจึงไม่คำนวณทับผลเดิมเมื่อกำหนดส่งเปลี่ยน (I2/N3)
--     ครูบันทึกใหม่ = คำนวณใหม่จากกำหนดปัจจุบัน (คำสั่งที่ชัดเจนตามข้อเสนอการแปลง I2)
--   - หักสายด้วยจำนวนเต็ม (raw × (100 − pct) + 99) / 100 ในชนิด bigint (K1: คะแนนเต็มถึง 1,000,000 ไม่ล้น)
--   - L4/K2: บันทึกคะแนนดิบครั้งแรกของงานตั้ง assignments.full_score_locked_at ใน transaction เดียวกัน
--     (trigger 0010 กันการแก้คะแนนเต็ม/% หักหลังจากนั้น); บันทึกเฉพาะผ่าน/ไม่ผ่านไม่ล็อก
--   - L2/J3: ปรับ % หักรายคนใช้ได้เฉพาะงานที่คำนวณแล้วว่าสาย; ตั้ง/เปลี่ยน/ล้างต้องมีเหตุผล ซึ่งกลายเป็นความคิดเห็น
--     ส่วนตัวของครูที่นักเรียนเห็น ผูกกับผลตรวจ ใน transaction เดียวกัน
--   - ระยะ 4 ไม่ให้โทเคนและไม่แตะ reward_granted (BUILD_PLAN ส่วน 10) — ขั้นให้รางวัล (ส่วน 6 ข้อ 6–7) ระยะ 5 เติม
--     ในฟังก์ชันเดียวกันตรงจุดที่ทำเครื่องหมายไว้ ให้อยู่ใน transaction เดียวกับผลตรวจ
--   - comments = ช่องความคิดเห็นส่วนตัวของ (งาน, นักเรียน) แม้ยังไม่ส่ง; คำสั่งเขียน/ยกเลิก (F5) มากับ P4-02
--     ตารางรองรับการยกเลิกแล้ว: ยกเลิก = ล้างข้อความ (ไม่เก็บสำเนา — ส่วน 6 ท้ายส่วน) + ตั้ง retracted_at
--
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: score_invalid (คะแนนดิบไม่ใช่ 0–คะแนนเต็ม), penalty_not_late (ปรับการหักของงานที่ไม่สาย),
--   comment_too_long (ข้อความเกิน 2,000 ตัว)
-- รหัสเดิมที่ใช้: forbidden, admin_mode_required, stale_revision, reason_required, late_penalty_invalid
-- รหัสภายใน: invalid_request, request_key_required, request_key_conflict, immutable_field, invalid_status_transition

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
-- ความคิดเห็นส่วนตัวของงานหนึ่งกับนักเรียนหนึ่งคน (เห็นเฉพาะนักเรียนคนนั้นและครูเจ้าของห้อง/ผู้ดูแล — ส่วน 11)
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  -- ลบงานแล้วหายตาม (N4 — คำสั่งลบมากับ P4-09)
  assignment_id uuid not null references public.assignments (post_id) on delete cascade,
  student_id uuid not null references public.students (id),
  author_account_id uuid not null references public.accounts (id),
  -- เพดาน 2,000 ตัวเป็นตัวกันค่าผิดพลาด; ยกเลิกแล้วข้อความเป็น null
  body text check (body is null or (body = btrim(body) and length(body) between 1 and 2000)),
  created_at timestamptz not null default clock_timestamp(),
  retracted_at timestamptz,
  check ((retracted_at is null) = (body is not null))
);
create index comments_assignment_id_student_id_idx on public.comments (assignment_id, student_id, created_at);
create index comments_student_id_idx on public.comments (student_id);
create index comments_author_account_id_idx on public.comments (author_account_id);

-- ผลตรวจล่าสุดของงานส่ง (ส่วน 2: grades + grade_timing)
create table public.grades (
  submission_id uuid primary key references public.submissions (id) on delete cascade,
  -- คะแนนก่อนหัก (K1: 0–คะแนนเต็ม ตรวจใน RPC) — null = บันทึกเฉพาะผ่าน/ไม่ผ่าน
  raw_score integer check (raw_score between 0 and 1000000),
  -- ยืนยันงานครบถ้วน (แยกจากคะแนน); ไม่ผ่าน = ตรวจแล้วยังไม่ครบ
  passed boolean not null,
  -- L2: % หักเฉพาะคน (null = ใช้ของงาน, 0 = ยกเว้น) ใช้ได้เฉพาะงานสาย
  penalty_override_pct integer check (penalty_override_pct between 0 and 100),
  -- ความคิดเห็นที่เป็นเหตุผลของการตั้ง/ล้าง override ครั้งล่าสุด (ยกเลิกข้อความได้ตาม F5 ผลตรวจคงอยู่)
  override_comment_id uuid references public.comments (id),
  -- grade_timing: ทัน/สายที่ใช้ตรวจ, กำหนดส่ง ณ ตอนตรวจ, ฐานเวลา (เวลาส่งครั้งแรก), I1 (ส่งแรกทัน ส่งแก้หลังกำหนด)
  timing text not null check (timing in ('on_time', 'late')),
  timing_due_at timestamptz not null,
  timing_basis_at timestamptz not null,
  timing_i1 boolean not null,
  -- ค่าที่ใช้คำนวณจริง: % หัก (0 เมื่อทัน), คะแนนที่หัก, คะแนนสุทธิ
  applied_penalty_pct integer not null check (applied_penalty_pct between 0 and 100),
  deduction integer,
  net_score integer,
  graded_revision integer not null check (graded_revision >= 1),
  graded_at timestamptz not null,
  graded_by_account_id uuid not null references public.accounts (id),
  -- รุ่นของผลตรวจ (บันทึกจากหน้าจอที่เห็นรุ่นเก่า → stale_revision)
  version integer not null default 1 check (version >= 1),
  check ((raw_score is null) = (net_score is null) and (raw_score is null) = (deduction is null)),
  check (net_score >= 0 and deduction >= 0 and deduction = raw_score - net_score),
  check (timing = 'late' or (applied_penalty_pct = 0 and penalty_override_pct is null)),
  check (penalty_override_pct is null or override_comment_id is not null),
  check (not timing_i1 or timing = 'on_time')
);
create index grades_override_comment_id_idx on public.grades (override_comment_id);
create index grades_graded_by_account_id_idx on public.grades (graded_by_account_id);

alter table public.comments enable row level security;
alter table public.grades enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ตัวกันช่องที่แก้ไม่ได้ — trigger ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
create function private.comments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.assignment_id <> old.assignment_id or new.student_id <> old.student_id
     or new.author_account_id <> old.author_account_id or new.created_at <> old.created_at then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  -- เปลี่ยนได้ทางเดียว: ยกเลิก (ล้างข้อความ + ตั้งเวลา) ยกเลิกแล้วไม่กลับ และแก้ข้อความไม่ได้
  if old.retracted_at is not null and (new.retracted_at, new.body) is distinct from (old.retracted_at, old.body) then
    raise exception using errcode = 'P0001', message = 'invalid_status_transition';
  end if;
  if old.retracted_at is null and new.retracted_at is null and new.body is distinct from old.body then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger comments_guard
  before update on public.comments
  for each row execute function private.comments_guard();

create function private.grades_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.submission_id <> old.submission_id or new.version <= old.version
     or new.graded_revision < old.graded_revision then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger grades_guard
  before update on public.grades
  for each row execute function private.grades_guard();

-- ---------------------------------------------------------------------------
-- 3. RLS อ่าน (ฟังก์ชันช่วยเดิมใน private — EXECUTE ให้ authenticated อยู่แล้ว)
-- ---------------------------------------------------------------------------
grant select on public.comments, public.grades to authenticated;

-- นักเรียนเจ้าของช่อง (แม้ถูกเอาออกจากห้องแล้ว — แบบเดียวกับงานส่ง) หรือครูเจ้าของห้อง/ผู้ดูแล
create policy comments_select on public.comments
  for select to authenticated
  using (student_id = (select private.current_student()) or private.post_access(assignment_id) = 'teacher');

-- ผลตรวจ = สิทธิ์อ่านงานส่ง
create policy grades_select on public.grades
  for select to authenticated
  using (private.can_read_submission(submission_id));

-- ---------------------------------------------------------------------------
-- 4. สูตรคะแนนและ "รุ่นล่าสุดมีผลตรวจแล้ว" (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- คะแนนสุทธิ = ceil(raw × (100 − pct) / 100) ด้วยจำนวนเต็มล้วน (ส่วน 6 ข้อ 3, L2) — ชุดตัวอย่างร่วมกับหน้าเว็บ
-- อยู่ที่ supabase/tests/fixtures/score_cases.json
create function private.grade_net_score(p_raw integer, p_pct integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((p_raw::bigint * (100 - p_pct) + 99) / 100)::integer
$$;

-- แทนตัวชั่วคราวของ 0020 (ที่คืน false): มีผลตรวจของ content_revision ล่าสุด
-- ใช้ใน submission_outcome (แถว 5/6), teacher_work_summary (รอตรวจ), teacher_submission_list (graded)
create or replace function private.submission_latest_graded(p_submission_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.grades g
      join public.submissions s on s.id = g.submission_id
     where g.submission_id = p_submission_id and g.graded_revision = s.content_revision)
$$;

-- ---------------------------------------------------------------------------
-- 5. บันทึกผลตรวจ (POST /submissions/:id/grade)
-- ---------------------------------------------------------------------------
-- p_raw            คะแนนก่อนหัก (null = บันทึกเฉพาะผ่าน/ไม่ผ่าน)
-- p_pass           ยืนยันงานครบถ้วน (บังคับ)
-- p_override_pct   % หักเฉพาะคน (null = ใช้ของงาน) — ส่งค่าเดิมมาได้โดยไม่ต้องมีเหตุผล
-- p_reason         เหตุผลเมื่อตั้ง/เปลี่ยน/ล้าง % หักเฉพาะคนของงานสาย (นอกจากนั้นต้องเป็น null)
-- p_seen_revision  content_revision ของไฟล์ที่ครูเปิดดู (นักเรียนส่งใหม่ระหว่างตรวจ → stale_revision)
-- p_expected_version  version ของผลตรวจที่หน้าจอเห็น (0 = ยังไม่เคยตรวจ)
-- ตรวจงานภาคเรียนที่จบแล้ว/ภาคเรียนก่อนได้ (K5, I5) และงานของนักเรียนที่ถูกเอาออกแล้วได้
create function public.grade_submission(
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
  select c.teacher_id into v_teacher_id
    from public.submissions s
    join public.posts p on p.id = s.assignment_id
    join public.classrooms c on c.id = p.classroom_id
   where s.id = p_submission_id;
  if not found or (v_account.role = 'teacher' and v_teacher_id is distinct from v_account.teacher_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  -- ลำดับล็อก (ส่วน 6 ข้อ 2): term_control → assignments → submissions (→ wallets ในระยะ 5)
  -- term_control แบบ share: การเริ่ม/จบภาคเรียน (ระยะ 5) ล็อก exclusive จึงไม่ชนกลางการให้รางวัล
  perform 1 from public.term_control c where c.singleton for share;
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
  -- L2: ปรับรายคนได้เฉพาะงานสาย; งานที่กลายเป็นทัน (ขยายกำหนด) ล้าง override เดิมโดยไม่ต้องมีเหตุผล
  if v_timing = 'on_time' and p_override_pct is not null then
    raise exception using errcode = 'P0001', message = 'penalty_not_late';
  end if;
  v_override := p_override_pct;
  v_reason_needed := v_timing = 'late' and v_override is distinct from v_old.penalty_override_pct;
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
  elsif v_timing = 'late' then
    v_comment_id := v_old.override_comment_id;
  end if;

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

  -- ===== ระยะ 5: ขั้นให้รางวัล (TECHNICAL_DESIGN ส่วน 6 ข้อ 6–7) เติมตรงนี้ =====
  -- เงื่อนไข: v_timing = 'on_time' (ไม่ใช่ส่งแรกหลังเฉลย), p_pass, งานอยู่ในภาคเรียนของกระเป๋าปัจจุบัน (I5),
  -- v_sub.reward_granted = false → ล็อก wallets (หลัง submissions) เพิ่มยอด reward_tokens และตั้ง reward_granted = true
  -- ใน transaction นี้; ระยะ 4 ไม่ให้โทเคนและไม่แตะ reward_granted (I3: ไม่ถอนเมื่อเปลี่ยนเป็นไม่ผ่าน)
  -- ===========================================================================

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
    'reward_granted', v_sub.reward_granted);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.grade_submission(uuid, integer, boolean, integer, text, integer, integer, uuid, boolean)
  from public, anon;
grant execute on function public.grade_submission(uuid, integer, boolean, integer, text, integer, integer, uuid, boolean)
  to authenticated;
