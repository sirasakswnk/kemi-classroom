-- 0017_upload_complete: ขั้น complete ของการอัปโหลด (POST /uploads/:batch_id/complete) + ตัวนับงบ B2 รายวัน — P3-04
-- TECHNICAL_DESIGN 9 ข้อ 2–4, 9.1, 9.3; TECHNICAL_BUILD_PLAN 5 (uploads)
--
-- แบ่งสิทธิ์เป็นสองชั้น:
--   1. upload_complete_target — เรียกด้วย JWT ของผู้ใช้ (authenticated): ยืนยันว่าเป็นเจ้าของ batch แล้วคืน staging key/ชนิด/ขนาด
--      ที่ประกาศไว้จากแถว batch (หน้าเว็บส่งแค่ batch id + ลำดับไฟล์ ไม่ส่ง key) — อ่านอย่างเดียว ไม่เขียนอะไร
--   2. upload_complete_begin / _finish / _abort และ record_b2_usage — เรียกได้เฉพาะ service_role (Edge Function `uploads`)
--      เพราะเขียนข้อมูลที่ระบบเชื่อ (staging_version_id, version_id ปลายทาง, ขนาด, ETag, ชนิดที่ตรวจแล้ว, สถานะ)
--      ผู้ใช้เรียกผ่าน PostgREST ตรง ๆ ไม่ได้ (function_privileges.test.sql); ฟังก์ชันตรวจเจ้าของ batch ซ้ำจาก p_account_id
--      ที่ Edge Function ได้มาจากข้อ 1 (ไม่ใช่ค่าที่หน้าเว็บส่ง)
-- ลำดับล็อก: upload_batches (FOR UPDATE) → assets — การเรียก complete พร้อมกันของไฟล์เดียวกันจึงรอกันทีละราย
-- และรายที่สองเห็นแถว asset ของรายแรก (staging_key ไม่ซ้ำ) จึงไม่ได้สองแถวและไม่คัดลอกซ้ำ
--
-- รหัสที่หน้าเว็บอาจเจอ (Edge Function ส่งต่อ): upload_expired, upload_not_found, upload_size_mismatch,
-- upload_type_mismatch, upload_in_progress, upload_failed, download_budget_reached, forbidden
-- รหัสภายใน: invalid_request, account_required

-- ---------------------------------------------------------------------------
-- 1. งบดาวน์โหลดรายวัน (TECHNICAL_DESIGN 9.3) — ค่างบอยู่ในแถวตั้งค่าเดียวกับพื้นที่
-- ---------------------------------------------------------------------------
-- ค่าเริ่มต้นเป็น [ข้อเสนอ] ของ 9.3 ข้อ 2 (ปรับหลังวัดจริงที่จุดสาธิต 2 — P3-12); P3-05 ใช้บังคับงบเปิดดู
alter table public.storage_settings
  add column daily_view_budget_bytes bigint not null default 750000000 check (daily_view_budget_bytes > 0),
  add column daily_view_budget_requests integer not null default 1800 check (daily_view_budget_requests > 0);

-- ยอดใช้ต่อรอบวันของ B2 (00:00 UTC = 07:00 น. ไทย) แยกตามแหล่ง: view (เปิดดู P3-05), complete (ขั้นนี้), backup (P3-11)
-- class_b_requests/download_bytes = GET/HEAD ที่นับเพดาน Class B และไบต์ดาวน์โหลด
-- copy_bytes = ขนาดไฟล์ที่ CopyObject (ยังไม่ยืนยันว่า B2 นับเป็นไบต์ดาวน์โหลดหรือไม่ — เก็บแยกไว้เทียบกับหน้า Caps ใน P3-12)
-- เขียนผ่าน private.b2_usage_add() เท่านั้น (ใน RPC ของ service_role และงานสำรองที่ต่อด้วย postgres); ไม่เปิดให้ผู้ใช้อ่าน
create table public.b2_daily_usage (
  day date not null,
  source text not null check (source in ('view', 'complete', 'backup')),
  class_b_requests bigint not null default 0 check (class_b_requests >= 0),
  download_bytes bigint not null default 0 check (download_bytes >= 0),
  copy_bytes bigint not null default 0 check (copy_bytes >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (day, source)
);
alter table public.b2_daily_usage enable row level security;
revoke all on public.b2_daily_usage from anon, authenticated;

create function private.b2_usage_add(p_source text, p_requests integer, p_bytes bigint, p_copy_bytes bigint default 0)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  if p_source is null or p_requests is null or p_bytes is null or p_copy_bytes is null
     or p_requests < 0 or p_bytes < 0 or p_copy_bytes < 0 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  insert into public.b2_daily_usage as u (day, source, class_b_requests, download_bytes, copy_bytes)
  values ((clock_timestamp() at time zone 'UTC')::date, p_source, p_requests, p_bytes, p_copy_bytes)
  on conflict (day, source) do update
    set class_b_requests = u.class_b_requests + excluded.class_b_requests,
        download_bytes = u.download_bytes + excluded.download_bytes,
        copy_bytes = u.copy_bytes + excluded.copy_bytes,
        updated_at = clock_timestamp();
end
$$;

-- ---------------------------------------------------------------------------
-- 2. หนึ่งไฟล์พัก = หนึ่ง asset (กันคัดลอกซ้ำเมื่อเรียก complete พร้อมกัน/ซ้ำ)
-- ---------------------------------------------------------------------------
create unique index assets_staging_key_key on public.assets (staging_key);

-- ---------------------------------------------------------------------------
-- 3. ขั้นที่เรียกด้วย JWT ของผู้ใช้
-- ---------------------------------------------------------------------------
-- p_item = ลำดับไฟล์ใน batch (1..จำนวนไฟล์) ตามที่ create_upload_batch คืน
-- ผล: { account_id, batch_id, item, staging_key, file_name, content_type, size_bytes, asset: { id, status } | null }
create function public.upload_complete_target(p_batch_id uuid, p_item integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account uuid := private.current_account();
  v_batch public.upload_batches;
  v_file jsonb;
  v_asset public.assets;
  v_has_asset boolean;
begin
  if v_account is null then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  select b.* into v_batch from public.upload_batches b where b.id = p_batch_id;
  -- batch ของคนอื่นกับ batch ที่ไม่มี (เช่นหายตามโพสต์ที่ถูกลบ) ตอบเหมือนกัน
  if not found or v_batch.owner_account_id <> v_account then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if p_item is null or p_item < 1 or p_item > jsonb_array_length(v_batch.files) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_file := v_batch.files -> (p_item - 1);
  select a.* into v_asset from public.assets a where a.staging_key = v_file ->> 'staging_key';
  v_has_asset := found;
  -- ไฟล์ที่ complete แล้วตอบผลเดิมได้แม้ batch ปิด/หมดอายุ (เรียกซ้ำหลังเน็ตหลุด)
  if not v_has_asset and (v_batch.status <> 'open' or v_batch.expires_at <= clock_timestamp()) then
    raise exception using errcode = 'P0001', message = 'upload_expired';
  end if;
  return jsonb_build_object(
    'account_id', v_account,
    'batch_id', v_batch.id,
    'item', p_item,
    'staging_key', v_file ->> 'staging_key',
    'file_name', v_file ->> 'file_name',
    'content_type', v_file ->> 'content_type',
    'size_bytes', (v_file ->> 'size_bytes')::bigint,
    'asset', case when v_has_asset then jsonb_build_object('id', v_asset.id, 'status', v_asset.status) end);
end
$$;
grant execute on function public.upload_complete_target(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. ขั้นที่เขียนข้อมูลที่ระบบเชื่อ — service_role เท่านั้น
-- ---------------------------------------------------------------------------
-- หลัง GET แบบ Range 0–15 ครั้งเดียว: นับคำขอ (แม้ผลถูกปฏิเสธ) → ตรวจขนาดเต็ม/ชนิดจาก magic number เทียบที่ประกาศ
-- → สร้าง asset สถานะ copying พร้อม final_key ใหม่ (files/{asset_id}.{ext} — ไม่ผูกกับโพสต์/งานส่งที่อาจยังไม่มี)
-- ผลที่ไม่ผ่านคืนเป็น { code } (ไม่ raise) เพื่อให้ยอดคำขอที่นับไว้ commit ด้วย
-- ผล: { asset_id, final_key, file_name, content_type, size_bytes, status: 'copying' }
--      | { asset_id, status, existing: true } (มี asset ของไฟล์นี้แล้ว) | { code }
create function public.upload_complete_begin(
  p_account_id uuid,
  p_batch_id uuid,
  p_item integer,
  p_staging_version_id text,
  p_total_bytes bigint,
  p_detected_type text,
  p_read_bytes integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.upload_batches;
  v_file jsonb;
  v_asset public.assets;
  v_id uuid := gen_random_uuid();
  v_final_key text;
begin
  if p_account_id is null or p_batch_id is null or p_item is null or p_read_bytes is null
     or p_read_bytes not between 0 and 16 or p_total_bytes is null or p_total_bytes < 0
     or p_staging_version_id is null or p_staging_version_id = '' or length(p_staging_version_id) > 200 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select b.* into v_batch from public.upload_batches b where b.id = p_batch_id for update;
  if not found or v_batch.owner_account_id <> p_account_id then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if p_item < 1 or p_item > jsonb_array_length(v_batch.files) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_file := v_batch.files -> (p_item - 1);

  -- GET ที่ Edge Function ทำไปแล้ว = 1 คำขอ Class B + ไบต์ที่อ่าน
  perform private.b2_usage_add('complete', 1, p_read_bytes);

  select a.* into v_asset from public.assets a where a.staging_key = v_file ->> 'staging_key';
  if found then
    return jsonb_build_object('asset_id', v_asset.id, 'status', v_asset.status, 'existing', true);
  end if;
  if v_batch.status <> 'open' or v_batch.expires_at <= clock_timestamp() then
    return jsonb_build_object('code', 'upload_expired');
  end if;
  if p_total_bytes <> (v_file ->> 'size_bytes')::bigint then
    return jsonb_build_object('code', 'upload_size_mismatch');
  end if;
  if p_detected_type is distinct from v_file ->> 'content_type' then
    return jsonb_build_object('code', 'upload_type_mismatch');
  end if;

  v_final_key := 'files/' || v_id || case v_file ->> 'content_type'
                                         when 'image/jpeg' then '.jpg'
                                         when 'image/png' then '.png'
                                         else '.pdf' end;
  insert into public.assets (id, owner_account_id, purpose, upload_batch_id, staging_key, staging_version_id,
                             final_key, content_type, size_bytes, file_name)
  values (v_id, v_batch.owner_account_id, v_batch.purpose, v_batch.id, v_file ->> 'staging_key', p_staging_version_id,
          v_final_key, v_file ->> 'content_type', p_total_bytes, v_file ->> 'file_name');
  return jsonb_build_object(
    'asset_id', v_id,
    'final_key', v_final_key,
    'file_name', v_file ->> 'file_name',
    'content_type', v_file ->> 'content_type',
    'size_bytes', p_total_bytes,
    'status', 'copying');
end
$$;

-- CopyObject สำเร็จ: บันทึก version_id ปลายทาง + ETag แล้ว copying → ready; เรียกซ้ำด้วยค่าเดิมได้ผลเดิม
-- นับ copy_bytes ของวัน (ดูหมายเหตุตาราง b2_daily_usage)
create function public.upload_complete_finish(p_asset_id uuid, p_version_id text, p_checksum text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asset public.assets;
begin
  if p_asset_id is null or p_version_id is null or p_version_id = '' or length(p_version_id) > 200
     or p_checksum is null or p_checksum !~ '^[0-9A-Za-z_-]{1,128}$' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select a.* into v_asset from public.assets a where a.id = p_asset_id for update;
  -- แถวหายหรือ sweeper ตัดสินไปแล้ว (deleting): ผลการคัดลอกนี้ใช้ไม่ได้
  if not found or v_asset.status = 'deleting'
     or (v_asset.status = 'ready' and (v_asset.version_id <> p_version_id or v_asset.checksum <> p_checksum)) then
    raise exception using errcode = 'P0001', message = 'upload_failed';
  end if;
  if v_asset.status = 'copying' then
    update public.assets
       set version_id = p_version_id, checksum = p_checksum, status = 'ready', ready_at = clock_timestamp()
     where id = p_asset_id;
    perform private.b2_usage_add('complete', 0, 0, v_asset.size_bytes);
  end if;
  return jsonb_build_object(
    'asset_id', v_asset.id,
    'file_name', v_asset.file_name,
    'content_type', v_asset.content_type,
    'size_bytes', v_asset.size_bytes,
    'status', 'ready');
end
$$;

-- CopyObject ถูกปฏิเสธแน่นอน (4xx เช่นเกินเพดาน) ปลายทางจึงไม่มีไฟล์: ลบแถว copying ทิ้งให้ complete ใหม่ได้
-- (ผลไม่แน่นอน เช่น 5xx/หมดเวลา ไม่เรียกฟังก์ชันนี้ — ปล่อยให้ sweeper ใน P3-10 ตรวจปลายทางแล้วตัดสิน)
create function public.upload_complete_abort(p_asset_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.assets a where a.id = p_asset_id and a.status = 'copying';
  return found;
end
$$;

-- นับคำขอ B2 ที่ไม่ผ่านขั้นข้างบน (เช่น GET ได้ 404) — P3-05 เพิ่มฟังก์ชันตรวจ+นับงบเปิดดูแยก
create function public.record_b2_usage(p_source text, p_requests integer, p_bytes bigint, p_copy_bytes bigint default 0)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_source is distinct from 'complete' and p_source is distinct from 'view' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  perform private.b2_usage_add(p_source, p_requests, p_bytes, p_copy_bytes);
end
$$;

revoke all on function public.upload_complete_begin(uuid, uuid, integer, text, bigint, text, integer) from public, anon, authenticated;
revoke all on function public.upload_complete_finish(uuid, text, text) from public, anon, authenticated;
revoke all on function public.upload_complete_abort(uuid) from public, anon, authenticated;
revoke all on function public.record_b2_usage(text, integer, bigint, bigint) from public, anon, authenticated;
grant execute on function public.upload_complete_begin(uuid, uuid, integer, text, bigint, text, integer) to service_role;
grant execute on function public.upload_complete_finish(uuid, text, text) to service_role;
grant execute on function public.upload_complete_abort(uuid) to service_role;
grant execute on function public.record_b2_usage(text, integer, bigint, bigint) to service_role;
