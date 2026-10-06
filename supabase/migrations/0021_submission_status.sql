-- 0021_submission_status: สถานะงานของนักเรียนสำหรับ S03/S02/S01 และการปฏิเสธชุดอัปโหลดที่ส่งไม่ได้แน่นอน — P3-08
-- TECHNICAL_DESIGN ส่วน 5 (ตารางรับการส่ง + ลำดับตรวจที่ทำจริง + ข้อเสนอให้ขอ batch ถูกปฏิเสธเมื่อส่งไม่ได้แน่นอน), 9
-- หลัก: กติกาแถว 1–7 อยู่ที่เดียว — private.submission_outcome (อ่านข้อเท็จจริง แล้วเรียก private.submission_rule ของ 0020)
--   ใช้ร่วมกันโดย submit_assignment (หลังได้ล็อก), create_upload_batch (submission) และ RPC อ่านสถานะ (ไม่บันทึกอะไร)
--   submission_status(p_assignment_id) — S03: ถ้าส่งตอนนี้ผลเป็นอะไร (outcome) หรือส่งไม่ได้เพราะอะไร (blocked = รหัส UX 7.1)
--     + งานส่งปัจจุบัน (รุ่น เวลา ทัน/สาย ไฟล์) + สิทธิ์แก้ค้าง + สถานะรับงาน
--   my_work(p_classroom_id) — S02 (ห้องเดียว) / S01 (ทุกห้องที่เป็นสมาชิก เมื่อส่ง null): การบ้านพร้อมสถานะส่วนตัว
-- ทั้งสองเรียกได้เฉพาะนักเรียน (ครู/ผู้ดูแล → forbidden) และอ่านแถว membership สด (not_member)
-- รหัสใหม่: ไม่มี (ใช้รหัสของ 0020: submission_closed, resubmit_not_allowed, term_ended, not_member, forbidden)

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันตัดสินร่วม (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- แถว 1: ภาคเรียนปัจจุบันยัง active และงานอยู่ในภาคเรียนปัจจุบัน (K5) — อ่านอย่างเดียว ผู้เรียกที่ต้องล็อกถือล็อกเอง
create function private.require_current_term(p_term_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_term uuid;
  v_status text;
begin
  select c.term_id, c.status into v_term, v_status from public.term_control c where c.singleton;
  if v_term is null or v_status <> 'active' or p_term_id is distinct from v_term then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;
end
$$;

-- ทัน/สายของงานส่ง (I1/I2): เวลาส่งครั้งแรกเทียบกำหนดส่งปัจจุบัน; ส่งแรกหลังเฉลยสายเสมอ
create function private.submission_timing(p_first_submitted_at timestamptz, p_first_after_solution boolean,
                                          p_due_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when not p_first_after_solution and p_first_submitted_at <= p_due_at then 'on_time' else 'late' end
$$;

-- ถ้านักเรียนคนนี้ส่งงานนี้ ณ p_now ผลเป็นอะไร (ตารางรับการส่งแถว 1–7) — คืนผลของ submission_rule หรือ raise รหัส
-- (term_ended, submission_closed, resubmit_not_allowed; forbidden = ไม่ใช่การบ้าน) ไม่บันทึกอะไร ไม่ตรวจสมาชิก/ไฟล์
create function private.submission_outcome(p_assignment_id uuid, p_student_id uuid, p_now timestamptz)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_term_id uuid;
  v_due timestamptz;
  v_sub public.submissions;
begin
  select c.term_id, a.due_at into v_term_id, v_due
    from public.assignments a
    join public.posts p on p.id = a.post_id
    join public.classrooms c on c.id = p.classroom_id
   where a.post_id = p_assignment_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.require_current_term(v_term_id);
  select s.* into v_sub from public.submissions s
   where s.assignment_id = p_assignment_id and s.student_id = p_student_id;
  return private.submission_rule(
    v_sub.id is not null,
    v_due,
    p_now,
    private.assignment_intake(p_assignment_id, p_now),
    exists (select 1 from public.solutions s where s.assignment_id = p_assignment_id and s.published_at is not null),
    v_sub.id is not null and private.submission_latest_graded(v_sub.id),
    v_sub.id is not null and exists (select 1 from public.revision_permissions r
                                      where r.submission_id = v_sub.id and r.status = 'open'));
end
$$;

-- ผลตัดสินแบบไม่ raise สำหรับหน้าจอ: { outcome, blocked } — อย่างใดอย่างหนึ่งเป็น null
create function private.submission_verdict(p_assignment_id uuid, p_student_id uuid, p_now timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return jsonb_build_object('outcome', private.submission_outcome(p_assignment_id, p_student_id, p_now), 'blocked', null);
exception
  when sqlstate 'P0001' then
    return jsonb_build_object('outcome', null, 'blocked', sqlerrm);
end
$$;

-- ---------------------------------------------------------------------------
-- 2. ส่งงาน (จาก 0020): ภาคเรียนและการตัดสินผ่านฟังก์ชันร่วม (พฤติกรรมเดิมทุกข้อ — เทสต์ 0020 ผ่านเหมือนเดิม)
-- ---------------------------------------------------------------------------
create or replace function public.submit_assignment(
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
  v_classroom public.classrooms;
  v_assignment public.assignments;
  v_student_id uuid;
  v_sub public.submissions;
  v_perm public.revision_permissions;
  v_count integer;
  v_total bigint;
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
  perform 1 from public.term_control c where c.singleton for share;
  select c.* into v_classroom
    from public.posts p join public.classrooms c on c.id = p.classroom_id
   where p.id = p_assignment_id and p.kind = 'homework';
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  -- สมาชิกขณะนี้ (ถูกเอาออก → not_member) แล้วจึงภาคเรียน (แถว 1: K5 ended หรืองานของภาคเรียนก่อน)
  v_student_id := private.require_member(v_classroom.id);
  perform private.require_current_term(v_classroom.term_id);

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
  -- เวลาตัดสิน: หลังได้ล็อกและตรวจไฟล์แล้ว (ส่วน 5)
  v_now := clock_timestamp();
  v_outcome := private.submission_outcome(p_assignment_id, v_student_id, v_now);

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
    'timing', private.submission_timing(v_sub.first_submitted_at, v_sub.first_after_solution, v_assignment.due_at),
    'first_after_solution', v_sub.first_after_solution,
    'content_revision', v_sub.content_revision,
    'used_permission', v_outcome = 'resubmit_permission',
    'files', private.submission_files_json(v_sub.id));
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. ขอชุดอัปโหลด (จาก 0020): submission ถูกปฏิเสธเมื่อส่งไม่ได้แน่นอน ด้วยรหัสเดียวกับ submit_assignment
-- ---------------------------------------------------------------------------
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
    -- ส่งไม่ได้แน่นอนตอนนี้ (ภาคเรียน, ปิดรับ, เลยกำหนด/ตรวจแล้ว/หลังเฉลยโดยไม่มีสิทธิ์แก้) → รหัสเดียวกับ submit_assignment
    -- ใช้ฟังก์ชันตัดสินตัวเดียวกัน (ไม่บันทึกอะไร) — ไม่ต้องอัปโหลดไฟล์ที่ส่งไม่ได้
    perform private.submission_outcome(v_post.id, v_student_id, clock_timestamp());
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
-- 4. RPC อ่านสถานะ (นักเรียน) — volatile เพื่อให้ PostgREST เรียกผ่าน POST ใน transaction ปกติ
-- ---------------------------------------------------------------------------
-- S03: สถานะงานของฉัน
-- ผล: { assignment_id, classroom_id, server_now, due_at, close_at, intake (open|closed|after_solution),
--       solution_published, permission_open, outcome (ผลถ้าส่งตอนนี้ | null), blocked (รหัสที่ส่งไม่ได้ | null),
--       submission: null | { submission_id, content_revision, first_submitted_at, last_submitted_at,
--                            first_after_solution, timing, files: [{ asset_id, file_name, content_type, size_bytes }] } }
create function public.submission_status(p_assignment_id uuid)
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
revoke all on function public.submission_status(uuid) from public, anon;
grant execute on function public.submission_status(uuid) to authenticated;

-- S02 (ห้องเดียว) / S01 (ทุกห้องที่เป็นสมาชิกขณะนี้ เมื่อ p_classroom_id = null): การบ้านพร้อมสถานะส่วนตัว
-- ผล: [{ post_id, classroom_id, classroom_name, title, due_at, close_at, reward_tokens, submitted, timing,
--        last_submitted_at, content_revision, permission_open, outcome, blocked }] เรียงกำหนดส่งจากเร็วไปช้า
create function public.my_work(p_classroom_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_now timestamptz := clock_timestamp();
  v_rows jsonb := '[]'::jsonb;
  r record;
begin
  perform private.require_student_account();
  if p_classroom_id is not null then
    v_student_id := private.require_member(p_classroom_id);
  else
    v_student_id := private.current_student();
    if v_student_id is null then
      return v_rows;
    end if;
  end if;
  for r in
    select p.id as post_id, p.classroom_id, c.name as classroom_name, p.title, a.due_at, a.close_at, a.reward_tokens,
           s.id as submission_id, s.first_submitted_at, s.first_after_solution, s.last_submitted_at, s.content_revision
      from public.posts p
      join public.assignments a on a.post_id = p.id
      join public.classrooms c on c.id = p.classroom_id
      join public.memberships m on m.classroom_id = c.id and m.student_id = v_student_id
      left join public.submissions s on s.assignment_id = p.id and s.student_id = v_student_id
     where p_classroom_id is null or p.classroom_id = p_classroom_id
     order by a.due_at, p.published_at
  loop
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'post_id', r.post_id,
      'classroom_id', r.classroom_id,
      'classroom_name', r.classroom_name,
      'title', r.title,
      'due_at', r.due_at,
      'close_at', r.close_at,
      'reward_tokens', r.reward_tokens,
      'submitted', r.submission_id is not null,
      'timing', case when r.submission_id is not null
                     then private.submission_timing(r.first_submitted_at, r.first_after_solution, r.due_at) end,
      'last_submitted_at', r.last_submitted_at,
      'content_revision', r.content_revision,
      'permission_open', r.submission_id is not null and exists (select 1 from public.revision_permissions x
                                                                  where x.submission_id = r.submission_id
                                                                    and x.status = 'open'))
      || private.submission_verdict(r.post_id, v_student_id, v_now));
  end loop;
  return v_rows;
end
$$;
revoke all on function public.my_work(uuid) from public, anon;
grant execute on function public.my_work(uuid) to authenticated;
