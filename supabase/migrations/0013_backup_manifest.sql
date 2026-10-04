-- 0013_backup_manifest: manifest ในฐานข้อมูลแบบไฟล์ละแถว (P3-01d) — ตัดสิน 4 ต.ค. 2026 จากขนาดที่วัดใน P3-01c
-- (TECHNICAL_BUILD_PLAN ส่วน 8 "ตาราง manifest ในฐานข้อมูล", TECHNICAL_DESIGN ส่วน 2, 12)
-- แทนแถวต่อไฟล์ต่อรอบของ 0012 (~468 ไบต์/แถว × 16 รอบ = 75–150 MB) ด้วย:
--   private.backup_manifests  ไฟล์ละแถว: final_key, version_id, ขนาด, checksum, รอบสำเร็จแรก/ล่าสุดที่เห็นไฟล์
--   private.backup_run_files  รายการของรอบที่กำลังทำ (ชั่วคราว ล้างเมื่อจบรอบทุกผล และเมื่อรอบค้างถูกปิดเป็น failed)
-- ใช้ได้เพราะ final_key ไม่ถูกใช้ซ้ำและ asset ไม่ย้อนเป็น ready: ไฟล์อยู่ในรอบสำเร็จติดกันเสมอ รอบสำเร็จ R อ้างไฟล์เมื่อ
-- รอบแรก ≤ R ≤ รอบล่าสุด (เรียงตาม started_at); รายการเต็มของแต่ละจุดกู้คืนอยู่ในไฟล์ manifest บน Drive
-- ทั้งสองตารางไม่อยู่ใน dump (backup.sh ใช้ --exclude-table-data) และฟังก์ชันทุกตัวเรียกได้เฉพาะ postgres

-- กันพลาด: ตารางแบบเดิมต้องว่างก่อนเปลี่ยนโครงสร้าง (ตรวจบน kemi-dev แล้ว 4 ต.ค. 2026: 0 แถว)
do $$
begin
  if exists (select 1 from private.backup_manifests) then
    raise exception 'private.backup_manifests ไม่ว่าง — หยุดก่อนเปลี่ยนโครงสร้าง';
  end if;
end
$$;

drop function private.backup_prune_manifests();
drop table private.backup_manifests;

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
-- ไฟล์ที่เคยอยู่ในรอบสำเร็จ (มีสำเนาใน Drive แล้ว) — ขยับเฉพาะตอนจบรอบสำเร็จ; ไม่ FK ไป assets (asset ถูกลบได้แต่สำเนา
-- ใน Drive ยังต้องเก็บจนไม่มีจุดกู้คืนใดอ้าง)
create table private.backup_manifests (
  final_key text primary key check (final_key like 'files/%'),
  version_id text not null check (version_id <> ''),
  size_bytes bigint not null check (size_bytes > 0),
  checksum text not null check (checksum <> ''),
  first_run_id uuid not null references public.backup_runs (id),
  last_run_id uuid not null references public.backup_runs (id),
  -- ขั้นแรกของการล้าง: ส่งรายการให้สคริปต์ไปลบจาก Drive แล้ว — ขั้นสองลบแถวได้เฉพาะที่ขอไว้
  prune_requested_at timestamptz
);
create index backup_manifests_first_run_id_idx on private.backup_manifests (first_run_id);
create index backup_manifests_last_run_id_idx on private.backup_manifests (last_run_id);

-- รายการของรอบที่กำลังทำ (snapshot เดียวกับ dump) — ใช้เขียนไฟล์ manifest ขึ้น Drive และหาไฟล์ใหม่
create table private.backup_run_files (
  run_id uuid not null references public.backup_runs (id) on delete cascade,
  final_key text not null check (final_key like 'files/%'),
  version_id text not null check (version_id <> ''),
  size_bytes bigint not null check (size_bytes > 0),
  checksum text not null check (checksum <> ''),
  primary key (run_id, final_key)
);

alter table private.backup_manifests enable row level security;
alter table private.backup_run_files enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ฟังก์ชันเดิมที่เปลี่ยนตามตารางใหม่
-- ---------------------------------------------------------------------------
-- เริ่มรอบ: เหมือน 0012 และล้างรายการชั่วคราวของรอบค้างที่ถูกปิดเป็น failed
create or replace function private.backup_start()
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
  -- รอบค้าง (Actions ตายกลางทางจนธงหมดอายุ): ล้างรายการชั่วคราวแล้วปิดเป็นล้มเหลว
  delete from private.backup_run_files f
   using public.backup_runs r
   where r.id = f.run_id and r.kind = 'backup' and r.status = 'running';
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

-- บันทึกรายการของรอบจาก assets สถานะ ready ใน snapshot ของผู้เรียก (ต้องเป็น session A ที่ export snapshot ให้ pg_dump)
create or replace function private.backup_record_manifest(p_run_id uuid)
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
  if exists (select 1 from private.backup_run_files f where f.run_id = p_run_id) then
    raise exception using errcode = 'P0001', message = 'manifest_recorded';
  end if;
  insert into private.backup_run_files (run_id, final_key, version_id, size_bytes, checksum)
  select p_run_id, a.final_key, a.version_id, a.size_bytes, a.checksum
    from public.assets a
   where a.status = 'ready';
  select count(*)::integer, coalesce(sum(f.size_bytes), 0)::bigint into v_count, v_bytes
    from private.backup_run_files f where f.run_id = p_run_id;
  return jsonb_build_object('file_count', v_count, 'total_bytes', v_bytes);
end
$$;

-- จบรอบ: สำเร็จต้องมีชื่อจุดกู้คืนและยอดตรงกับรายการของรอบ (manifest_mismatch) แล้วจึงรวมเข้า backup_manifests
-- (ไฟล์ใหม่ได้รอบแรก = รอบนี้ ไฟล์เดิมเลื่อนรอบล่าสุด = รอบนี้) — รอบที่ล้มเหลวไม่แตะ backup_manifests เลย
-- ทั้งสองผลล้างรายการชั่วคราวของรอบนี้; ไม่ปลดธง (เรียก backup_release_lock ต่อเสมอ)
create or replace function private.backup_finish(
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
    select count(*)::integer, coalesce(sum(f.size_bytes), 0)::bigint into v_count, v_bytes
      from private.backup_run_files f where f.run_id = p_run_id;
    if p_file_count is distinct from v_count or p_total_bytes is distinct from v_bytes then
      raise exception using errcode = 'P0001', message = 'manifest_mismatch';
    end if;
    -- version_id/ขนาด/checksum ใช้ค่าล่าสุด (หลังกู้คืนจริง version_id เปลี่ยนได้ แต่ final_key และเนื้อไฟล์เดิม)
    insert into private.backup_manifests (final_key, version_id, size_bytes, checksum, first_run_id, last_run_id)
    select f.final_key, f.version_id, f.size_bytes, f.checksum, p_run_id, p_run_id
      from private.backup_run_files f
     where f.run_id = p_run_id
    on conflict (final_key) do update
      set version_id = excluded.version_id,
          size_bytes = excluded.size_bytes,
          checksum = excluded.checksum,
          last_run_id = excluded.last_run_id,
          prune_requested_at = null;
  end if;
  delete from private.backup_run_files f where f.run_id = p_run_id;
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

-- ---------------------------------------------------------------------------
-- 3. ฟังก์ชันใหม่สำหรับ ops/backup.sh
-- ---------------------------------------------------------------------------
-- รายการไฟล์ของรอบนี้ — เขียนเป็นไฟล์ manifest ขึ้น gcrypt:runs/<เวลา>/ (รายการเต็มของจุดกู้คืน)
create function private.backup_run_file_list(p_run_id uuid)
returns table (final_key text, version_id text, size_bytes bigint, checksum text)
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform private.backup_running_run(p_run_id);
  return query
    select f.final_key, f.version_id, f.size_bytes, f.checksum
      from private.backup_run_files f
     where f.run_id = p_run_id
     order by f.final_key;
end
$$;

-- ไฟล์ใหม่ของรอบนี้ = อยู่ในรอบนี้แต่ไม่เคยอยู่ในรอบสำเร็จใด → rclone copy --files-from
-- (ไฟล์ที่เคยอยู่แค่ในรอบที่ล้มเหลวยังนับเป็นไฟล์ใหม่)
create function private.backup_new_files(p_run_id uuid)
returns table (final_key text)
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform private.backup_running_run(p_run_id);
  return query
    select f.final_key
      from private.backup_run_files f
     where f.run_id = p_run_id
       and not exists (select 1 from private.backup_manifests m where m.final_key = f.final_key)
     order by f.final_key;
end
$$;

-- ไฟล์ที่ไม่มีจุดกู้คืนใดอ้างแล้ว: รอบสำเร็จล่าสุดที่เห็นไฟล์เริ่มเกิน 8 วัน (จุดกู้คืน 7 วัน เผื่อ 1 วัน) และไม่ใช่
-- รอบสำเร็จล่าสุดของระบบ — สำรองล้มเหลวติดกันนานเท่าไรก็ไม่ล้างไฟล์ของจุดกู้คืนสุดท้ายที่มี
create function private.backup_prune_eligible(p_last_run_id uuid)
returns boolean
language sql
volatile
set search_path = ''
as $$
  select exists (
           select 1 from public.backup_runs r
            where r.id = p_last_run_id and r.started_at < clock_timestamp() - interval '8 days')
     and p_last_run_id is distinct from (
           select r.id from public.backup_runs r
            where r.kind = 'backup' and r.status = 'succeeded'
            order by r.started_at desc
            limit 1)
$$;

-- ล้างขั้นแรก: ทำเครื่องหมายไฟล์ที่ล้างได้แล้วคืนรายการ ให้สคริปต์ลบจาก Drive (--drive-use-trash=false)
create function private.backup_prune_candidates()
returns table (final_key text)
language plpgsql
volatile
set search_path = ''
as $$
begin
  update private.backup_manifests m
     set prune_requested_at = clock_timestamp()
   where m.prune_requested_at is null and private.backup_prune_eligible(m.last_run_id);
  return query
    select m.final_key
      from private.backup_manifests m
     where m.prune_requested_at is not null and private.backup_prune_eligible(m.last_run_id)
     order by m.final_key;
end
$$;

-- ล้างขั้นสอง: สคริปต์ส่งรายการที่ลบจาก Drive สำเร็จแล้ว — ลบแถวได้เฉพาะที่ขั้นแรกขอไว้และยังล้างได้
-- (ลบแถวก่อนลบใน Drive ไม่ได้ ไม่งั้นไฟล์ค้างใน Drive โดยไม่มีใครตามล้าง) คืนจำนวนแถวที่ลบ
create function private.backup_prune_confirm(p_final_keys text[])
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from private.backup_manifests m
   where m.final_key = any (coalesce(p_final_keys, '{}'))
     and m.prune_requested_at is not null
     and private.backup_prune_eligible(m.last_run_id);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end
$$;

-- ไม่มีบทบาทอื่นเรียกได้ (default privileges ถอน PUBLIC/anon/authenticated ไว้แล้ว — ระบุ service_role ด้วย)
revoke all on function private.backup_run_file_list(uuid), private.backup_new_files(uuid),
  private.backup_prune_eligible(uuid), private.backup_prune_candidates(), private.backup_prune_confirm(text[])
  from public, anon, authenticated, service_role;
