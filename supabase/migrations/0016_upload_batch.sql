-- 0016_upload_batch: ขอชุดอัปโหลด (ขั้นแรกของ POST /uploads) — P3-03
-- TECHNICAL_DESIGN ส่วน 9 (staging + จองพื้นที่ J10.2), 9.2, 10; SYSTEM_SPEC J4–J6, K5; TECHNICAL_BUILD_PLAN 5 (uploads)
-- create_upload_batch(p_purpose, p_classroom_id, p_post_id, p_files jsonb, p_request_key, p_admin_mode)
--   Edge Function `uploads` เรียกด้วย JWT ของผู้ใช้ แล้วลงลายเซ็น PUT ต่อไฟล์ให้ key ที่ได้จากที่นี่ (ฟังก์ชันไม่ตัดสินสิทธิ์เอง)
--   วัตถุประสงค์ตอนนี้: post (ไฟล์โจทย์/ไฟล์แนบประกาศ) และ solution (ไฟล์เฉลย) — ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล;
--   submission มากับ P3-07 (รวมกติกา K5 ของนักเรียน: ภาคเรียน ended ปฏิเสธการอัปโหลด) และ charm มากับระยะ 5
--   p_files = [{file_name, content_type, size_bytes}] 1–10 ไฟล์ · JPEG/PNG ≤ 2 MiB, PDF ≤ 10 MiB, รวม ≤ 20 MiB (J4–J6)
--   ทุกอย่างใน transaction เดียว: ตรวจ → นับเพดานครั้ง → จองพื้นที่ (ล็อก storage_settings) → สร้าง batch + staging key ต่อไฟล์
--   กดซ้ำด้วย request key เดิมได้ batch เดิม (ฟังก์ชันลงลายเซ็นใหม่ให้ key เดิม)

-- รหัสที่หน้าเว็บอาจเจอ: storage_full, rate_limited, term_ended, forbidden, admin_mode_required, too_many_files,
-- file_too_large, file_type_not_allowed, batch_too_large (หน้าเว็บตรวจกติกาเดียวกันก่อนส่ง รหัสเหล่านี้เป็นด่านหลัง)
-- รหัสภายใน: invalid_request, request_key_required, request_key_conflict
-- ผล: { batch_id, purpose, expires_at, reserved_bytes, files: [{ staging_key, file_name, content_type, size_bytes }] }

-- เพดานไฟล์ (ไบต์แบบ MiB ตามที่ระบบปฏิบัติการแสดง — หน้าเว็บใช้ค่าเดียวกัน)
create function private.upload_limits()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'max_files', 10,
    'max_image_bytes', 2097152,     -- รูปหลังย่อไม่เกิน 2 MB (J5)
    'max_pdf_bytes', 10485760,      -- PDF ไม่เกิน 10 MB (J4/J5)
    'max_batch_bytes', 20971520,    -- รวมต่อชุดไม่เกิน 20 MB (J6: โจทย์และเฉลยนับแยกชุด)
    'batch_ttl_minutes', 120,       -- จองพื้นที่ไว้ 2 ชม. (อัปโหลด + complete) แล้วปล่อยเอง
    'rate_limit', 30,               -- ขอ batch ได้ 30 ครั้งต่อ 10 นาทีต่อบัญชี
    'rate_window_minutes', 10)
$$;

create function public.create_upload_batch(
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
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  -- submission (P3-07) และ charm (ระยะ 5) ยังไม่เปิด
  if p_purpose is null or p_purpose not in ('post', 'solution') or p_classroom_id is null
     or (p_purpose = 'solution' and p_post_id is null)
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
  select c.term_id into v_term_id from public.term_control c where c.singleton for share;
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

  perform private.rate_limit_hit(v_account.id, 'upload_batch', (v_limits ->> 'rate_limit')::integer,
                                 make_interval(mins => (v_limits ->> 'rate_window_minutes')::integer));
  -- จองพื้นที่ (ล็อกแถว storage_settings จน commit) แล้วสร้าง batch ใน transaction เดียวกัน
  perform private.reserve_storage(v_total);
  v_expires := clock_timestamp() + make_interval(mins => (v_limits ->> 'batch_ttl_minutes')::integer);
  insert into public.upload_batches (id, owner_account_id, purpose, classroom_id, post_id, base_version, files,
                                     reserved_bytes, expires_at)
  values (v_batch_id, v_account.id, p_purpose, v_classroom.id, p_post_id, v_post.version, v_specs, v_total, v_expires);

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
grant execute on function public.create_upload_batch(text, uuid, uuid, jsonb, uuid, boolean) to authenticated;
