-- 0029_solutions: เตรียม/เผยแพร่/แก้เฉลย (M3) — migration กลุ่ม grading ส่วนที่สี่ (P4-03b)
-- TECHNICAL_DESIGN ส่วน 2 (solutions, attachments), 5 (K4, ช่วงรับหลังเฉลย), 10 (PUT /assignments/:id/solution,
-- /solution/publish); SYSTEM_SPEC K4, E1, N2; UX_DESIGN ส่วน 8 (M3)
-- หลัก:
--   - save_solution: ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแลบันทึกข้อความ + ไฟล์เฉลย (สูงสุด 10 ไฟล์/20 MB) ได้ตลอด
--     ทั้งร่างก่อนปิดรับและการแก้หลังเผยแพร่ (K4: คง published_at, เลื่อน updated_at = "แก้ไขล่าสุด"); ไม่มีอะไรเปลี่ยน
--     = ไม่ขยับ version/updated_at; เฉลยต้องมีข้อความหรือไฟล์อย่างน้อยหนึ่งอย่าง; ไม่แตะสถานะรับงาน เวลาส่ง
--     first_after_solution หรือผลตรวจ
--   - ไฟล์เฉลยตามกติกาเดียวกับไฟล์โจทย์ (0019): asset ต้อง ready, วัตถุประสงค์ solution และ (ผูกกับเฉลยนี้อยู่แล้ว หรือ
--     เป็นของผู้เรียกและยังไม่ผูก); เอาออก = ลบแถวผูก (asset กำพร้าเข้าคิวลบ B2 ตามงานประจำ 0023)
--   - publish_solution: เผยแพร่ครั้งแรกได้เมื่อปิดรับแล้วเท่านั้น (สถานะรับงานไม่ใช่ open — close_required); ตั้ง
--     published_at ครั้งเดียว; ถ้างานตั้งรับหลังเฉลย สถานะรับงานกลายเป็นช่วงรับหลังเฉลยในการเผยแพร่นี้ (assignment_intake)
--     และ "รับงานหลังเฉลย" ล็อก (trigger 0010 — จึงล็อกแถวงาน FOR UPDATE ก่อน); เผยแพร่แล้วกดซ้ำคืนสถานะเดิม
--   - นักเรียนเห็นเฉลย/ไฟล์เฉลยเมื่อเผยแพร่แล้วเท่านั้น (RLS solutions_select 0010, authorize_files 0020 →
--     can_read_solution) — ครูเปิดได้ตลอด
--   - แจ้งเตือน "เผยแพร่เฉลย" ระยะ 6 เติมที่ private.assignment_event (0028)
--
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: close_required (เผยแพร่เฉลยขณะยังเปิดรับ — UX: “ปิดรับงานก่อนเผยแพร่เฉลย”)
-- รหัสเดิมที่ใช้: post_body_required, post_body_too_long, post_file_unavailable, too_many_files, batch_too_large,
--   stale_revision, forbidden, admin_mode_required
-- รหัสภายใน: invalid_request, request_key_required, request_key_conflict

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- ทำให้ไฟล์ของเฉลยตรงกับรายการ (ตามลำดับ) — คืน true ถ้าชุดหรือลำดับเปลี่ยน (แบบเดียวกับ private.post_files_apply)
create function private.solution_files_apply(p_assignment_id uuid, p_ids uuid[], p_account uuid)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_current uuid[];
  v_count integer;
  v_total bigint;
begin
  select coalesce(array_agg(t.asset_id order by t.position), '{}') into v_current
    from public.attachments t where t.solution_id = p_assignment_id;
  if v_current = p_ids then
    return false;
  end if;

  perform 1 from public.assets a where a.id = any(p_ids) order by a.id for update;
  select count(*)::integer, coalesce(sum(a.size_bytes), 0)::bigint into v_count, v_total
    from public.assets a
    left join public.attachments t on t.asset_id = a.id
   where a.id = any(p_ids)
     and a.status = 'ready'
     and a.purpose = 'solution'
     and (t.solution_id = p_assignment_id or (t.id is null and a.owner_account_id = p_account));
  if v_count <> cardinality(p_ids) then
    raise exception using errcode = 'P0001', message = 'post_file_unavailable';
  end if;
  -- J6: รวมต่อชุดเฉลยไม่เกิน 20 MB
  if v_total > (private.upload_limits() ->> 'max_batch_bytes')::bigint then
    raise exception using errcode = 'P0001', message = 'batch_too_large';
  end if;

  set constraints public.attachments_solution_position_key deferred;
  delete from public.attachments t where t.solution_id = p_assignment_id and t.asset_id <> all (p_ids);
  update public.attachments t
     set position = u.n
    from unnest(p_ids) with ordinality u(id, n)
   where t.solution_id = p_assignment_id and t.asset_id = u.id and t.position <> u.n;
  insert into public.attachments (asset_id, solution_id, position)
  select u.id, p_assignment_id, u.n
    from unnest(p_ids) with ordinality u(id, n)
   where not exists (select 1 from public.attachments t where t.asset_id = u.id);

  update public.upload_batches b
     set status = 'consumed'
   where b.status = 'open'
     and b.id in (select a.upload_batch_id from public.assets a where a.id = any(p_ids))
     and jsonb_array_length(b.files) = (select count(*) from public.assets a
                                          join public.attachments t on t.asset_id = a.id
                                         where a.upload_batch_id = b.id);
  return true;
end
$$;

-- ผลของ RPC เฉลย: { assignment_id, body, published_at, updated_at, version, files: [{ asset_id, file_name, content_type,
--   size_bytes }], intake }
create function private.solution_json(p_assignment_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'assignment_id', s.assignment_id,
    'body', s.body,
    'published_at', s.published_at,
    'updated_at', s.updated_at,
    'version', s.version,
    'files', coalesce((
      select jsonb_agg(jsonb_build_object(
               'asset_id', a.id, 'file_name', a.file_name, 'content_type', a.content_type, 'size_bytes', a.size_bytes)
               order by t.position)
        from public.attachments t join public.assets a on a.id = t.asset_id
       where t.solution_id = s.assignment_id), '[]'::jsonb),
    'intake', private.assignment_intake(s.assignment_id, clock_timestamp()))
    from public.solutions s
   where s.assignment_id = p_assignment_id
$$;

-- ---------------------------------------------------------------------------
-- 2. บันทึกเฉลย (PUT /assignments/:id/solution)
-- ---------------------------------------------------------------------------
-- p_files: null = คงชุดเดิม (เฉลยใหม่ = ไม่มีไฟล์), อาร์เรย์ = ชุดใหม่ทั้งชุดตามลำดับ
-- p_expected_version: version ของเฉลยที่หน้าจอเห็น (0 = ยังไม่มีเฉลย)
-- ผล: solution_json + changed
create function public.save_solution(
  p_assignment_id uuid,
  p_body text,
  p_files uuid[],
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
  v_body text;
  v_operation text;
  v_prior jsonb;
  v_solution public.solutions;
  v_files_changed boolean := false;
  v_changed boolean;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null or p_expected_version is null or p_expected_version < 0
     or (p_files is not null and (array_position(p_files, null) is not null
                                  or cardinality(p_files) <> (select count(distinct x) from unnest(p_files) x))) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if cardinality(p_files) > (private.upload_limits() ->> 'max_files')::integer then
    raise exception using errcode = 'P0001', message = 'too_many_files';
  end if;
  v_body := private.trim_text(p_body);
  if length(v_body) > 10000 then
    raise exception using errcode = 'P0001', message = 'post_body_too_long';
  end if;

  v_operation := 'save_solution:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'body', v_body, 'files', to_jsonb(p_files),
    'expected_version', p_expected_version)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  perform private.require_post_teacher(p_assignment_id, p_admin_mode);
  -- งาน (share — ไม่ชนกันเองแต่รอการเผยแพร่ที่ถือ FOR UPDATE) → เฉลย
  perform 1 from public.assignments a where a.post_id = p_assignment_id for share;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  -- advisory lock ครอบกรณียังไม่มีแถว (บันทึกครั้งแรกพร้อมกันสองแท็บ) แล้วล็อกแถว
  perform pg_advisory_xact_lock(hashtextextended('solution:' || p_assignment_id, 0));
  select s.* into v_solution from public.solutions s where s.assignment_id = p_assignment_id for update;
  if coalesce(v_solution.version, 0) <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  if v_solution.assignment_id is null then
    insert into public.solutions (assignment_id, body) values (p_assignment_id, v_body) returning * into v_solution;
  end if;

  if p_files is not null then
    v_files_changed := private.solution_files_apply(p_assignment_id, p_files, v_account.id);
  end if;
  if v_body is null and not exists (select 1 from public.attachments t where t.solution_id = p_assignment_id) then
    raise exception using errcode = 'P0001', message = 'post_body_required';
  end if;

  v_changed := v_files_changed or v_body is distinct from v_solution.body or p_expected_version = 0;
  if v_changed then
    update public.solutions
       set body = v_body,
           updated_at = clock_timestamp(),
           version = case when p_expected_version = 0 then 1 else version + 1 end
     where assignment_id = p_assignment_id;
  end if;

  v_result := private.solution_json(p_assignment_id) || jsonb_build_object('changed', v_changed);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.save_solution(uuid, text, uuid[], integer, uuid, boolean) from public, anon;
grant execute on function public.save_solution(uuid, text, uuid[], integer, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. เผยแพร่เฉลย (POST /assignments/:id/solution/publish)
-- ---------------------------------------------------------------------------
-- ผล: solution_json + already_published
create function public.publish_solution(
  p_assignment_id uuid,
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
  v_solution public.solutions;
  v_now timestamptz;
  v_already boolean := true;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_assignment_id is null or p_expected_version is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'publish_solution:' || md5(jsonb_build_object(
    'assignment_id', p_assignment_id, 'expected_version', p_expected_version)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  perform private.require_post_teacher(p_assignment_id, p_admin_mode);
  -- งาน FOR UPDATE ก่อน: รอการส่ง/ปิดรับ/เปลี่ยนกำหนดที่ถืองานอยู่ และกันการแก้ "รับหลังเฉลย" พร้อมกัน (0010)
  perform 1 from public.assignments a where a.post_id = p_assignment_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select s.* into v_solution from public.solutions s where s.assignment_id = p_assignment_id for update;

  if v_solution.published_at is null then
    if v_solution.assignment_id is null or v_solution.version <> p_expected_version then
      raise exception using errcode = 'P0001', message = 'stale_revision';
    end if;
    if v_solution.body is null
       and not exists (select 1 from public.attachments t where t.solution_id = p_assignment_id) then
      raise exception using errcode = 'P0001', message = 'post_body_required';
    end if;
    v_now := clock_timestamp();
    if private.assignment_intake(p_assignment_id, v_now) = 'open' then
      raise exception using errcode = 'P0001', message = 'close_required';
    end if;
    -- updated_at = published_at: ยังไม่ถือว่า "แก้ไขหลังเผยแพร่"
    update public.solutions
       set published_at = v_now, updated_at = v_now, version = version + 1
     where assignment_id = p_assignment_id;
    perform private.assignment_event(p_assignment_id, 'solution_published', '{}'::jsonb);
    v_already := false;
  end if;

  v_result := private.solution_json(p_assignment_id) || jsonb_build_object('already_published', v_already);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.publish_solution(uuid, integer, uuid, boolean) from public, anon;
grant execute on function public.publish_solution(uuid, integer, uuid, boolean) to authenticated;
