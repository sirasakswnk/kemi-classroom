-- 0040_charm_admin: T06 จัดการเครื่องราง (UX 11, TECHNICAL_DESIGN ส่วน 8) — รูป ชื่อ คำอธิบาย ระดับ และอัตราสุ่ม
-- รูปเครื่องรางเป็น attachments เป้าหมายที่สี่ (charm_id ตามที่ 0020 เว้นไว้) — ตัวกวาดไฟล์กำพร้า การนับพื้นที่
-- และงานลบไฟล์ใช้กติกาเดียวกับไฟล์อื่น · แก้ชื่อ/รูป/ระดับคงรหัสเดิม (ไม่กลายเป็นของใหม่ให้สุ่มซ้ำ) · ไม่มีคำสั่งลบเครื่องราง

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
-- รุ่นของแถวเครื่องราง: บันทึกจากสองหน้าจอพร้อมกัน → stale_revision
alter table public.charms add column version integer not null default 1 check (version >= 1);

alter table public.attachments
  add column charm_id uuid references public.charms (id),
  drop constraint attachments_one_target,
  add constraint attachments_one_target check (num_nonnulls(post_id, solution_id, submission_id, charm_id) = 1),
  -- รูปละหนึ่งไฟล์ต่อชิ้น
  add constraint attachments_charm_id_key unique (charm_id),
  add constraint attachments_charm_position check (charm_id is null or position = 1);

create or replace function private.charms_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.created_at <> old.created_at or new.version < old.version then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

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
       or new.charm_id is distinct from old.charm_id or new.created_at <> old.created_at then
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
                    when new.submission_id is not null then 'submission'
                    when new.charm_id is not null then 'charm' end;
  if v_purpose is not null and v_asset.purpose <> v_purpose then
    raise exception using errcode = 'P0001', message = 'attachment_purpose_mismatch';
  end if;
  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. ขอชุดอัปโหลด (create_upload_batch จาก 0021 + purpose charm)
-- ---------------------------------------------------------------------------
-- charm: ครู/ผู้ดูแลในโหมดผู้ดูแล, ไม่มีห้อง/โพสต์, 1 ไฟล์ รูป JPG/PNG เท่านั้น (PDF = file_type_not_allowed)
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
  -- charm (0040): รูปเครื่องรางไม่มีห้อง/โพสต์ (ใช้ร่วมทุกห้อง) — ครู/ผู้ดูแลในโหมดผู้ดูแล
  if p_purpose is null or p_purpose not in ('post', 'solution', 'submission', 'charm')
     or (p_purpose = 'charm') <> (p_classroom_id is null)
     or (p_purpose = 'charm' and p_post_id is not null)
     or (p_purpose in ('solution', 'submission') and p_post_id is null)
     or jsonb_typeof(p_files) is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- รายการไฟล์ (J4–J6)
  v_count := jsonb_array_length(p_files);
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if v_count > (case when p_purpose = 'charm' then 1 else (v_limits ->> 'max_files')::integer end) then
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
    if v_type is null or v_type not in ('image/jpeg', 'image/png', 'application/pdf')
       or (p_purpose = 'charm' and v_type = 'application/pdf') then
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
  if p_purpose = 'charm' then
    -- แคตตาล็อกใช้ร่วมทุกห้อง ไม่ผูกภาคเรียน (แก้รูปหลังจบภาคเรียนได้)
    v_base := null;
  elsif p_purpose = 'submission' then
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
-- 3. ใครขอลิงก์รูปเครื่องรางได้ (ผู้ใช้กำหนด 24 ต.ค. 2026)
-- ---------------------------------------------------------------------------
-- ครู/ผู้ดูแล: ทุกชิ้น · นักเรียน: ชิ้นที่ตัวเองมี หรือชิ้นที่สมาชิกห้องเดียวกันเลือกแสดงข้างชื่อ
create function private.can_view_charm(p_charm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_teacher_or_admin()
      or exists (select 1 from public.owned_charms o
                  where o.charm_id = p_charm_id and o.student_id = private.current_student())
      or exists (select 1
                   from public.student_equipment e
                   join public.memberships theirs on theirs.student_id = e.student_id
                   join public.memberships mine on mine.classroom_id = theirs.classroom_id
                  where e.charm_id = p_charm_id and mine.student_id = private.current_student())
$$;
revoke all on function private.can_view_charm(uuid) from public, anon;

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
             when t.charm_id is not null then private.can_view_charm(t.charm_id)
             else false
           end), '{}'::uuid[]);
end
$$;

-- ---------------------------------------------------------------------------
-- 4. ตัวช่วย
-- ---------------------------------------------------------------------------
-- รูปที่ผูกกับเครื่องราง (null = รูปวาดชั่วคราว)
create function private.charm_image(p_charm_id uuid)
returns uuid
language sql
stable
set search_path = ''
as $$
  select t.asset_id from public.attachments t join public.assets a on a.id = t.asset_id
   where t.charm_id = p_charm_id and a.status = 'ready'
$$;

-- รุ่นของอัตราทั้งชุด (บันทึกจากสองหน้าจอพร้อมกัน → stale_revision)
create function private.rarity_weights_key()
returns text
language sql
stable
set search_path = ''
as $$
  select md5(coalesce(string_agg(r.id || ':' || r.weight, ',' order by r.id), '')) from public.rarities r
$$;

-- แถวเครื่องรางสำหรับ T06: owners = จำนวนนักเรียนที่มีชิ้นนี้ (ครูเห็นว่าแก้แล้วกระทบใคร)
create function private.charm_admin_json(p_charm_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'id', c.id, 'name', c.name, 'description', c.description, 'symbol', c.symbol,
           'rarity_id', c.rarity_id, 'position', c.position, 'version', c.version,
           'image_asset_id', private.charm_image(c.id),
           'owners', (select count(*) from public.owned_charms o where o.charm_id = c.id)::integer)
    from public.charms c where c.id = p_charm_id
$$;

-- ---------------------------------------------------------------------------
-- 5. T06 อ่านแคตตาล็อก — ครู/ผู้ดูแลในโหมดผู้ดูแล
-- ---------------------------------------------------------------------------
-- ผล: { weights_key, rarities: [{ id, name, weight, count }], charms: [charm_admin_json ตาม position] }
create function public.charm_catalog(p_admin_mode boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_teacher(p_admin_mode);
  return jsonb_build_object(
    'weights_key', private.rarity_weights_key(),
    'rarities', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'name', r.name, 'weight', r.weight,
               'count', (select count(*) from public.charms c where c.rarity_id = r.id)::integer) order by r.id)
        from public.rarities r), '[]'::jsonb),
    'charms', coalesce((
      select jsonb_agg(private.charm_admin_json(c.id) order by c.position) from public.charms c), '[]'::jsonb));
end
$$;
revoke all on function public.charm_catalog(boolean) from public, anon;
grant execute on function public.charm_catalog(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. T06 บันทึกอัตราตามระดับ — รวมต้องเท่ากับ 100 (rates_must_total_100, UX 7.1)
-- ---------------------------------------------------------------------------
-- p_weights = [{ rarity_id, weight }] ครบทุกระดับ น้ำหนัก 0–100 · p_expected_key = weights_key ที่หน้าจอโหลดมา
-- ตั้งค่าซ้ำได้ผลเดิม จึงไม่ใช้ request key · ผล: { weights_key, rarities }
create function public.save_rarity_weights(p_weights jsonb, p_expected_key text, p_admin_mode boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_input jsonb;
  v_sum integer;
begin
  perform private.require_teacher(p_admin_mode);
  if jsonb_typeof(p_weights) is distinct from 'array' or p_expected_key is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select jsonb_agg(jsonb_build_object('id', private.jsonb_int(x -> 'rarity_id'), 'weight', private.jsonb_int(x -> 'weight')))
    into v_input
    from jsonb_array_elements(p_weights) x
   where jsonb_typeof(x) = 'object'
     and not exists (select 1 from jsonb_object_keys(x) k where k not in ('rarity_id', 'weight'));
  -- ครบทุกระดับ ไม่ซ้ำ น้ำหนักเป็นจำนวนเต็ม 0–100
  if v_input is null or jsonb_array_length(v_input) <> jsonb_array_length(p_weights)
     or (select count(*) from public.rarities) <> jsonb_array_length(v_input)
     or exists (select 1 from jsonb_array_elements(v_input) x
                 where (x ->> 'weight') is null or (x ->> 'weight')::integer not between 0 and 100
                    or not exists (select 1 from public.rarities r where r.id = (x ->> 'id')::integer))
     or (select count(distinct x ->> 'id') from jsonb_array_elements(v_input) x) <> jsonb_array_length(v_input) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select sum((x ->> 'weight')::integer) into v_sum from jsonb_array_elements(v_input) x;
  if v_sum <> 100 then
    raise exception using errcode = 'P0001', message = 'rates_must_total_100';
  end if;

  perform 1 from public.rarities r order by r.id for update;
  if private.rarity_weights_key() <> p_expected_key then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  update public.rarities r
     set weight = (x ->> 'weight')::integer
    from jsonb_array_elements(v_input) x
   where r.id = (x ->> 'id')::integer and r.weight <> (x ->> 'weight')::integer;
  return public.charm_catalog(p_admin_mode) - 'charms';
end
$$;
revoke all on function public.save_rarity_weights(jsonb, text, boolean) from public, anon;
grant execute on function public.save_rarity_weights(jsonb, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. T06 เพิ่ม/แก้เครื่องราง
-- ---------------------------------------------------------------------------
-- p_charm = { id?, name, description, rarity_id, symbol?, image_asset_id? }
--   id ไม่มี = เพิ่มใหม่ (ต่อท้ายรายการ, p_expected_version = 0) · มี = แก้ (p_expected_version = version ที่โหลดมา)
--   name 1–40 ตัว · description ≤ 120 ตัว · rarity_id 1–4 · symbol (รูปวาดชั่วคราว) 1–8 ตัว ไม่ส่ง = ตัวแรกของชื่อ/ของเดิม
--   image_asset_id ไม่ส่ง = คงรูปเดิม · null = กลับไปใช้รูปวาด · uuid = รูปที่อัปโหลดเสร็จแล้ว (purpose charm ของผู้เรียก ยังไม่ผูก)
-- รูปเดิมที่ถูกแทน/เอาออก: เลิกผูก → deleting → งานลบ B2 แบบระบุ version_id · ผล: charm_admin_json
create function public.save_charm(
  p_charm jsonb,
  p_expected_version integer,
  p_request_key uuid,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_id uuid;
  v_name text;
  v_desc text;
  v_rarity integer;
  v_symbol text;
  v_set_image boolean;
  v_image uuid;
  v_old_image uuid;
  v_charm public.charms;
  v_asset public.assets;
  v_operation text;
  v_prior jsonb;
  v_result jsonb;
  v_now timestamptz;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if jsonb_typeof(p_charm) is distinct from 'object' or p_expected_version is null
     or exists (select 1 from jsonb_object_keys(p_charm) k
                 where k not in ('id', 'name', 'description', 'rarity_id', 'symbol', 'image_asset_id')) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if p_charm ? 'id' then
    if jsonb_typeof(p_charm -> 'id') <> 'string'
       or (p_charm ->> 'id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    v_id := (p_charm ->> 'id')::uuid;
  end if;
  v_name := private.trim_text(case when jsonb_typeof(p_charm -> 'name') = 'string' then p_charm ->> 'name' end);
  v_desc := coalesce(private.trim_text(case when jsonb_typeof(p_charm -> 'description') = 'string'
                                            then p_charm ->> 'description' end), '');
  v_rarity := private.jsonb_int(p_charm -> 'rarity_id');
  if v_name is null or length(v_name) > 40 or length(v_desc) > 120
     or (p_charm ? 'description' and jsonb_typeof(p_charm -> 'description') <> 'string')
     or v_rarity is null or not exists (select 1 from public.rarities r where r.id = v_rarity) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if p_charm ? 'symbol' then
    v_symbol := private.trim_text(case when jsonb_typeof(p_charm -> 'symbol') = 'string' then p_charm ->> 'symbol' end);
    if v_symbol is null or length(v_symbol) > 8 then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
  end if;
  v_set_image := p_charm ? 'image_asset_id';
  if v_set_image and jsonb_typeof(p_charm -> 'image_asset_id') <> 'null' then
    if jsonb_typeof(p_charm -> 'image_asset_id') <> 'string'
       or (p_charm ->> 'image_asset_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    v_image := (p_charm ->> 'image_asset_id')::uuid;
  end if;
  if (v_id is null) <> (p_expected_version = 0) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- กดซ้ำด้วย request key เดิม → ผลเดิม (เพิ่มใหม่ไม่ได้สองชิ้น)
  v_operation := 'save_charm:' || md5(jsonb_build_object('charm', p_charm, 'expected', p_expected_version)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  v_now := clock_timestamp();
  if v_id is null then
    -- ต่อท้ายรายการ: ล็อกลำดับกันเพิ่มพร้อมกันได้ position ซ้ำ
    perform pg_advisory_xact_lock(hashtextextended('charms:position', 0));
    insert into public.charms (rarity_id, name, description, symbol, position, created_at, updated_at)
    select v_rarity, v_name, v_desc, coalesce(v_symbol, left(v_name, 1)), coalesce(max(c.position), 0) + 1, v_now, v_now
      from public.charms c
    returning * into v_charm;
  else
    select c.* into v_charm from public.charms c where c.id = v_id for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    if v_charm.version <> p_expected_version then
      raise exception using errcode = 'P0001', message = 'stale_revision';
    end if;
    update public.charms c
       set name = v_name, description = v_desc, rarity_id = v_rarity, symbol = coalesce(v_symbol, c.symbol),
           version = c.version + 1, updated_at = v_now
     where c.id = v_id
    returning * into v_charm;
  end if;

  if v_set_image then
    select t.asset_id into v_old_image from public.attachments t where t.charm_id = v_charm.id;
    if v_image is distinct from v_old_image then
      if v_old_image is not null then
        delete from public.attachments t where t.charm_id = v_charm.id;
        update public.assets a
           set status = 'deleting', delete_requested_at = v_now
         where a.id = v_old_image
        returning a.* into v_asset;
        perform private.enqueue_delete_asset(v_asset, 'replaced');
      end if;
      if v_image is not null then
        select a.* into v_asset from public.assets a where a.id = v_image for update;
        if not found or v_asset.status <> 'ready' or v_asset.purpose <> 'charm'
           or v_asset.owner_account_id <> v_account.id
           or exists (select 1 from public.attachments t where t.asset_id = v_image) then
          raise exception using errcode = 'P0001', message = 'invalid_request';
        end if;
        insert into public.attachments (asset_id, charm_id, position) values (v_image, v_charm.id, 1);
        update public.upload_batches b set status = 'consumed'
         where b.id = v_asset.upload_batch_id and b.status = 'open';
      end if;
    end if;
  end if;

  v_result := private.charm_admin_json(v_charm.id);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.save_charm(jsonb, integer, uuid, boolean) from public, anon;
grant execute on function public.save_charm(jsonb, integer, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. รูปในผลของนักเรียน: my_collection (ชิ้นที่มี) และ classroom_view (ชิ้นที่สมาชิกเลือกแสดง) + image_asset_id
-- ---------------------------------------------------------------------------
create or replace function public.my_collection()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  v_student_id := private.require_current_student();
  return (
    select jsonb_build_object(
             'total', count(*)::integer,
             'owned', count(o.charm_id)::integer,
             'equipped_charm_id', (select e.charm_id from public.student_equipment e where e.student_id = v_student_id),
             'items', coalesce(jsonb_agg(
               case when o.charm_id is null then
                 jsonb_build_object('position', c.position, 'rarity_id', c.rarity_id, 'rarity_name', r.name,
                                    'owned', false)
               else
                 jsonb_build_object('position', c.position, 'rarity_id', c.rarity_id, 'rarity_name', r.name,
                                    'owned', true, 'charm_id', c.id, 'name', c.name, 'description', c.description,
                                    'symbol', c.symbol, 'obtained_at', o.obtained_at,
                                    'image_asset_id', private.charm_image(c.id))
               end order by c.position), '[]'::jsonb))
      from public.charms c
      join public.rarities r on r.id = c.rarity_id
      left join public.owned_charms o on o.charm_id = c.id and o.student_id = v_student_id
  );
end
$$;

create or replace function public.classroom_view(p_classroom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  perform private.require_student_account();
  v_student_id := private.require_member(p_classroom_id);
  return (
    select jsonb_build_object(
             'id', c.id,
             'name', c.name,
             'description', c.description,
             'teacher_name', t.display_name,
             'term_name', tm.name,
             'member_count', (select count(*) from public.memberships x where x.classroom_id = c.id),
             'members', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'display_name', s.display_name,
                        'roll_number', e.roll_number,
                        'is_me', s.id = v_student_id,
                        'charm', case when ch.id is null then null
                                      else jsonb_build_object('name', ch.name, 'symbol', ch.symbol,
                                                              'rarity_id', ch.rarity_id,
                                                              'image_asset_id', private.charm_image(ch.id)) end
                      ) order by e.roll_number nulls last, s.display_name)
                 from public.memberships m
                 join public.students s on s.id = m.student_id
                 left join public.roster_entries e on e.student_id = s.id and e.term_id = c.term_id
                 left join public.student_equipment eq on eq.student_id = s.id
                 left join public.charms ch on ch.id = eq.charm_id
                where m.classroom_id = c.id
             ), '[]'::jsonb))
      from public.classrooms c
      join public.teachers t on t.id = c.teacher_id
      join public.terms tm on tm.id = c.term_id
     where c.id = p_classroom_id
  );
end
$$;
