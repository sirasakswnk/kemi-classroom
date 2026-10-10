-- 0023_jobs: ตัวทำงานเบื้องหลังขั้นต่ำ (P3-10) — คิวงาน, ลบไฟล์ใน B2 แบบระบุเวอร์ชัน, sweeper แถว copying, งานประจำ
-- และยอดพื้นที่/ตัวนับ B2 ให้หน้าเว็บอ่าน
-- TECHNICAL_DESIGN 9 (ลบแล้วต้องคืนพื้นที่จริง ข้อ 1–3, ข้อ 8), 9.1, 9.3, 12 (J10); BUILD_PLAN 5 (process-jobs)
-- แบ่งหน้าที่:
--   - ฐานข้อมูลตัดสินทุกอย่าง (เลือกงาน, ตรวจ maintenance_locks, ตรวจว่า asset ยังลบได้) — Edge Function `process-jobs`
--     แค่เรียก B2 ตามที่ RPC บอก แล้วรายงานผลกลับ; RPC ชุดนี้ GRANT ให้ service_role เท่านั้น
--   - ดึงงานด้วย FOR UPDATE SKIP LOCKED ทีละชุดเล็ก — รันซ้อนกันได้โดยไม่ได้งานเดียวกัน; งานที่ค้าง running เกิน
--     10 นาที (ตัวทำงานหยุดกลางทาง) ดึงใหม่ได้ ทุกงานจึงต้อง idempotent (delete_asset: ลบซ้ำ/ไม่มีไฟล์แล้ว = สำเร็จ)
--   - ล้มเหลว → ลองใหม่เว้นช่วง 1, 2, 4, 8, 16 นาที … (สูงสุด 6 ชม.) เกิน 6 ครั้ง → failed (แสดงในหน้าผู้ดูแลภายหลัง)
--   - งานประจำที่เป็น SQL ล้วน (jobs_maintenance) cron เรียกตรงใน 0024 ไม่ต้องปลุก Edge Function
-- รหัสใหม่ที่หน้าเว็บอาจเจอ: ไม่มี (storage_status/admin_b2_usage ตอบ forbidden เมื่อไม่มีสิทธิ์)

-- ---------------------------------------------------------------------------
-- 1. ค่าตั้ง [ค่าที่ Claude เลือก — ปรับได้ในไฟล์นี้]
-- ---------------------------------------------------------------------------
create function private.jobs_limits()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'max_attempts', 6,               -- เกินนี้ = failed
    'backoff_base_seconds', 60,      -- 60 × 2^(ครั้งที่ล้ม − 1)
    'backoff_max_seconds', 21600,    -- ไม่เกิน 6 ชม.
    'stale_running_minutes', 10,     -- running ค้างนานกว่านี้ = ตัวทำงานหยุดกลางทาง ดึงใหม่ได้
    'claim_max', 50,
    'copying_stale_minutes', 15,     -- sweeper แถว copying (TECHNICAL_DESIGN 9 ข้อ 3)
    'orphan_grace_hours', 24,        -- asset ไม่มีแถวผูก + batch หมดอายุเกิน 24 ชม. (9 ข้อ 8)
    'orphan_batch_max', 200,
    'usage_keep_days', 30,           -- ล้าง b2_daily_usage เก่า
    'done_keep_days', 30)            -- ล้างงานที่เสร็จแล้ว (failed เก็บไว้ให้ผู้ดูแลดู)
$$;

-- batch ที่เลยเวลาแล้วมีสถานะของตัวเอง (เดิมนับเป็นหมดอายุจาก expires_at อย่างเดียว)
alter table public.upload_batches
  drop constraint upload_batches_status_check,
  add constraint upload_batches_status_check check (status in ('open', 'consumed', 'cancelled', 'expired'));

-- ---------------------------------------------------------------------------
-- 2. คิวงาน (service_role)
-- ---------------------------------------------------------------------------
-- ดึงงานที่ถึงเวลา (pending) หรือค้าง running เกินเวลา ทีละชุด — ผล: [{ id, kind, payload, attempts }]
create function public.jobs_claim(p_limit integer default 10)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_limits jsonb := private.jobs_limits();
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
begin
  with picked as (
    select j.id
      from private.jobs j
     where (j.status = 'pending' and j.run_at <= v_now)
        or (j.status = 'running'
            and j.locked_at < v_now - make_interval(mins => (v_limits ->> 'stale_running_minutes')::integer))
     order by j.run_at, j.id
     limit least(greatest(coalesce(p_limit, 10), 1), (v_limits ->> 'claim_max')::integer)
     for update skip locked
  ), claimed as (
    update private.jobs j
       set status = 'running', locked_at = v_now, attempts = j.attempts + 1, updated_at = v_now
      from picked
     where j.id = picked.id
    returning j.id, j.kind, j.payload, j.attempts
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'payload', c.payload,
                                               'attempts', c.attempts) order by c.id), '[]'::jsonb)
    into v_result
    from claimed c;
  return v_result;
end
$$;

-- งานที่ดึงไปแล้ว (running) — แถวอื่นถือว่ามีตัวทำงานอื่นจัดการแล้ว คืน false
create function private.jobs_running(p_job_id bigint)
returns private.jobs
language sql
volatile
set search_path = ''
as $$
  select j.* from private.jobs j where j.id = p_job_id and j.status = 'running' for update
$$;

create function public.jobs_complete(p_job_id bigint, p_note text default null)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update private.jobs
     set status = 'done', locked_at = null, last_error = left(p_note, 500), updated_at = clock_timestamp()
   where id = p_job_id and status = 'running';
  return found;
end
$$;

-- ล้มเหลว: ลองใหม่แบบเว้นช่วงห่างขึ้น หรือ failed เมื่อครบจำนวนครั้ง — คืนสถานะใหม่
create function public.jobs_fail(p_job_id bigint, p_error text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_limits jsonb := private.jobs_limits();
  v_job private.jobs;
  v_wait integer;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null then
    return null;
  end if;
  if v_job.attempts >= (v_limits ->> 'max_attempts')::integer then
    update private.jobs
       set status = 'failed', locked_at = null, last_error = left(p_error, 500), updated_at = clock_timestamp()
     where id = p_job_id;
    return 'failed';
  end if;
  v_wait := least((v_limits ->> 'backoff_base_seconds')::integer * (2 ^ (v_job.attempts - 1))::integer,
                  (v_limits ->> 'backoff_max_seconds')::integer);
  update private.jobs
     set status = 'pending', locked_at = null, last_error = left(p_error, 500),
         run_at = clock_timestamp() + make_interval(secs => v_wait), updated_at = clock_timestamp()
   where id = p_job_id;
  return 'pending';
end
$$;

-- เลื่อนรอบโดยไม่นับเป็นการลอง (เช่นมีธง maintenance_locks)
create function private.jobs_defer(p_job_id bigint, p_until timestamptz, p_reason text)
returns void
language sql
volatile
set search_path = ''
as $$
  update private.jobs
     set status = 'pending', locked_at = null, attempts = greatest(attempts - 1, 0),
         run_at = greatest(p_until, clock_timestamp() + interval '1 minute'),
         last_error = p_reason, updated_at = clock_timestamp()
   where id = p_job_id and status = 'running'
$$;

-- ---------------------------------------------------------------------------
-- 3. งาน delete_asset (ลบ B2 แบบระบุ version_id แล้วลบแถว asset — เลิกนับพื้นที่)
-- ---------------------------------------------------------------------------
-- ก่อนเรียก B2: ผล { action: 'delete', final_key, version_id } | { action: 'defer' } | { action: 'done', note } |
-- { action: 'skip' } (งานไม่ได้อยู่ในมือผู้เรียกแล้ว) — ค่า key/เวอร์ชันมาจากแถว asset ไม่ใช่ payload
create function public.delete_asset_begin(p_job_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
  v_asset public.assets;
  v_lock timestamptz;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null or v_job.kind <> 'delete_asset' then
    return jsonb_build_object('action', 'skip');
  end if;
  -- ธงหยุดลบระหว่างสำรอง (9.1 ข้อ 4) → เลื่อนไปหลังธงหมดอายุ
  select max(l.expires_at) into v_lock from private.maintenance_locks l where l.expires_at > clock_timestamp();
  if v_lock is not null then
    perform private.jobs_defer(p_job_id, v_lock, 'maintenance_lock');
    return jsonb_build_object('action', 'defer');
  end if;
  select a.* into v_asset from public.assets a where a.id = (v_job.payload ->> 'asset_id')::uuid for update;
  if not found then
    perform public.jobs_complete(p_job_id, 'asset_gone');
    return jsonb_build_object('action', 'done', 'note', 'asset_gone');
  end if;
  -- ห้ามลบไฟล์ที่ยังผูกอยู่หรือไม่ได้อยู่ในคิวลบ (เช่นงานที่ใส่ผิด) — ปิดงานโดยไม่แตะไฟล์
  if v_asset.status <> 'deleting'
     or exists (select 1 from public.attachments t where t.asset_id = v_asset.id) then
    perform public.jobs_complete(p_job_id, 'asset_kept');
    return jsonb_build_object('action', 'done', 'note', 'asset_kept');
  end if;
  return jsonb_build_object('action', 'delete', 'asset_id', v_asset.id, 'final_key', v_asset.final_key,
                            'version_id', v_asset.version_id);
end
$$;

-- B2 ลบสำเร็จ (204/200) หรือไม่มีเวอร์ชันนั้นแล้ว (404) → ลบแถว asset แล้วปิดงาน
create function public.delete_asset_finish(p_job_id bigint)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null or v_job.kind <> 'delete_asset' then
    return false;
  end if;
  delete from public.assets a
   where a.id = (v_job.payload ->> 'asset_id')::uuid
     and a.status = 'deleting'
     and not exists (select 1 from public.attachments t where t.asset_id = a.id);
  perform public.jobs_complete(p_job_id, null);
  return true;
end
$$;

-- เข้าคิวลบ asset (ใช้ร่วม: กำพร้า, copying ที่ค้าง) — idempotent ด้วย dedupe_key = asset id
create function private.enqueue_delete_asset(p_asset public.assets, p_reason text)
returns void
language sql
volatile
set search_path = ''
as $$
  insert into private.jobs (kind, payload, dedupe_key)
  values ('delete_asset',
          jsonb_build_object('asset_id', p_asset.id, 'final_key', p_asset.final_key,
                             'version_id', p_asset.version_id, 'reason', p_reason),
          p_asset.id::text)
  on conflict (kind, dedupe_key) do nothing
$$;

-- ---------------------------------------------------------------------------
-- 4. sweeper แถว copying ที่ค้าง (ขั้น complete หยุดกลางทาง — 9 ข้อ 3, โน้ต P3-04)
-- ---------------------------------------------------------------------------
-- รายการให้ Edge Function HEAD ไฟล์ปลายทาง (นับ Class B แหล่ง complete) — ผล: [{ asset_id, final_key }]
create function public.copying_stale(p_limit integer default 10)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('asset_id', x.id, 'final_key', x.final_key) order by x.created_at), '[]'::jsonb)
    from (select a.id, a.final_key, a.created_at
            from public.assets a
           where a.status = 'copying'
             and a.created_at < clock_timestamp()
                                - make_interval(mins => (private.jobs_limits() ->> 'copying_stale_minutes')::integer)
           order by a.created_at
           limit least(greatest(coalesce(p_limit, 10), 1), 50)) x
$$;

-- ผล HEAD: มีไฟล์ (p_version_id) → บันทึกเวอร์ชัน + deleting + งานลบ (ไม่ทำต่อเป็น ready: ผู้ใช้ได้ข้อผิดพลาดและอัปโหลด
-- ใหม่ไปแล้ว) · ไม่มีไฟล์ (null) → ลบแถว (ผู้ใช้เรียก complete ใหม่ได้) — คืน 'queued' | 'removed' | 'skip'
create function public.sweep_copying_finish(p_asset_id uuid, p_version_id text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asset public.assets;
begin
  select a.* into v_asset from public.assets a where a.id = p_asset_id for update;
  if not found or v_asset.status <> 'copying'
     or v_asset.created_at >= clock_timestamp()
                              - make_interval(mins => (private.jobs_limits() ->> 'copying_stale_minutes')::integer) then
    return 'skip';
  end if;
  if p_version_id is null or p_version_id = '' then
    delete from public.assets where id = p_asset_id;
    return 'removed';
  end if;
  update public.assets
     set version_id = p_version_id, status = 'deleting', delete_requested_at = clock_timestamp()
   where id = p_asset_id
  returning * into v_asset;
  perform private.enqueue_delete_asset(v_asset, 'stale_copying');
  return 'queued';
end
$$;

-- ---------------------------------------------------------------------------
-- 5. งานประจำ (SQL ล้วน — cron เรียกตรง; service_role เรียกได้เพื่อทดสอบ/สั่งเอง)
-- ---------------------------------------------------------------------------
-- (1) batch เปิดที่เลยเวลา → expired  (2) asset ready ที่ไม่มีแถวผูก และ batch หมดอายุเกิน 24 ชม.
--     (ไม่มี batch แล้ว ใช้เวลาที่พร้อมใช้) → deleting + งานลบ  (3) ล้างตัวนับ B2 เก่า งานที่เสร็จนาน และใบรับคำขอที่หมดอายุ
-- ผล: { batches_expired, orphans_queued, usage_deleted, jobs_deleted, receipts_deleted }
create function public.jobs_maintenance()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_limits jsonb := private.jobs_limits();
  v_now timestamptz := clock_timestamp();
  v_grace interval := make_interval(hours => (v_limits ->> 'orphan_grace_hours')::integer);
  v_batches integer;
  v_orphans integer := 0;
  v_usage integer;
  v_jobs integer;
  v_receipts integer;
  v_asset public.assets;
begin
  update public.upload_batches set status = 'expired' where status = 'open' and expires_at <= v_now;
  get diagnostics v_batches = row_count;

  -- ล็อกแบบข้ามแถวที่มีคนถืออยู่ (เช่นกำลังผูกกับโพสต์/งานส่งพร้อมกัน — ผู้ผูกล็อก FOR UPDATE/SHARE) รอบหน้าค่อยดูใหม่
  for v_asset in
    select a.*
      from public.assets a
      left join public.upload_batches b on b.id = a.upload_batch_id
     where a.status = 'ready'
       and not exists (select 1 from public.attachments t where t.asset_id = a.id)
       and coalesce(b.expires_at, a.ready_at) < v_now - v_grace
     order by a.id
     limit (v_limits ->> 'orphan_batch_max')::integer
     for update of a skip locked
  loop
    update public.assets set status = 'deleting', delete_requested_at = v_now where id = v_asset.id
    returning * into v_asset;
    perform private.enqueue_delete_asset(v_asset, 'orphan');
    v_orphans := v_orphans + 1;
  end loop;

  delete from public.b2_daily_usage
   where day < (v_now at time zone 'UTC')::date - (v_limits ->> 'usage_keep_days')::integer;
  get diagnostics v_usage = row_count;
  delete from private.jobs
   where status = 'done' and updated_at < v_now - make_interval(days => (v_limits ->> 'done_keep_days')::integer);
  get diagnostics v_jobs = row_count;
  delete from private.operation_receipts where expires_at < v_now;
  get diagnostics v_receipts = row_count;

  return jsonb_build_object('batches_expired', v_batches, 'orphans_queued', v_orphans, 'usage_deleted', v_usage,
                            'jobs_deleted', v_jobs, 'receipts_deleted', v_receipts);
end
$$;

-- มีงานให้ Edge Function ทำหรือไม่ (cron ใช้ตัดสินว่าจะปลุกฟังก์ชันไหม)
create function private.jobs_has_work()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from private.jobs j
                  where (j.status = 'pending' and j.run_at <= clock_timestamp())
                     or (j.status = 'running'
                         and j.locked_at < clock_timestamp()
                                           - make_interval(mins => (private.jobs_limits() ->> 'stale_running_minutes')::integer)))
      or exists (select 1 from public.assets a
                  where a.status = 'copying'
                    and a.created_at < clock_timestamp()
                                       - make_interval(mins => (private.jobs_limits() ->> 'copying_stale_minutes')::integer))
$$;

revoke all on function public.jobs_claim(integer), public.jobs_complete(bigint, text), public.jobs_fail(bigint, text),
  public.delete_asset_begin(bigint), public.delete_asset_finish(bigint), public.copying_stale(integer),
  public.sweep_copying_finish(uuid, text), public.jobs_maintenance() from public, anon, authenticated;
grant execute on function public.jobs_claim(integer), public.jobs_complete(bigint, text), public.jobs_fail(bigint, text),
  public.delete_asset_begin(bigint), public.delete_asset_finish(bigint), public.copying_stale(integer),
  public.sweep_copying_finish(uuid, text), public.jobs_maintenance() to service_role;

-- ---------------------------------------------------------------------------
-- 6. ยอดพื้นที่และตัวนับ B2 ให้หน้าเว็บอ่าน (authenticated)
-- ---------------------------------------------------------------------------
-- ระดับ: เทียบกับเพดานที่ใช้ได้จริง (quota − hard_stop_margin — 100% = อัปโหลดใหม่ไม่ได้ J10.2)
-- full = ใช้ ≥ เพดาน · teacher_warn ≥ teacher_warn_pct · admin_warn ≥ admin_warn_pct · ok
-- ครู/ผู้ดูแล: ยอดละเอียด · นักเรียน: แค่ระดับ full/ok (หน้าส่งงานเปลี่ยนกล่องเลือกไฟล์เป็นกล่องแจ้งเต็ม J10.3)
create function public.storage_status()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_settings public.storage_settings;
  v_used bigint;
  v_limit bigint;
  v_pct numeric;
  v_level text;
begin
  select a.role into v_role from public.accounts a where a.auth_user_id = auth.uid();
  if v_role is null then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select s.* into v_settings from public.storage_settings s where s.singleton;
  v_used := private.storage_used_bytes();
  v_limit := v_settings.quota_bytes - v_settings.hard_stop_margin_bytes;
  v_pct := round(v_used * 100.0 / v_limit, 1);
  v_level := case when v_used >= v_limit then 'full'
                  when v_pct >= v_settings.teacher_warn_pct then 'teacher_warn'
                  when v_pct >= v_settings.admin_warn_pct then 'admin_warn'
                  else 'ok' end;
  if v_role = 'student' then
    return jsonb_build_object('level', case when v_level = 'full' then 'full' else 'ok' end);
  end if;
  return jsonb_build_object(
    'level', v_level,
    'used_bytes', v_used,
    'limit_bytes', v_limit,
    'quota_bytes', v_settings.quota_bytes,
    'percent', v_pct,
    'admin_warn_pct', v_settings.admin_warn_pct,
    'teacher_warn_pct', v_settings.teacher_warn_pct,
    'reserved_bytes', v_used - (select coalesce(sum(a.size_bytes), 0) from public.assets a),
    'deleting_bytes', (select coalesce(sum(a.size_bytes), 0) from public.assets a where a.status = 'deleting'),
    'by_purpose', (select jsonb_build_object(
                      'submission', coalesce(sum(a.size_bytes) filter (where a.purpose = 'submission'), 0),
                      'post', coalesce(sum(a.size_bytes) filter (where a.purpose = 'post'), 0),
                      'solution', coalesce(sum(a.size_bytes) filter (where a.purpose = 'solution'), 0),
                      'charm', coalesce(sum(a.size_bytes) filter (where a.purpose = 'charm'), 0))
                     from public.assets a where a.status <> 'deleting'));
end
$$;

-- ผู้ดูแล: ตัวนับ B2 ของวันนี้ (รอบวัน UTC = 07:00 น. ไทย) เทียบงบเปิดดู + สถานะคิวงาน
create function public.admin_b2_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_day date := (clock_timestamp() at time zone 'UTC')::date;
  v_settings public.storage_settings;
begin
  if not private.is_admin() then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select s.* into v_settings from public.storage_settings s where s.singleton;
  return jsonb_build_object(
    'day', v_day,
    'sources', coalesce((select jsonb_object_agg(u.source, jsonb_build_object(
                                 'class_b_requests', u.class_b_requests, 'download_bytes', u.download_bytes,
                                 'copy_bytes', u.copy_bytes))
                           from public.b2_daily_usage u where u.day = v_day), '{}'::jsonb),
    'view_budget_requests', v_settings.daily_view_budget_requests,
    'view_budget_bytes', v_settings.daily_view_budget_bytes,
    'jobs', (select jsonb_build_object(
                'pending', count(*) filter (where j.status = 'pending'),
                'running', count(*) filter (where j.status = 'running'),
                'failed', count(*) filter (where j.status = 'failed'))
               from private.jobs j));
end
$$;

revoke all on function public.storage_status(), public.admin_b2_usage() from public, anon;
grant execute on function public.storage_status(), public.admin_b2_usage() to authenticated;
