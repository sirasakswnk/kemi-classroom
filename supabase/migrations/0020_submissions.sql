-- 0020_submissions: งานส่งของนักเรียน — migration กลุ่ม submissions (P3-07)
-- TECHNICAL_DESIGN ส่วน 2 (submissions, revision_permissions, attachments), 5 (ตารางรับการส่ง 7 แถว, I1–I5), 9 ข้อ 1–8,
-- 9.1 ข้อ 3; SYSTEM_SPEC K3, K5, E1, I4; TECHNICAL_BUILD_PLAN 4.1 ข้อ 4–6, 4.2 แถว 7
-- หลัก:
--   - submissions = งานส่งหนึ่งแถวต่อ (งาน, นักเรียน) เกิดเมื่อส่งสำเร็จครั้งแรกเท่านั้น (อัปโหลดอย่างเดียวไม่ใช่การส่ง)
--     ผูกกับนักเรียน ไม่ผูกกับ membership: ถูกเอาออกแล้วเข้าใหม่เห็นงานเดิม
--   - ทัน/สายไม่เก็บเป็นคอลัมน์: คิดจาก first_submitted_at เทียบ due_at ปัจจุบันเสมอ (I2/N3) และ first_after_solution = สายเสมอ
--   - revision_permissions = สิทธิ์ส่งแก้ที่ครูเปิดรายคน (K3) ใช้ได้กับการส่งสำเร็จหนึ่งครั้ง; คำสั่งเปิดสิทธิ์มากับ P4-02
--   - ไฟล์งานส่งอยู่ใน attachments (คอลัมน์ submission_id ใหม่) เรียงตามลำดับที่นักเรียนแนบ
--   - submit_assignment ล็อกตามลำดับ term_control → assignments → submissions แล้วอ่าน clock_timestamp() หลังได้ล็อก
--     และตรวจไฟล์แล้ว (ส่วน 5) — ไฟล์ที่ถูกแทนเลิกผูก เข้าสถานะ deleting และเพิ่มงานลบ B2 แบบระบุ version_id ลง jobs
--     ใน transaction เดียวกัน (ส่วน 9 ข้อ 5–6, 9.1 ข้อ 3) ตัวทำงานลบ (process-jobs) มากับ P3-10
--   - "รุ่นล่าสุดมีผลตรวจแล้ว" และ "ปิดรับ" ถามผ่านฟังก์ชันเดียวใน private (submission_latest_graded, assignment_intake)
--     ให้ P4-01/P4-03 แทนที่ภายหลัง (ส่วน 5 ใต้ตาราง)
--   - pg_cron + pg_net เรียก process-jobs (BUILD_PLAN 4.2 แถว 7) ทำพร้อมตัวทำงานใน P3-10
--
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: submission_closed, resubmit_not_allowed, submission_files_required, submission_file_unavailable
-- รหัสเดิมที่ submit_assignment ใช้: not_member, term_ended, stale_revision, too_many_files, batch_too_large, forbidden
-- รหัสภายใน: invalid_request, request_key_required, request_key_conflict, immutable_field, invalid_status_transition

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  -- ลบงานแล้วงานส่งหายตาม (N4 — คำสั่งลบมากับ P4-09 พร้อมเข้าคิวลบไฟล์)
  assignment_id uuid not null references public.assignments (post_id) on delete cascade,
  -- ห้ามย้ายไปนักเรียนคนอื่น (ส่วน 2) — นักเรียนไม่มีคำสั่งลบ
  student_id uuid not null references public.students (id),
  -- เวลาที่เซิร์ฟเวอร์รับการส่งสำเร็จ (clock_timestamp() หลังได้ล็อก) ครั้งแรกและล่าสุด
  first_submitted_at timestamptz not null,
  last_submitted_at timestamptz not null,
  -- แถว 4: ส่งครั้งแรกหลังเผยแพร่เฉลย = สายและไม่มีโทเคน แม้ขยายกำหนดภายหลัง
  first_after_solution boolean not null default false,
  -- รุ่นของชุดไฟล์ เพิ่มทุกการส่งสำเร็จ (คำขอที่ส่งรุ่นเก่ามา → stale_revision)
  content_revision integer not null default 1 check (content_revision >= 1),
  -- รางวัลงานนี้ให้แล้ว (กลุ่ม rewards) — false → true ได้ครั้งเดียว ไม่ย้อน (I3)
  reward_granted boolean not null default false,
  unique (assignment_id, student_id),
  check (last_submitted_at >= first_submitted_at)
);
create index submissions_student_id_idx on public.submissions (student_id);

-- สิทธิ์ส่งแก้ (K3): เปิดหนึ่งครั้ง ใช้กับการส่งสำเร็จหนึ่งครั้ง; ส่งล้มเหลวไม่ใช้สิทธิ์; ครูเปิดใหม่ได้หลังใช้แล้ว
-- เปิดค้างได้ทีละหนึ่งสิทธิ์ต่องานส่ง; ไม่มีเดดไลน์รายคน
create table public.revision_permissions (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id) on delete cascade,
  opened_by_account_id uuid not null references public.accounts (id),
  opened_at timestamptz not null default clock_timestamp(),
  status text not null default 'open' check (status in ('open', 'used', 'revoked')),
  -- การส่งที่ใช้สิทธิ์นี้ (content_revision หลังส่ง) และเวลา
  used_at timestamptz,
  used_revision integer check (used_revision >= 2),
  revoked_at timestamptz,
  check ((status = 'used') = (used_at is not null and used_revision is not null)),
  check ((status = 'revoked') = (revoked_at is not null))
);
create unique index revision_permissions_open_key on public.revision_permissions (submission_id) where status = 'open';
create index revision_permissions_submission_id_idx on public.revision_permissions (submission_id);
create index revision_permissions_opened_by_account_id_idx on public.revision_permissions (opened_by_account_id);

alter table public.submissions enable row level security;
alter table public.revision_permissions enable row level security;

-- ไฟล์งานส่ง: เป้าหมายที่สามของ attachments (charm เพิ่มในระยะ 5)
alter table public.attachments
  add column submission_id uuid references public.submissions (id) on delete cascade,
  drop constraint attachments_one_target,
  add constraint attachments_one_target check (num_nonnulls(post_id, solution_id, submission_id) = 1),
  add constraint attachments_submission_position_key unique (submission_id, position) deferrable initially immediate;

-- ---------------------------------------------------------------------------
-- 2. ตัวกันช่องที่แก้ไม่ได้ — trigger ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
create function private.submissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.assignment_id <> old.assignment_id or new.student_id <> old.student_id
     or new.first_submitted_at <> old.first_submitted_at or new.first_after_solution <> old.first_after_solution
     or new.content_revision < old.content_revision or new.last_submitted_at < old.last_submitted_at
     or (old.reward_granted and not new.reward_granted) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger submissions_guard
  before update on public.submissions
  for each row execute function private.submissions_guard();

create function private.revision_permissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception using errcode = 'P0001', message = 'invalid_status_transition';
    end if;
    return new;
  end if;
  if new.id <> old.id or new.submission_id <> old.submission_id
     or new.opened_by_account_id <> old.opened_by_account_id or new.opened_at <> old.opened_at then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  -- open → used | revoked เท่านั้น ใช้แล้ว/ยกเลิกแล้วไม่กลับมาเปิด (ครูเปิดสิทธิ์ใหม่เป็นแถวใหม่)
  if (old.status <> 'open' and (new.status, new.used_at, new.used_revision, new.revoked_at)
                               is distinct from (old.status, old.used_at, old.used_revision, old.revoked_at)) then
    raise exception using errcode = 'P0001', message = 'invalid_status_transition';
  end if;
  return new;
end
$$;

create trigger revision_permissions_guard
  before insert or update on public.revision_permissions
  for each row execute function private.revision_permissions_guard();

-- attachments: เพิ่มเป้าหมาย submission (จาก 0011)
create or replace function private.attachments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_asset public.assets;
  v_purpose text;
begin
  if tg_op = 'UPDATE' then
    -- แก้ได้เฉพาะลำดับ
    if new.id <> old.id or new.asset_id <> old.asset_id or new.post_id is distinct from old.post_id
       or new.solution_id is distinct from old.solution_id or new.submission_id is distinct from old.submission_id
       or new.created_at <> old.created_at then
      raise exception using errcode = 'P0001', message = 'immutable_field';
    end if;
    return new;
  end if;

  -- ผูกได้เฉพาะไฟล์ที่พร้อมใช้ และล็อกไว้กันการเปลี่ยนเป็น deleting พร้อมกัน
  select a.* into v_asset from public.assets a where a.id = new.asset_id for share;
  if not found or v_asset.status <> 'ready' then
    raise exception using errcode = 'P0001', message = 'asset_not_ready';
  end if;
  -- ไม่มีเป้าหมาย/หลายเป้าหมาย ให้ check attachments_one_target ตอบ
  v_purpose := case when new.post_id is not null then 'post'
                    when new.solution_id is not null then 'solution'
                    when new.submission_id is not null then 'submission' end;
  if v_purpose is not null and v_asset.purpose <> v_purpose then
    raise exception using errcode = 'P0001', message = 'attachment_purpose_mismatch';
  end if;
  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. RLS อ่าน (ฟังก์ชันช่วยอยู่ใน private: EXECUTE ให้ authenticated ไม่ให้ USAGE — 3.1 ข้อ 5)
-- ---------------------------------------------------------------------------
-- อ่านงานส่งนี้ได้หรือไม่: นักเรียนเจ้าของงาน (แม้ถูกเอาออกจากห้องแล้ว — งานเป็นของนักเรียน) หรือครูเจ้าของห้อง/ผู้ดูแล
create function private.can_read_submission(p_submission_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select s.student_id = private.current_student() or private.post_access(s.assignment_id) = 'teacher'
      from public.submissions s
     where s.id = p_submission_id), false)
$$;
grant execute on function private.can_read_submission(uuid) to authenticated;

grant select on public.submissions, public.revision_permissions to authenticated;

create policy submissions_select on public.submissions
  for select to authenticated
  using (student_id = (select private.current_student()) or private.post_access(assignment_id) = 'teacher');

create policy revision_permissions_select on public.revision_permissions
  for select to authenticated
  using (private.can_read_submission(submission_id));

-- ไฟล์งานส่ง = สิทธิ์อ่านงานส่ง (เพื่อนร่วมห้องไม่เห็น)
alter policy attachments_select on public.attachments
  using ((post_id is not null and private.post_access(post_id) is not null)
         or (solution_id is not null and private.can_read_solution(solution_id))
         or (submission_id is not null and private.can_read_submission(submission_id)));

-- ---------------------------------------------------------------------------
-- 4. สิทธิ์เปิดไฟล์ (จาก 0018 + ไฟล์งานส่ง: นักเรียนเจ้าของ + ครูเจ้าของห้อง/ผู้ดูแล)
-- ---------------------------------------------------------------------------
create or replace function public.authorize_files(p_asset_ids uuid[])
returns uuid[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account uuid := private.current_account();
  v_limits jsonb := private.files_sign_limits();
  v_ids uuid[];
begin
  if v_account is null then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  v_ids := private.files_sign_ids(p_asset_ids);
  perform private.rate_limit_hit(v_account, 'files_sign', (v_limits ->> 'rate_limit')::integer,
                                 make_interval(mins => (v_limits ->> 'rate_window_minutes')::integer));
  return coalesce((
    select array_agg(a.id order by u.n)
      from unnest(v_ids) with ordinality u(id, n)
      join public.assets a on a.id = u.id
      left join public.attachments t on t.asset_id = a.id
     where a.status = 'ready'
       and case
             when t.id is null then a.owner_account_id = v_account
             when t.post_id is not null then private.post_access(t.post_id) is not null
             when t.solution_id is not null then private.can_read_solution(t.solution_id)
             when t.submission_id is not null then private.can_read_submission(t.submission_id)
             else false
           end), '{}'::uuid[]);
end
$$;

-- ---------------------------------------------------------------------------
-- 5. ขอชุดอัปโหลด (จาก 0016 + วัตถุประสงค์ submission)
-- ---------------------------------------------------------------------------
-- submission: นักเรียนที่เป็นสมาชิกขณะนี้ของห้องของงาน (not_member), โพสต์เป็นการบ้านของห้องนั้น (forbidden),
--   ภาคเรียนปัจจุบันยัง active และห้องอยู่ในภาคเรียนปัจจุบัน (K5 → term_ended), J4–J6 ชุดนักเรียน 10 ไฟล์/20 MB
--   ไม่ตรวจว่ายังส่งได้หรือไม่ (ปิดรับ/สิทธิ์แก้) — ตัดสินตอน submit_assignment เท่านั้น (ส่วน 9 ท้าย)
--   base_version = content_revision ปัจจุบัน (0 = ยังไม่เคยส่ง); p_admin_mode ไม่มีผล (ครู/ผู้ดูแลส่งงานแทนไม่ได้)
create or replace function public.create_upload_batch(
  p_purpose text,
  p_classroom_id uuid,
  p_post_id uuid,
  p_files jsonb,
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
  v_limits jsonb := private.upload_limits();
  v_classroom public.classrooms;
  v_post public.posts;
  v_term_id uuid;
  v_term_status text;
  v_student_id uuid;
  v_base integer;
  v_file jsonb;
  v_name text;
  v_type text;
  v_size integer;
  v_total bigint := 0;
  v_count integer;
  v_specs jsonb := '[]'::jsonb;
  v_operation text;
  v_prior jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_expires timestamptz;
  v_result jsonb;
begin
  if p_purpose = 'submission' then
    v_account := private.require_student_account();
  else
    v_account := private.require_teacher(p_admin_mode);
  end if;
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  -- charm (ระยะ 5) ยังไม่เปิด
  if p_purpose is null or p_purpose not in ('post', 'solution', 'submission') or p_classroom_id is null
     or (p_purpose in ('solution', 'submission') and p_post_id is null)
     or jsonb_typeof(p_files) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- รายการไฟล์ (J4–J6)
  v_count := jsonb_array_length(p_files);
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if v_count > (v_limits ->> 'max_files')::integer then
    raise exception using errcode = 'P0001', message = 'too_many_files';
  end if;
  for v_file in select value from jsonb_array_elements(p_files)
  loop
    if jsonb_typeof(v_file) <> 'object'
       or exists (select 1 from jsonb_object_keys(v_file) k where k not in ('file_name', 'content_type', 'size_bytes')) then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    v_name := private.trim_text(case when jsonb_typeof(v_file -> 'file_name') = 'string' then v_file ->> 'file_name' end);
    -- ชื่อที่แสดงและใช้ตอนดาวน์โหลด: 1–255 ตัว ไม่มีอักขระควบคุมหรือตัวแบ่งโฟลเดอร์ / และ chr(92) (หน้าเว็บทำความสะอาดก่อนส่ง)
    if v_name is null or length(v_name) > 255 or v_name ~ '[[:cntrl:]/]' or strpos(v_name, chr(92)) > 0 then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    v_type := v_file ->> 'content_type';
    -- ชนิดหลังแปลงบนเครื่อง (HEIC → JPEG ก่อนส่ง — เซิร์ฟเวอร์ไม่รับ HEIC ดิบ และตรวจเนื้อหาจริงอีกครั้งตอน complete)
    if v_type is null or v_type not in ('image/jpeg', 'image/png', 'application/pdf') then
      raise exception using errcode = 'P0001', message = 'file_type_not_allowed';
    end if;
    v_size := private.jsonb_int(v_file -> 'size_bytes');
    if v_size is null or v_size < 1 then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    -- CASE ต้องอยู่ในวงเล็บ: เงื่อนไขของ IF ใน plpgsql อ่านถึงคำว่า THEN ตัวแรก
    if v_size > (case when v_type = 'application/pdf' then (v_limits ->> 'max_pdf_bytes')::integer
                      else (v_limits ->> 'max_image_bytes')::integer end) then
      raise exception using errcode = 'P0001', message = 'file_too_large';
    end if;
    v_total := v_total + v_size;
    v_specs := v_specs || jsonb_build_array(jsonb_build_object(
      'staging_key', 'staging/' || v_batch_id || '/' || gen_random_uuid(),
      'file_name', v_name, 'content_type', v_type, 'size_bytes', v_size));
  end loop;
  if v_total > (v_limits ->> 'max_batch_bytes')::bigint then
    raise exception using errcode = 'P0001', message = 'batch_too_large';
  end if;

  -- กดซ้ำด้วย request key เดิม → batch เดิม (key ไฟล์เดิม)
  v_operation := 'create_upload_batch:' || md5(jsonb_build_object(
    'purpose', p_purpose, 'classroom_id', p_classroom_id, 'post_id', p_post_id,
    'files', (select jsonb_agg(s - 'staging_key') from jsonb_array_elements(v_specs) s))::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: term_control → ห้อง (ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล) → โพสต์
  select c.term_id, c.status into v_term_id, v_term_status from public.term_control c where c.singleton for share;
  if p_purpose = 'submission' then
    -- สมาชิกขณะนี้ (อ่านแถว membership สด) → งานเป็นการบ้านของห้องนี้ → ภาคเรียน (K5)
    v_student_id := private.require_member(p_classroom_id);
    select c.* into v_classroom from public.classrooms c where c.id = p_classroom_id;
    select p.* into v_post from public.posts p where p.id = p_post_id and p.classroom_id = v_classroom.id;
    if not found or v_post.kind <> 'homework' then
      raise exception using errcode = 'P0001', message = 'forbidden';
    end if;
    if v_term_id is null or v_term_status <> 'active' or v_classroom.term_id <> v_term_id then
      raise exception using errcode = 'P0001', message = 'term_ended';
    end if;
    select s.content_revision into v_base
      from public.submissions s where s.assignment_id = v_post.id and s.student_id = v_student_id;
    v_base := coalesce(v_base, 0);
  else
    v_classroom := private.require_classroom_teacher(p_classroom_id, p_admin_mode);
    if p_post_id is not null then
      select p.* into v_post from public.posts p where p.id = p_post_id and p.classroom_id = v_classroom.id;
      if not found or (p_purpose = 'solution' and v_post.kind <> 'homework') then
        raise exception using errcode = 'P0001', message = 'forbidden';
      end if;
    elsif v_term_id is null or v_classroom.term_id <> v_term_id then
      -- ไฟล์ของโพสต์ใหม่ในห้องของภาคเรียนก่อน: โพสต์ไม่ได้อยู่แล้ว (K5) จึงไม่ให้อัปโหลด
      raise exception using errcode = 'P0001', message = 'term_ended';
    end if;
    v_base := v_post.version;
  end if;

  perform private.rate_limit_hit(v_account.id, 'upload_batch', (v_limits ->> 'rate_limit')::integer,
                                 make_interval(mins => (v_limits ->> 'rate_window_minutes')::integer));
  -- จองพื้นที่ (ล็อกแถว storage_settings จน commit) แล้วสร้าง batch ใน transaction เดียวกัน
  perform private.reserve_storage(v_total);
  v_expires := clock_timestamp() + make_interval(mins => (v_limits ->> 'batch_ttl_minutes')::integer);
  insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, base_version, files,
                                     reserved_bytes, expires_at)
  values (v_batch_id, v_account.id, p_purpose, v_classroom.id, p_post_id, v_base, v_specs, v_total, v_expires);

  v_result := jsonb_build_object(
    'batch_id', v_batch_id,
    'purpose', p_purpose,
    'expires_at', v_expires,
    'reserved_bytes', v_total,
    'files', v_specs);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. สถานะรับงานและผลตรวจ — จุดเดียวที่ P4-01/P4-03 แทนที่ (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- "รุ่นล่าสุดมีผลตรวจแล้ว" = มีคะแนนหรือผลผ่าน/ไม่ผ่านของ content_revision ล่าสุด — ตาราง grades มากับ P4-01
-- ตอนนี้ยังไม่มีการตรวจ จึง false เสมอ
create function private.submission_latest_graded(p_submission_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

-- สถานะรับงาน ณ เวลา p_now:
--   'after_solution' = เผยแพร่เฉลยแล้วและงานตั้งรับหลังเฉลย (ช่วงรับหลังเฉลย — แม้เลยวันปิดรับแล้ว)
--   'closed'         = เผยแพร่เฉลยแล้วแต่ไม่รับหลังเฉลย หรือเลยวันปิดรับแล้ว (close_at รับถึงวินาทีนั้นพอดี เหมือน due_at)
--   'open'           = อื่น ๆ
-- P4-03 เพิ่มปิดรับทันทีและการปิดช่วงรับหลังเฉลยที่นี่
create function private.assignment_intake(p_assignment_id uuid, p_now timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select case
           when exists (select 1 from public.solutions s
                         where s.assignment_id = a.post_id and s.published_at is not null)
             then case when a.accept_after_solution then 'after_solution' else 'closed' end
           when a.close_at is not null and p_now > a.close_at then 'closed'
           else 'open'
         end
    from public.assignments a
   where a.post_id = p_assignment_id
$$;

-- ตารางรับการส่ง (TECHNICAL_DESIGN 5) — ฟังก์ชันล้วน เวลา p_now ส่งเข้ามา จึงทดสอบขอบเวลาได้ตรงวินาที
-- ผล: first_on_time (แถว 2) · first_late (แถว 3) · first_after_solution (แถว 4) · resubmit (แถว 5)
--     resubmit_permission (แถว 6 และแถว 7 กรณีมีสิทธิ์แก้ค้าง — ผู้เรียกต้องใช้สิทธิ์ใน transaction เดียวกัน)
-- แถว 1 (ภาคเรียน) ผู้เรียกตรวจก่อน; "ปิดรับ" (แถว 7) และ "เฉลยเผยแพร่แล้ว" (แถว 4) ตรวจก่อนแถวที่ดูแค่เวลา
-- เพราะปิดรับ/เฉลยต้องชนะกำหนดส่งเสมอ (ด้วยข้อมูลตอนนี้ — close_at ≥ due_at และยังไม่มีคำสั่งเผยแพร่เฉลย —
-- ผลเท่ากับไล่ตามลำดับแถวตรง ๆ)
create function private.submission_rule(
  p_submitted boolean,
  p_due_at timestamptz,
  p_now timestamptz,
  p_intake text,
  p_solution_published boolean,
  p_latest_graded boolean,
  p_has_permission boolean
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if not p_submitted then
    if p_intake = 'after_solution' then
      return 'first_after_solution';                       -- แถว 4 (สายเสมอ ไม่มีโทเคน)
    elsif p_intake = 'closed' then
      raise exception using errcode = 'P0001', message = 'submission_closed';   -- แถว 7 ยังไม่เคยส่ง
    elsif p_now <= p_due_at then
      return 'first_on_time';                              -- แถว 2 (ไม่มีช่วงผ่อนผัน)
    end if;
    return 'first_late';                                   -- แถว 3
  end if;

  -- แถว 5: ยังไม่ถึงกำหนด ยังเปิดรับ (ไม่มีเฉลย) และรุ่นล่าสุดยังไม่มีผลตรวจ — ไม่ใช้สิทธิ์แก้
  if p_intake = 'open' and p_now <= p_due_at and not p_latest_graded then
    return 'resubmit';
  end if;
  -- แถว 6/7: ต้องมีสิทธิ์แก้ค้าง; เฉลยเผยแพร่แล้วต้องอยู่ในช่วงรับหลังเฉลยด้วย (E1)
  if p_solution_published and p_intake <> 'after_solution' then
    raise exception using errcode = 'P0001', message = 'submission_closed';
  end if;
  if not p_has_permission then
    if p_intake = 'closed' then
      raise exception using errcode = 'P0001', message = 'submission_closed';
    end if;
    raise exception using errcode = 'P0001', message = 'resubmit_not_allowed';
  end if;
  return 'resubmit_permission';
end
$$;

-- ---------------------------------------------------------------------------
-- 7. ส่งงาน (POST /assignments/:id/submit)
-- ---------------------------------------------------------------------------
-- รายการไฟล์: 1–10 id ไม่มี null ไม่ซ้ำ (ลำดับ = ลำดับที่แสดง)
create function private.submission_files_ids(p_files uuid[])
returns uuid[]
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_files is null or array_ndims(p_files) > 1 or array_position(p_files, null) is not null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if cardinality(p_files) = 0 then
    raise exception using errcode = 'P0001', message = 'submission_files_required';
  end if;
  if cardinality(p_files) <> (select count(distinct x) from unnest(p_files) x) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  -- J6: นักเรียนแนบได้ 10 ไฟล์ (ค่าเดียวกับ private.upload_limits())
  if cardinality(p_files) > (private.upload_limits() ->> 'max_files')::integer then
    raise exception using errcode = 'P0001', message = 'too_many_files';
  end if;
  return p_files;
end
$$;

-- รายการไฟล์ของงานส่งสำหรับผลของ RPC
create function private.submission_files_json(p_submission_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'asset_id', a.id, 'file_name', a.file_name, 'content_type', a.content_type, 'size_bytes', a.size_bytes)
           order by t.position), '[]'::jsonb)
    from public.attachments t
    join public.assets a on a.id = t.asset_id
   where t.submission_id = p_submission_id
$$;

-- submit_assignment(p_assignment_id, p_files, p_expected_revision, p_request_key)
--   p_files = asset id ตามลำดับ: ไฟล์ใหม่ (ของผู้ส่ง ready วัตถุประสงค์ submission ยังไม่ผูก และมาจาก batch ของงานนี้)
--             + ไฟล์เดิมที่เก็บไว้ (ต้องผูกกับงานส่งรุ่นปัจจุบันของตน) — ผิดข้อใด → submission_file_unavailable ทั้งคำขอ
--   p_expected_revision = content_revision ที่หน้าจอเห็น (0 = ยังไม่เคยส่ง) ไม่ตรง → stale_revision
--   กดซ้ำด้วย request key เดิม → ผลเดิม (ตรวจก่อนเทียบรุ่น)
-- ผล: { submission_id, assignment_id, outcome, submitted_at, first_submitted_at, last_submitted_at, timing (on_time|late),
--       first_after_solution, content_revision, used_permission, files: [{ asset_id, file_name, content_type, size_bytes }] }
create function public.submit_assignment(
  p_assignment_id uuid,
  p_files uuid[],
  p_expected_revision integer,
  p_request_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_ids uuid[];
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_term_status text;
  v_classroom public.classrooms;
  v_assignment public.assignments;
  v_student_id uuid;
  v_sub public.submissions;
  v_perm public.revision_permissions;
  v_count integer;
  v_total bigint;
  v_solution boolean;
  v_now timestamptz;
  v_outcome text;
  v_removed uuid[];
  v_result jsonb;
begin
  v_account := private.require_student_account();
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null or p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_ids := private.submission_files_ids(p_files);

  v_operation := 'submit_assignment:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'files', to_jsonb(v_ids), 'expected_revision', p_expected_revision)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก (BUILD_PLAN 4.1 ข้อ 5): term_control → assignments → submissions → assets
  select c.term_id, c.status into v_term_id, v_term_status from public.term_control c where c.singleton for share;
  select c.* into v_classroom
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id and p.kind = 'homework';
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  -- สมาชิกขณะนี้ (ถูกเอาออก → not_member) แล้วจึงภาคเรียน (แถว 1: K5 ended หรืองานของภาคเรียนก่อน)
  v_student_id := private.require_member(v_classroom.id);
  if v_term_id is null or v_term_status <> 'active' or v_classroom.term_id <> v_term_id then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;

  -- งาน: ล็อกแบบ exclusive เฉพาะตอนที่ยังไม่ล็อกรางวัล (อาจต้องตั้ง reward_locked_at — I4) ไม่อย่างนั้นแค่ FOR SHARE
  -- ให้นักเรียนหลายคนส่งพร้อมกันได้; reward_locked_at ตั้งแล้วไม่ย้อน (trigger 0010) จึงไม่ต้องอัปเกรดล็อกภายหลัง
  -- การเปลี่ยนกำหนดส่ง/ปิดรับ (P4-03) ต้องล็อก FOR UPDATE จึงรอการส่งที่กำลังทำอยู่
  select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id;
  if v_assignment.reward_locked_at is null then
    select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id for no key update;
  else
    select a.* into v_assignment from public.assignments a where a.post_id = p_assignment_id for share;
  end if;

  -- งานส่งของนักเรียนคนนี้: advisory lock ครอบทั้งกรณียังไม่มีแถว (ส่งแรกพร้อมกันสองคำขอ) แล้วล็อกแถว
  perform pg_advisory_xact_lock(hashtextextended('submission:' || p_assignment_id || ':' || v_student_id, 0));
  select s.* into v_sub from public.submissions s
   where s.assignment_id = p_assignment_id and s.student_id = v_student_id for update;
  if coalesce(v_sub.content_revision, 0) <> p_expected_revision then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;

  -- ไฟล์: ล็อกแถว asset ที่ขอ (ตามลำดับ id) ก่อนตรวจ — asset เดียวกันส่งเข้าสองงานพร้อมกันไม่ได้
  perform 1 from public.assets a where a.id = any(v_ids) order by a.id for update;
  select count(*)::integer, coalesce(sum(a.size_bytes), 0)::bigint into v_count, v_total
    from public.assets a
    left join public.attachments t on t.asset_id = a.id
    left join public.upload_batches b on b.id = a.upload_batch_id
   where a.id = any(v_ids)
     and a.status = 'ready'
     and a.purpose = 'submission'
     and ((v_sub.id is not null and t.submission_id = v_sub.id)
          or (t.id is null and a.owner_account_id = v_account.id and b.post_id = p_assignment_id));
  if v_count <> cardinality(v_ids) then
    raise exception using errcode = 'P0001', message = 'submission_file_unavailable';
  end if;
  -- J6: รวมไม่เกิน 20 MB (ค่าเดียวกับ private.upload_limits())
  if v_total > (private.upload_limits() ->> 'max_batch_bytes')::bigint then
    raise exception using errcode = 'P0001', message = 'batch_too_large';
  end if;

  if v_sub.id is not null then
    select r.* into v_perm from public.revision_permissions r
     where r.submission_id = v_sub.id and r.status = 'open' for update;
  end if;
  v_solution := exists (select 1 from public.solutions s
                         where s.assignment_id = p_assignment_id and s.published_at is not null);

  -- เวลาตัดสิน: หลังได้ล็อกและตรวจไฟล์แล้ว (ส่วน 5)
  v_now := clock_timestamp();
  v_outcome := private.submission_rule(
    v_sub.id is not null, v_assignment.due_at, v_now, private.assignment_intake(p_assignment_id, v_now),
    v_solution, v_sub.id is not null and private.submission_latest_graded(v_sub.id), v_perm.id is not null);

  if v_sub.id is null then
    insert into public.submissions (assignment_id, student_id, first_submitted_at, last_submitted_at, first_after_solution)
    values (p_assignment_id, v_student_id, v_now, v_now, v_outcome = 'first_after_solution')
    returning * into v_sub;
    -- I4: การส่งครั้งแรกของงานล็อกจำนวนรางวัลถาวร
    if v_assignment.reward_locked_at is null then
      update public.assignments set reward_locked_at = v_now where post_id = p_assignment_id;
    end if;
  else
    update public.submissions
       set last_submitted_at = v_now, content_revision = content_revision + 1
     where id = v_sub.id
    returning * into v_sub;
    -- K3: ใช้สิทธิ์แก้ใน transaction เดียวกับการส่งที่สำเร็จ
    if v_outcome = 'resubmit_permission' then
      update public.revision_permissions
         set status = 'used', used_at = v_now, used_revision = v_sub.content_revision
       where id = v_perm.id;
    end if;
  end if;

  -- ไฟล์ที่ถูกแทน: เลิกผูก → deleting → งานลบ B2 แบบระบุ version_id (ส่วน 9 ข้อ 5–6) ห้ามเรียกบริการภายนอกที่นี่
  with removed as (
    delete from public.attachments t
     where t.submission_id = v_sub.id and t.asset_id <> all (v_ids)
    returning t.asset_id
  )
  select coalesce(array_agg(asset_id), '{}') into v_removed from removed;
  if cardinality(v_removed) > 0 then
    update public.assets
       set status = 'deleting', delete_requested_at = v_now
     where id = any(v_removed);
    insert into private.jobs (kind, payload, dedupe_key)
    select 'delete_asset',
           jsonb_build_object('asset_id', a.id, 'final_key', a.final_key, 'version_id', a.version_id, 'reason', 'replaced'),
           a.id::text
      from public.assets a
     where a.id = any(v_removed)
    on conflict (kind, dedupe_key) do nothing;
  end if;

  -- ชุดใหม่ตามลำดับ (unique (submission_id, position) ตรวจตอนจบ transaction)
  set constraints public.attachments_submission_position_key deferred;
  update public.attachments t
     set position = u.n
    from unnest(v_ids) with ordinality u(id, n)
   where t.submission_id = v_sub.id and t.asset_id = u.id and t.position <> u.n;
  insert into public.attachments (asset_id, submission_id, position)
  select u.id, v_sub.id, u.n
    from unnest(v_ids) with ordinality u(id, n)
   where not exists (select 1 from public.attachments t where t.asset_id = u.id);

  -- batch ที่ทุกไฟล์ถูกผูกแล้ว: เลิกจอง (แบบเดียวกับ 0019)
  update public.upload_batches b
     set status = 'consumed'
   where b.status = 'open'
     and b.id in (select a.upload_batch_id from public.assets a where a.id = any(v_ids))
     and jsonb_array_length(b.files) = (select count(*) from public.assets a
                                          join public.attachments t on t.asset_id = a.id
                                         where a.upload_batch_id = b.id);

  v_result := jsonb_build_object(
    'submission_id', v_sub.id,
    'assignment_id', v_sub.assignment_id,
    'outcome', v_outcome,
    'submitted_at', v_now,
    'first_submitted_at', v_sub.first_submitted_at,
    'last_submitted_at', v_sub.last_submitted_at,
    -- I1/I2: ทัน/สายคิดจากเวลาส่งครั้งแรกเทียบกำหนดปัจจุบัน; ส่งแรกหลังเฉลยสายเสมอ
    'timing', case when not v_sub.first_after_solution and v_sub.first_submitted_at <= v_assignment.due_at
                   then 'on_time' else 'late' end,
    'first_after_solution', v_sub.first_after_solution,
    'content_revision', v_sub.content_revision,
    'used_permission', v_outcome = 'resubmit_permission',
    'files', private.submission_files_json(v_sub.id));
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.submit_assignment(uuid, uuid[], integer, uuid) from public, anon;
grant execute on function public.submit_assignment(uuid, uuid[], integer, uuid) to authenticated;
