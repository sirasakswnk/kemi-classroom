-- 0012_backups: รอบสำรอง (backup_runs) และรายการไฟล์ต่อรอบ (private.backup_manifests) — migration กลุ่ม posts_files
-- ส่วนสุดท้าย (P3-01c) — TECHNICAL_DESIGN ส่วน 2, 9, 12; TECHNICAL_BUILD_PLAN 8 (backup.yml / restore-test.yml)
-- หลัก:
--   - ฟังก์ชันสำรองอยู่ใน private และเรียกได้เฉพาะ postgres: ops/backup.sh เรียกผ่าน psql ด้วย connection เดียวกับ pg_dump
--     (Session pooler) จึงไม่ต้องเก็บ service role key ใน GitHub; authenticated / service_role เรียกไม่ได้
--   - backup_manifests อยู่ใน private (ไม่มีใครอ่านผ่าน Data API) และไม่ FK ไป assets: asset ถูกลบได้แต่ manifest
--     ยังต้องใช้ 7 วัน (ส่วน 12 อายุสำเนา)
--   - backup_runs ผู้ดูแลอ่านได้ (แผงสำรองใน D01) ครูและนักเรียนไม่เห็น

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
create table public.backup_runs (
  id uuid primary key default gen_random_uuid(),
  -- backup = รอบสำรองของ backup.yml · restore_test = ผลทดสอบกู้คืนจาก restore-test.yml
  kind text not null check (kind in ('backup', 'restore_test')),
  status text not null check (status in ('running', 'succeeded', 'failed')),
  started_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz,
  -- backup: โฟลเดอร์ของรอบใน gcrypt:runs/<เวลา>/ · restore_test: จุดกู้คืนที่ใช้
  dump_name text check (dump_name is null or length(dump_name) between 1 and 200),
  -- backup: จำนวน/ขนาดไฟล์ใน manifest · restore_test: จำนวนไฟล์ที่กู้แล้วตรวจ
  file_count integer check (file_count >= 0),
  total_bytes bigint check (total_bytes >= 0),
  -- backup: ไฟล์ที่คัดลอกใหม่ในรอบนี้
  new_file_count integer check (new_file_count >= 0),
  -- ผลตรวจความครบหรือสาเหตุที่ล้มเหลวแบบสั้น (แสดงใน D01) — ห้ามใส่ข้อมูลนักเรียน
  detail text check (detail is null or length(detail) <= 1000),
  check ((status = 'running') = (finished_at is null)),
  -- restore_test บันทึกครั้งเดียวตอนจบ
  check (kind = 'backup' or status <> 'running'),
  -- รอบสำเร็จต้องบอกได้ว่าจุดกู้คืนอยู่ที่ไหน
  check (status <> 'succeeded' or dump_name is not null)
);
create index backup_runs_kind_started_at_idx on public.backup_runs (kind, started_at desc);

-- แถวต่อไฟล์ต่อรอบ: final_key + version_id ที่ dump ของรอบนั้นอ้าง (ไฟล์ใน Drive ลบได้เมื่อไม่มี manifest ใน 7 วันอ้าง)
create table private.backup_manifests (
  run_id uuid not null references public.backup_runs (id) on delete cascade,
  final_key text not null check (final_key like 'files/%'),
  version_id text not null check (version_id <> ''),
  size_bytes bigint not null check (size_bytes > 0),
  checksum text not null check (checksum <> ''),
  primary key (run_id, final_key)
);

alter table public.backup_runs enable row level security;
alter table private.backup_manifests enable row level security;

-- ---------------------------------------------------------------------------
-- 2. RLS: ผู้ดูแลอ่าน backup_runs ได้ (ฟังก์ชันช่วยอยู่ใน private: EXECUTE ให้ authenticated ไม่ให้ USAGE)
-- ---------------------------------------------------------------------------
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.accounts a where a.auth_user_id = auth.uid() and a.role = 'admin')
$$;
grant execute on function private.is_admin() to authenticated;

grant select on public.backup_runs to authenticated;

create policy backup_runs_select on public.backup_runs
  for select to authenticated
  using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- 3. ฟังก์ชันของงานสำรอง — เรียกได้เฉพาะ postgres (ผ่าน psql ใน ops/backup.sh และ ops/restore-test.sh)
-- ---------------------------------------------------------------------------
-- รหัสภายใน (ไม่ถึงหน้าเว็บ): backup_in_progress, backup_not_running, manifest_recorded, manifest_mismatch,
-- snapshot_required

-- เริ่มรอบ: ตั้งธงหยุดงานลบไฟล์ใน B2 (หมดอายุ 2 ชม. กันธงค้าง) + สร้างรอบ running ใน transaction เดียว
-- มีรอบ running ที่ธงยังไม่หมดอายุ → backup_in_progress; รอบ running ที่ธงหมดอายุแล้ว (Actions ตายกลางทาง) ปิดเป็น failed
create function private.backup_start()
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_run_id uuid;
  v_now timestamptz;
begin
  -- สองงานเริ่มพร้อมกันรอกันที่นี่ (concurrency group ของ Actions เป็นด่านแรก)
  perform pg_advisory_xact_lock(hashtextextended('backup_start', 0));
  -- อ่านเวลาครั้งเดียวหลังได้ล็อก ธงจึงมีอายุ 2 ชม. พอดีและเวลาของรอบตรงกัน
  v_now := clock_timestamp();
  if exists (select 1 from public.backup_runs r where r.kind = 'backup' and r.status = 'running')
     and exists (select 1 from private.maintenance_locks l
                  where l.name = 'backup' and l.expires_at > v_now) then
    raise exception using errcode = 'P0001', message = 'backup_in_progress';
  end if;
  update public.backup_runs r
     set status = 'failed', finished_at = v_now, detail = 'หยุดกลางทาง: ธงหมดอายุก่อนจบรอบ'
   where r.kind = 'backup' and r.status = 'running';
  insert into private.maintenance_locks (name, reason, acquired_at, expires_at)
  values ('backup', 'สำรองข้อมูล', v_now, v_now + interval '2 hours')
  on conflict (name) do update
    set reason = excluded.reason, acquired_at = excluded.acquired_at, expires_at = excluded.expires_at;
  insert into public.backup_runs (kind, status, started_at) values ('backup', 'running', v_now) returning id into v_run_id;
  return v_run_id;
end
$$;

-- รอบที่บันทึกต่อได้: ชนิด backup และยัง running (ล็อกแถวไว้กันจบรอบซ้อน)
create function private.backup_running_run(p_run_id uuid)
returns public.backup_runs
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_run public.backup_runs;
begin
  select r.* into v_run from public.backup_runs r where r.id = p_run_id for update;
  if not found or v_run.kind <> 'backup' or v_run.status <> 'running' then
    raise exception using errcode = 'P0001', message = 'backup_not_running';
  end if;
  return v_run;
end
$$;

-- บันทึก manifest จาก assets สถานะ ready ใน snapshot ของผู้เรียก — ต้องเรียกใน session A ที่ export snapshot ให้ pg_dump
-- (BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT pg_export_snapshot(); …) manifest จึงตรงกับ dump ทุกแถว
-- คืน {file_count, total_bytes}; รายการให้ rclone อ่านจาก private.backup_manifests ของรอบนี้
create function private.backup_record_manifest(p_run_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_count integer;
  v_bytes bigint;
begin
  if current_setting('transaction_isolation') <> 'repeatable read' then
    raise exception using errcode = 'P0001', message = 'snapshot_required';
  end if;
  perform private.backup_running_run(p_run_id);
  if exists (select 1 from private.backup_manifests m where m.run_id = p_run_id) then
    raise exception using errcode = 'P0001', message = 'manifest_recorded';
  end if;
  insert into private.backup_manifests (run_id, final_key, version_id, size_bytes, checksum)
  select p_run_id, a.final_key, a.version_id, a.size_bytes, a.checksum
    from public.assets a
   where a.status = 'ready';
  select count(*)::integer, coalesce(sum(m.size_bytes), 0)::bigint into v_count, v_bytes
    from private.backup_manifests m where m.run_id = p_run_id;
  return jsonb_build_object('file_count', v_count, 'total_bytes', v_bytes);
end
$$;

-- จบรอบ: สำเร็จต้องมีชื่อจุดกู้คืน และจำนวน/ขนาดที่ตรวจได้ต้องตรงกับ manifest; ล้มเหลวบันทึกสาเหตุ
-- (ไม่ปลดธง — เรียก backup_release_lock ต่อเสมอ ทั้งตอนสำเร็จและล้มเหลว)
create function private.backup_finish(
  p_run_id uuid,
  p_succeeded boolean,
  p_dump_name text default null,
  p_file_count integer default null,
  p_total_bytes bigint default null,
  p_new_file_count integer default null,
  p_detail text default null
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_count integer;
  v_bytes bigint;
begin
  perform private.backup_running_run(p_run_id);
  if p_succeeded then
    select count(*)::integer, coalesce(sum(m.size_bytes), 0)::bigint into v_count, v_bytes
      from private.backup_manifests m where m.run_id = p_run_id;
    if p_file_count is distinct from v_count or p_total_bytes is distinct from v_bytes then
      raise exception using errcode = 'P0001', message = 'manifest_mismatch';
    end if;
  end if;
  update public.backup_runs
     set status = case when p_succeeded then 'succeeded' else 'failed' end,
         finished_at = clock_timestamp(),
         dump_name = p_dump_name,
         file_count = p_file_count,
         total_bytes = p_total_bytes,
         new_file_count = p_new_file_count,
         detail = p_detail
   where id = p_run_id;
end
$$;

-- ปลดธงหยุดงานลบไฟล์ (เรียกซ้ำได้) — คืน true เมื่อมีธงให้ปลด
create function private.backup_release_lock()
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
begin
  delete from private.maintenance_locks where name = 'backup';
  return found;
end
$$;

-- ผลทดสอบกู้คืน (restore-test.yml บันทึกลงระบบจริงตอนจบ) แสดง "ทดสอบกู้คืนล่าสุด" ใน D01
create function private.backup_record_restore_test(
  p_succeeded boolean,
  p_restore_point text,
  p_files_checked integer,
  p_detail text default null
)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  insert into public.backup_runs (kind, status, started_at, finished_at, dump_name, file_count, detail)
  values ('restore_test', case when p_succeeded then 'succeeded' else 'failed' end, v_now, v_now,
          p_restore_point, p_files_checked, p_detail)
  returning id into v_id;
  return v_id;
end
$$;

-- ล้าง manifest ที่ไม่ใช้แล้ว (backup.sh เรียกตอนท้าย): รอบที่เริ่มเกิน 8 วัน (จุดกู้คืน 7 วัน เผื่อ 1 วัน) และรอบที่ล้มเหลว
-- (ไม่ใช่จุดกู้คืน) — แถว backup_runs เก็บไว้เป็นประวัติ คืนจำนวนแถว manifest ที่ลบ
create function private.backup_prune_manifests()
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from private.backup_manifests m
   using public.backup_runs r
   where r.id = m.run_id
     and (r.started_at < clock_timestamp() - interval '8 days' or r.status = 'failed');
  get diagnostics v_deleted = row_count;
  return v_deleted;
end
$$;

-- ย้ำ: ไม่มีบทบาทอื่นเรียกได้ (default privileges ถอน PUBLIC/anon/authenticated ไว้แล้ว — ระบุ service_role ด้วย)
revoke all on function private.backup_start(), private.backup_running_run(uuid), private.backup_record_manifest(uuid),
  private.backup_finish(uuid, boolean, text, integer, bigint, integer, text), private.backup_release_lock(),
  private.backup_record_restore_test(boolean, text, integer, text), private.backup_prune_manifests()
  from public, anon, authenticated, service_role;
