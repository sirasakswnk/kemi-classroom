-- 0011_files: ไฟล์ใน B2 (assets) การผูกไฟล์กับโจทย์/เฉลย (attachments) ชุดอัปโหลด (upload_batches) และเพดานพื้นที่
-- (storage_settings) — migration กลุ่ม posts_files ส่วนที่สอง (P3-01b)
-- TECHNICAL_DESIGN ส่วน 2, 9, 9.1, 12 (J10); TECHNICAL_BUILD_PLAN 3, 4.2 แถว 6b
-- หลัก:
--   - assets = วัตถุใน B2 หนึ่งชิ้น (final_key + version_id) แถวอยู่จนกว่าจะลบจาก B2 สำเร็จ ยอดพื้นที่จึงนับจากแถวเหล่านี้ได้ตรง
--   - attachments = การผูก asset กับเป้าหมายหนึ่งอย่าง ตอนนี้ post / solution (submission, charm เพิ่มคอลัมน์ + FK ใน
--     migration กลุ่มนั้น); ลบโพสต์/เฉลยแล้วแถวผูกหายตาม แต่ asset อยู่ต่อและยังนับพื้นที่ จนคำสั่งลบเปลี่ยนเป็น deleting
--     แล้วเข้าคิวลบ B2 แบบระบุ version_id (ส่วน 9) — ไม่มี cascade ใดลบแถว asset
--   - เขียนผ่าน RPC/Edge Function เท่านั้น: authenticated ได้แค่ SELECT ตาม RLS (assets ไม่เปิดคอลัมน์ key/version/checksum)
--   - จองพื้นที่: private.reserve_storage() ล็อกแถว storage_settings ก่อนนับ (create_upload_batch ใน P3-03 เรียกแล้วสร้าง batch
--     ใน transaction เดียวกัน)

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
-- ค่าตั้งพื้นที่ (แถวเดียว) — ค่าที่ใส่ที่นี่เป็นค่าฝั่ง kemi-dev (BUILD_PLAN ส่วน 3): bucket dev ใช้ 10 GB ก้อนเดียวกับ prod
-- จึงกันไว้ 500 MB; ค่า prod ตั้งตอนระยะ 7 (ลืมแก้แล้วหยุดรับเร็ว ดีกว่าเกินเพดานบัญชี)
create table public.storage_settings (
  singleton boolean primary key default true check (singleton),
  -- ไบต์แบบที่ B2 คิด (1 GB = 1,000,000,000 ไบต์)
  quota_bytes bigint not null check (quota_bytes > 0),
  -- หยุดรับอัปโหลดใหม่เมื่อยอด + ที่ขอ เกิน quota_bytes − hard_stop_margin_bytes (J10.2)
  hard_stop_margin_bytes bigint not null check (hard_stop_margin_bytes >= 0),
  admin_warn_pct integer not null default 80 check (admin_warn_pct between 1 and 100),
  teacher_warn_pct integer not null default 90 check (teacher_warn_pct between 1 and 100),
  updated_at timestamptz not null default clock_timestamp(),
  check (hard_stop_margin_bytes < quota_bytes),
  check (admin_warn_pct <= teacher_warn_pct)
);
insert into public.storage_settings (quota_bytes, hard_stop_margin_bytes) values (500000000, 50000000);

-- ชุดอัปโหลด: ออกลายเซ็น PUT ใต้ staging/{batch_id}/ ต่อไฟล์ (P3-03) — ไม่ใช่ร่างงานสำหรับเปิดย้อนหลัง
-- พื้นที่ที่จองนับเฉพาะ batch ที่ยัง open และยังไม่หมดอายุ (ยกเลิก/ใช้แล้ว/หมดอายุ = ปล่อยพื้นที่)
create table public.upload_batches (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.accounts (id),
  purpose text not null check (purpose in ('post', 'solution', 'submission', 'charm')),
  -- ห้องของไฟล์ (โพสต์ใหม่ยังไม่มี post_id) และโพสต์/งานที่แก้หรือส่ง; รูปเครื่องรางไม่มีห้อง
  classroom_id uuid references public.classrooms (id),
  post_id uuid references public.posts (id) on delete cascade,
  -- รุ่นข้อมูลที่เริ่มแก้ (version ของโพสต์/เฉลย หรือ content_revision ของงานส่ง) ใช้ตอบ conflict ตอนบันทึก
  base_version integer,
  -- ไฟล์ที่ลงลายเซ็นแล้ว [{staging_key, size_bytes, content_type, file_name}] — create_upload_batch (P3-03) ใส่
  files jsonb not null default '[]'::jsonb check (jsonb_typeof(files) = 'array'),
  -- ผลรวมขนาดที่ประกาศตอนขอ batch (J10.2)
  reserved_bytes bigint not null check (reserved_bytes >= 0),
  status text not null default 'open' check (status in ('open', 'consumed', 'cancelled')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (expires_at > created_at),
  check ((purpose = 'charm') = (classroom_id is null)),
  check (purpose not in ('solution', 'submission') or post_id is not null)
);
create index upload_batches_owner_account_id_idx on public.upload_batches (owner_account_id);
create index upload_batches_classroom_id_idx on public.upload_batches (classroom_id);
create index upload_batches_post_id_idx on public.upload_batches (post_id);

-- วัตถุใน B2: แถวเกิดตอน complete (copying) → ready หลังคัดลอกสำเร็จ → deleting เมื่อเข้าคิวลบ → ลบแถวเมื่อลบจาก B2 สำเร็จ
create table public.assets (
  id uuid primary key default gen_random_uuid(),
  -- ผู้อัปโหลด (นักเรียนเจ้าของงานส่ง หรือครู/ผู้ดูแลที่แนบโจทย์/เฉลย/รูปเครื่องราง)
  owner_account_id uuid not null references public.accounts (id),
  purpose text not null check (purpose in ('post', 'solution', 'submission', 'charm')),
  -- batch ที่ไฟล์มาจาก (batch ถูกล้างภายหลังได้ ไฟล์อยู่ต่อ)
  upload_batch_id uuid references public.upload_batches (id) on delete set null,
  staging_key text not null check (staging_key like 'staging/%'),
  -- จำตั้งแต่ HEAD แรกตอน complete แล้วทุกขั้นอ้างเวอร์ชันนี้ (ส่วน 9 ข้อ 2)
  staging_version_id text not null check (staging_version_id <> ''),
  -- ตำแหน่งที่ไม่เคยออกลิงก์เขียนให้ใคร; key สุ่มใหม่ทุกครั้งไม่เขียนทับ
  final_key text not null unique check (final_key like 'files/%'),
  -- version_id ปลายทางจาก CopyObject และ ETag — ตั้งได้ระหว่าง copying เท่านั้น
  version_id text check (version_id <> ''),
  checksum text check (checksum <> ''),
  -- ชนิดที่เซิร์ฟเวอร์ตรวจจาก magic number แล้ว (ไม่รับ HEIC ดิบ — J4)
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'application/pdf')),
  -- เพดาน 20 MiB เป็นตัวกันค่าผิดพลาด เพดานจริงต่อชนิด/ชุด (J4–J6) ตรวจตอนขอ batch
  size_bytes bigint not null check (size_bytes between 1 and 20971520),
  -- ชื่อที่แสดงและใช้ตอนดาวน์โหลด (รูปที่แปลงเป็น JPEG เปลี่ยนนามสกุลแล้ว)
  file_name text not null check (length(file_name) between 1 and 255),
  status text not null default 'copying' check (status in ('copying', 'ready', 'deleting')),
  created_at timestamptz not null default clock_timestamp(),
  ready_at timestamptz,
  delete_requested_at timestamptz,
  -- ลบจาก B2 ต้องระบุเวอร์ชัน: พ้น copying แล้วต้องมี version_id; พร้อมใช้ต้องมี checksum
  check (status = 'copying' or version_id is not null),
  check (status <> 'ready' or (checksum is not null and ready_at is not null)),
  check (status <> 'deleting' or delete_requested_at is not null)
);
create index assets_owner_account_id_idx on public.assets (owner_account_id);
create index assets_upload_batch_id_idx on public.assets (upload_batch_id);

-- การผูกไฟล์กับเป้าหมายเดียว เรียงตามลำดับที่แนบ (โจทย์ 10 / เฉลย 10 ไฟล์ — SYSTEM_SPEC ส่วน 3)
-- ลำดับไม่ซ้ำในเป้าหมายเดียวกัน (deferrable: RPC สลับลำดับได้ด้วย set constraints … deferred)
create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  -- หนึ่ง asset ผูกได้ที่เดียว; ลบ asset ที่ยังผูกอยู่ไม่ได้ (RESTRICT)
  asset_id uuid not null unique references public.assets (id),
  post_id uuid references public.posts (id) on delete cascade,
  solution_id uuid references public.solutions (assignment_id) on delete cascade,
  position integer not null check (position between 1 and 10),
  created_at timestamptz not null default clock_timestamp(),
  constraint attachments_one_target check (num_nonnulls(post_id, solution_id) = 1),
  constraint attachments_post_position_key unique (post_id, position) deferrable initially immediate,
  constraint attachments_solution_position_key unique (solution_id, position) deferrable initially immediate
);

alter table public.storage_settings enable row level security;
alter table public.upload_batches enable row level security;
alter table public.assets enable row level security;
alter table public.attachments enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ตัวกันสถานะและช่องที่แก้ไม่ได้ — trigger ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
-- รหัสภายใน (หน้าเว็บไม่ควรเจอ): immutable_field, invalid_status_transition, asset_attached, asset_not_deletable,
-- asset_not_ready, attachment_purpose_mismatch, batch_mismatch
-- กู้คืน (ส่วน 12) ที่ต้องเขียน version_id ใหม่ทำใน Supabase ชั่วคราวด้วย session_replication_role = replica
create function private.assets_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_batch public.upload_batches;
begin
  if tg_op = 'INSERT' then
    -- ทุกไฟล์เริ่มที่ขั้น complete (copying) — ไม่มีทางลัดเป็น ready
    if new.status <> 'copying' then
      raise exception using errcode = 'P0001', message = 'invalid_status_transition';
    end if;
    if new.upload_batch_id is not null then
      select b.* into v_batch from public.upload_batches b where b.id = new.upload_batch_id;
      if found and (v_batch.owner_account_id <> new.owner_account_id or v_batch.purpose <> new.purpose) then
        raise exception using errcode = 'P0001', message = 'batch_mismatch';
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- ลบแถวได้เมื่อไม่มีไฟล์ใน B2 แล้วเท่านั้น: deleting ที่ลบจาก B2 สำเร็จ หรือ copying ที่ sweeper ยืนยันว่าปลายทางไม่มีไฟล์
    -- (แถว ready ต้องผ่าน deleting ก่อน ไม่งั้นไฟล์ค้างใน B2 โดยไม่ถูกนับ)
    if old.status = 'ready' then
      raise exception using errcode = 'P0001', message = 'asset_not_deletable';
    end if;
    return old;
  end if;

  if new.id <> old.id or new.owner_account_id <> old.owner_account_id or new.purpose <> old.purpose
     or new.staging_key <> old.staging_key or new.staging_version_id <> old.staging_version_id
     or new.final_key <> old.final_key or new.content_type <> old.content_type
     or new.size_bytes <> old.size_bytes or new.file_name <> old.file_name or new.created_at <> old.created_at
     -- batch เปลี่ยนได้ทางเดียวคือเป็น null (FK on delete set null ตอนล้าง batch)
     or (new.upload_batch_id is distinct from old.upload_batch_id and new.upload_batch_id is not null)
     -- เวอร์ชันปลายทางและ checksum ตั้งได้ระหว่าง copying เท่านั้น
     or (old.status <> 'copying'
         and (new.version_id is distinct from old.version_id or new.checksum is distinct from old.checksum))
     or (old.ready_at is not null and new.ready_at is distinct from old.ready_at)
     or (old.delete_requested_at is not null and new.delete_requested_at is distinct from old.delete_requested_at) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;

  -- เดินหน้าอย่างเดียว: copying → ready | deleting, ready → deleting
  -- sweeper (ส่วน 9.1) ที่เจอ copying ค้าง "ย้อนกลับ" ด้วยการเดินหน้าเป็น deleting (ปลายทางมีไฟล์: บันทึก version_id
  -- แล้วลบแบบระบุเวอร์ชัน) หรือลบแถว copying (ปลายทางไม่มีไฟล์) — ไม่กลับเป็น copying จากสถานะอื่น
  if new.status <> old.status
     and not ((old.status = 'copying' and new.status in ('ready', 'deleting'))
              or (old.status = 'ready' and new.status = 'deleting')) then
    raise exception using errcode = 'P0001', message = 'invalid_status_transition';
  end if;
  -- ไฟล์ที่ยังผูกกับโจทย์/เฉลย/งานส่งเข้าคิวลบไม่ได้ (ผู้ผูกล็อกแถวนี้ FOR SHARE จึงไม่ชนกัน)
  if new.status = 'deleting' and old.status <> 'deleting'
     and exists (select 1 from public.attachments t where t.asset_id = old.id) then
    raise exception using errcode = 'P0001', message = 'asset_attached';
  end if;
  return new;
end
$$;

create trigger assets_guard
  before insert or update or delete on public.assets
  for each row execute function private.assets_guard();

create function private.attachments_guard()
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
       or new.solution_id is distinct from old.solution_id or new.created_at <> old.created_at then
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
  v_purpose := case when new.post_id is not null then 'post' when new.solution_id is not null then 'solution' end;
  if v_purpose is not null and v_asset.purpose <> v_purpose then
    raise exception using errcode = 'P0001', message = 'attachment_purpose_mismatch';
  end if;
  return new;
end
$$;

create trigger attachments_guard
  before insert or update on public.attachments
  for each row execute function private.attachments_guard();

-- ---------------------------------------------------------------------------
-- 3. ยอดพื้นที่และการจอง (J10) — ใช้ภายใน RPC/Edge Function ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
-- ยอดที่ใช้ = ไฟล์ทุกแถวที่ยังลบจาก B2 ไม่สำเร็จ (copying / ready / deleting รวมไฟล์ที่ไม่มีใครอ้างแล้ว)
--           + ส่วนที่ batch ซึ่งยัง open และไม่หมดอายุจองไว้ (หักขนาดไฟล์ของ batch นั้นที่กลายเป็น asset แล้ว กันนับซ้ำ)
create function private.storage_used_bytes()
returns bigint
language sql
volatile
set search_path = ''
as $$
  select (select coalesce(sum(a.size_bytes), 0) from public.assets a)::bigint
       + (select coalesce(sum(greatest(
                   b.reserved_bytes
                   - coalesce((select sum(x.size_bytes) from public.assets x where x.upload_batch_id = b.id), 0),
                   0)), 0)
            from public.upload_batches b
           where b.status = 'open' and b.expires_at > clock_timestamp())::bigint
$$;

-- จองพื้นที่ก่อนสร้าง batch: ล็อกแถว storage_settings (FOR UPDATE) แล้วจึงนับ — คำขอพร้อมกันรอกันทีละราย และรายถัดไป
-- นับรวม batch ที่รายก่อนสร้างแล้ว; ผู้เรียกต้องสร้าง batch ใน transaction เดียวกันก่อน commit (ล็อกปล่อยตอน commit)
-- คืนพื้นที่ที่ยังจองได้หลังรายการนี้; เกิน quota − margin → storage_full (UX 7.1)
create function private.reserve_storage(p_bytes bigint)
returns bigint
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_settings public.storage_settings;
  v_used bigint;
  v_limit bigint;
begin
  if p_bytes is null or p_bytes <= 0 then
    raise exception using errcode = 'P0001', message = 'invalid_size';
  end if;
  select s.* into v_settings from public.storage_settings s where s.singleton for update;
  v_used := private.storage_used_bytes();
  v_limit := v_settings.quota_bytes - v_settings.hard_stop_margin_bytes;
  if v_used + p_bytes > v_limit then
    raise exception using errcode = 'P0001', message = 'storage_full';
  end if;
  return v_limit - v_used - p_bytes;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS อ่าน (ฟังก์ชันช่วยอยู่ใน private: EXECUTE ให้ authenticated ไม่ให้ USAGE — 3.1 ข้อ 5)
-- ---------------------------------------------------------------------------
-- เห็นเฉลยนี้ได้หรือไม่ (เงื่อนไขเดียวกับ solutions_select ใน 0010): ครูเจ้าของห้อง/ผู้ดูแลเสมอ สมาชิกเมื่อเผยแพร่แล้ว
create function private.can_read_solution(p_assignment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case private.post_access(s.assignment_id)
             when 'teacher' then true
             when 'member' then s.published_at is not null
             else false
           end
      from public.solutions s
     where s.assignment_id = p_assignment_id), false)
$$;
grant execute on function private.can_read_solution(uuid) to authenticated;

grant select on public.storage_settings, public.upload_batches, public.attachments to authenticated;
-- assets: เปิดเฉพาะข้อมูลที่หน้าเว็บแสดง — key/version/checksum ใช้เฉพาะ Edge Function (ลิงก์ออกผ่าน authorize_files)
grant select (id, purpose, file_name, content_type, size_bytes, status, created_at) on public.assets to authenticated;

create policy storage_settings_select on public.storage_settings
  for select to authenticated
  using ((select private.is_teacher_or_admin()));

create policy upload_batches_select on public.upload_batches
  for select to authenticated
  using (owner_account_id = (select private.current_account()));

-- ไฟล์โจทย์ = สิทธิ์อ่านโพสต์ (สมาชิกขณะนี้ + ครูเจ้าของห้อง/ผู้ดูแล); ไฟล์เฉลย = สิทธิ์อ่านเฉลย
create policy attachments_select on public.attachments
  for select to authenticated
  using ((post_id is not null and private.post_access(post_id) is not null)
         or (solution_id is not null and private.can_read_solution(solution_id)));

-- ผู้อัปโหลดเห็นไฟล์ของตน (เช่นระหว่างอัปโหลดก่อนกดส่ง) และทุกคนเห็นไฟล์ที่ผูกกับสิ่งที่ตนอ่านได้ (ผ่าน RLS ของ attachments)
create policy assets_select on public.assets
  for select to authenticated
  using (owner_account_id = (select private.current_account())
         or exists (select 1 from public.attachments t where t.asset_id = assets.id));
