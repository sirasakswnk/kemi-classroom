-- 0049_storage_reconcile: เทียบยอดพื้นที่จริงใน B2 วันละครั้ง (P6-04a) — TECHNICAL_DESIGN 9.2 ข้อ 3, 9.3; SYSTEM_SPEC 12
-- ทุกวัน 04:30 น. ไทย (21:30 UTC — หลังรอบสำรอง 02:30 น.) cron สร้างงาน storage_reconcile 1 งาน (ไม่ซ้อนกับงานที่ยังค้าง)
-- process-jobs ทำงานนี้เป็นหน้า ๆ: ListObjectVersions หน้าละ 1000 รายการ (Class C) **นับทุกเวอร์ชัน** รวมเวอร์ชันที่ถูกซ่อน
--   (กินพื้นที่จนกว่า lifecycle จะลบ) และ staging/ แล้วส่งผลแต่ละหน้าให้ storage_reconcile_step รวมยอดเก็บใน payload ของงาน
-- กันงบ Class C (2,500/วัน ใช้ร่วมกับรอบสำรอง): เพดานต่อรอบ reconcile_run_max_requests และต่อวัน
--   reconcile_daily_budget_requests (นับใน b2_daily_usage source 'reconcile') — ครบแล้วพักงานไว้ รอบหน้า/วันถัดไปทำต่อจาก cursor
-- จบแล้ว: diff = ยอด B2 − ยอดที่ระบบใช้คิดโควตา (assets + ที่จองไว้) → ค่าชดเชย storage_offset_bytes = greatest(0, diff)
--   (ใช้ยอดที่มากกว่า — ผู้ใช้เลือกตามเอกสาร 25 ต.ค. 2026) บวกเข้า storage_used_bytes() + เก็บประวัติใน storage_reconciliations
--   ให้ D01 แสดง (P6-04c) · **ไม่ลบไฟล์ใน B2 จากผลเทียบนี้**

-- ---------------------------------------------------------------------------
-- 1. ค่าตั้ง + ตัวนับ Class C
-- ---------------------------------------------------------------------------
alter table public.storage_settings
  -- ส่วนที่ B2 มากกว่าที่ระบบนับได้ ณ การเทียบล่าสุด (ไม่ติดลบ: B2 น้อยกว่าไม่ลดยอด)
  add column storage_offset_bytes bigint not null default 0 check (storage_offset_bytes >= 0),
  add column reconciled_at timestamptz,
  add column reconcile_run_max_requests integer not null default 20
    check (reconcile_run_max_requests between 1 and 200),
  add column reconcile_daily_budget_requests integer not null default 500
    check (reconcile_daily_budget_requests between 1 and 2500),
  -- ต่างกันถึงเกณฑ์ใดเกณฑ์หนึ่ง = ธง exceeds_threshold (TECHNICAL_DESIGN 9.2 ข้อ 3 “เช่น 5% หรือ 200 MB”)
  add column reconcile_warn_pct integer not null default 5 check (reconcile_warn_pct between 1 and 100),
  add column reconcile_warn_bytes bigint not null default 200000000 check (reconcile_warn_bytes > 0);

alter table public.b2_daily_usage
  add column class_c_requests bigint not null default 0 check (class_c_requests >= 0),
  drop constraint b2_daily_usage_source_check,
  add constraint b2_daily_usage_source_check check (source in ('view', 'complete', 'backup', 'reconcile'));

-- ---------------------------------------------------------------------------
-- 2. ประวัติการเทียบ (อ่านผ่าน RPC ของผู้ดูแลใน P6-04c — ไม่มี GRANT ตาราง)
-- ---------------------------------------------------------------------------
create table public.storage_reconciliations (
  id bigint generated always as identity primary key,
  job_id bigint,
  started_at timestamptz not null,
  finished_at timestamptz not null default clock_timestamp(),
  -- ยอดจริงใน B2: ทุกเวอร์ชันของทุก key (ป้ายซ่อนไม่มีขนาด)
  b2_bytes bigint not null,
  b2_versions integer not null,
  -- แยก: files/ staging/ อื่น ๆ · เวอร์ชันที่ไม่ใช่ล่าสุด · files/ ที่ไม่มีแถว asset ตรง (key + version) · ป้ายซ่อน
  breakdown jsonb not null,
  -- ยอดที่ระบบนับตอนจบ: ขนาด assets ทุกสถานะ + พื้นที่ที่ batch ยังเปิดจองไว้ (ไม่รวมค่าชดเชยเดิม)
  db_assets_bytes bigint not null,
  db_reserved_bytes bigint not null,
  diff_bytes bigint not null,
  offset_before_bytes bigint not null,
  offset_after_bytes bigint not null,
  exceeds_threshold boolean not null,
  -- คำขอ Class C ทั้งหมดของการเทียบนี้ และจำนวนรอบ process-jobs ที่ใช้
  requests integer not null,
  runs integer not null
);
create index storage_reconciliations_finished_idx on public.storage_reconciliations (finished_at desc);
alter table public.storage_reconciliations enable row level security;
revoke all on public.storage_reconciliations from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. ยอดที่ใช้คิดโควตา = assets + ที่จองไว้ + ค่าชดเชยจากการเทียบล่าสุด
-- ---------------------------------------------------------------------------
create or replace function private.storage_used_bytes()
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
       + (select s.storage_offset_bytes from public.storage_settings s where s.singleton)
$$;

-- reserved_bytes เดิมคิดจาก used − assets → ตัดค่าชดเชยออก และบอกค่าชดเชยแยก (offset_bytes)
create or replace function public.storage_status()
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
    'reserved_bytes', v_used - v_settings.storage_offset_bytes
                      - (select coalesce(sum(a.size_bytes), 0) from public.assets a),
    'offset_bytes', v_settings.storage_offset_bytes,
    'reconciled_at', v_settings.reconciled_at,
    'deleting_bytes', (select coalesce(sum(a.size_bytes), 0) from public.assets a where a.status = 'deleting'),
    'by_purpose', (select jsonb_build_object(
                      'submission', coalesce(sum(a.size_bytes) filter (where a.purpose = 'submission'), 0),
                      'post', coalesce(sum(a.size_bytes) filter (where a.purpose = 'post'), 0),
                      'solution', coalesce(sum(a.size_bytes) filter (where a.purpose = 'solution'), 0),
                      'charm', coalesce(sum(a.size_bytes) filter (where a.purpose = 'charm'), 0))
                     from public.assets a where a.status <> 'deleting'));
end
$$;

-- ---------------------------------------------------------------------------
-- 4. สร้างงานรายวัน (cron ในนาม postgres)
-- ---------------------------------------------------------------------------
-- ไม่สร้างถ้ามีงานเทียบที่ยังค้าง (pending/running — เช่นพักเพราะครบงบเมื่อวาน) · dedupe = วันที่ไทย
create function private.storage_reconcile_enqueue()
returns bigint
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if exists (select 1 from private.jobs j
              where j.kind = 'storage_reconcile' and j.status in ('pending', 'running')) then
    return null;
  end if;
  insert into private.jobs (kind, payload, dedupe_key)
  values ('storage_reconcile', '{}'::jsonb,
          to_char(clock_timestamp() at time zone 'Asia/Bangkok', 'YYYY-MM-DD'))
  on conflict (kind, dedupe_key) do nothing
  returning id into v_id;
  return v_id;
end
$$;
revoke all on function private.storage_reconcile_enqueue() from public, anon, authenticated;

select cron.schedule('kemi-storage-reconcile', '30 21 * * *', 'select private.storage_reconcile_enqueue()');

-- ---------------------------------------------------------------------------
-- 5. ตัวทำงาน (process-jobs, service_role)
-- ---------------------------------------------------------------------------
-- พักงานไว้ทำต่อรอบหลัง: คงยอดและ cursor ใน payload, ไม่นับเป็นการล้ม (attempts กลับเป็น 0)
create function private.storage_reconcile_pause(p_job_id bigint, p_payload jsonb, p_run_at timestamptz, p_note text)
returns void
language sql
volatile
set search_path = ''
as $$
  update private.jobs
     set status = 'pending', payload = p_payload, run_at = p_run_at, attempts = 0, locked_at = null,
         last_error = p_note, updated_at = clock_timestamp()
   where id = p_job_id;
$$;

-- รอบวันของเพดาน B2 = 00:00 UTC (07:00 น. ไทย) — ทำต่อหลังขึ้นวันใหม่ 10 นาที
create function private.b2_next_day()
returns timestamptz
language sql
volatile
set search_path = ''
as $$
  select (((clock_timestamp() at time zone 'UTC')::date + 1)::timestamp + interval '10 minutes') at time zone 'UTC'
$$;

-- เริ่มรอบ: ล็อกงาน (running ของผู้เรียก) แล้วบอกจำนวนหน้าที่ขอได้ในรอบนี้ = min(เพดานต่อรอบ, งบที่เหลือของวัน)
-- ผล: { action: 'list', allow, key_marker, version_id_marker } | { action: 'paused' } (งบวันนี้หมด) | { action: 'skip' }
create function public.storage_reconcile_start(p_job_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
  v_settings public.storage_settings;
  v_used bigint;
  v_allow integer;
  v_payload jsonb;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null or v_job.kind <> 'storage_reconcile' then
    return jsonb_build_object('action', 'skip');
  end if;
  select s.* into v_settings from public.storage_settings s where s.singleton;
  select coalesce(sum(u.class_c_requests), 0) into v_used
    from public.b2_daily_usage u
   where u.day = (clock_timestamp() at time zone 'UTC')::date and u.source = 'reconcile';
  v_allow := least(v_settings.reconcile_run_max_requests,
                   v_settings.reconcile_daily_budget_requests - v_used)::integer;
  v_payload := v_job.payload;
  if not (v_payload ? 'started_at') then
    v_payload := jsonb_build_object(
      'started_at', clock_timestamp(), 'requests', 0, 'runs', 0, 'key_marker', null, 'version_id_marker', null,
      'tally', jsonb_build_object(
        'bytes', 0, 'versions', 0, 'files_bytes', 0, 'files_versions', 0, 'staging_bytes', 0,
        'staging_versions', 0, 'other_bytes', 0, 'other_versions', 0, 'noncurrent_bytes', 0,
        'noncurrent_versions', 0, 'unknown_bytes', 0, 'unknown_versions', 0, 'delete_markers', 0));
  end if;
  if v_allow <= 0 then
    perform private.storage_reconcile_pause(p_job_id, v_payload, private.b2_next_day(), 'paused: daily_budget');
    return jsonb_build_object('action', 'paused', 'reason', 'daily_budget');
  end if;
  v_payload := jsonb_set(v_payload, '{runs}', to_jsonb((v_payload ->> 'runs')::integer + 1));
  update private.jobs set payload = v_payload, updated_at = clock_timestamp() where id = p_job_id;
  return jsonb_build_object('action', 'list', 'allow', v_allow,
                            'key_marker', v_payload -> 'key_marker',
                            'version_id_marker', v_payload -> 'version_id_marker');
end
$$;

-- ผลหนึ่งหน้า (นับคำขอ Class C 1 ครั้งเสมอ ทั้งสำเร็จและล้ม)
--   p_page = { ok: true, versions: [{ k, v, s, l }], delete_markers, truncated, next_key_marker, next_version_id_marker }
--          | { ok: false, error, cap: bool }
--   p_more = ตัวทำงานยังขอหน้าถัดไปในรอบนี้ได้ (ยังไม่ครบ allow และยังมีเวลา)
-- ผล: { action: 'list', key_marker, version_id_marker } ขอหน้าถัดไป | 'later' พักไว้รอบหน้า | 'paused' ครบเพดาน B2
--     | 'failed' (jobs_fail ลองใหม่ตามรอบ) | 'done' (บันทึกผลแล้ว) | 'skip'
create function public.storage_reconcile_step(p_job_id bigint, p_page jsonb, p_more boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
  v_settings public.storage_settings;
  v_payload jsonb;
  v_tally jsonb;
  v_page jsonb;
  v_assets bigint;
  v_reserved bigint;
  v_b2 bigint;
  v_diff bigint;
  v_offset bigint;
  v_exceeds boolean;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null or v_job.kind <> 'storage_reconcile' or not (v_job.payload ? 'started_at') then
    return jsonb_build_object('action', 'skip');
  end if;
  if p_page is null or jsonb_typeof(p_page) <> 'object' or p_more is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  insert into public.b2_daily_usage as u (day, source, class_c_requests)
  values ((clock_timestamp() at time zone 'UTC')::date, 'reconcile', 1)
  on conflict (day, source) do update
    set class_c_requests = u.class_c_requests + 1, updated_at = clock_timestamp();
  v_payload := jsonb_set(v_job.payload, '{requests}', to_jsonb((v_job.payload ->> 'requests')::integer + 1));

  if (p_page ->> 'ok')::boolean is not true then
    if (p_page ->> 'cap')::boolean is true then
      perform private.storage_reconcile_pause(p_job_id, v_payload, private.b2_next_day(), 'paused: b2_cap');
      return jsonb_build_object('action', 'paused', 'reason', 'b2_cap');
    end if;
    update private.jobs set payload = v_payload where id = p_job_id;
    perform public.jobs_fail(p_job_id, coalesce(left(p_page ->> 'error', 100), 'b2_error'));
    return jsonb_build_object('action', 'failed');
  end if;
  if jsonb_typeof(p_page -> 'versions') is distinct from 'array' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  -- รวมยอดของหน้านี้: แยกตาม prefix · เวอร์ชันไม่ล่าสุด · files/ ที่ไม่ตรงกับ asset ใด (key + version)
  select jsonb_build_object(
           'bytes', coalesce(sum(x.s), 0), 'versions', count(*),
           'files_bytes', coalesce(sum(x.s) filter (where x.k like 'files/%'), 0),
           'files_versions', count(*) filter (where x.k like 'files/%'),
           'staging_bytes', coalesce(sum(x.s) filter (where x.k like 'staging/%'), 0),
           'staging_versions', count(*) filter (where x.k like 'staging/%'),
           'other_bytes', coalesce(sum(x.s) filter (where x.k not like 'files/%' and x.k not like 'staging/%'), 0),
           'other_versions', count(*) filter (where x.k not like 'files/%' and x.k not like 'staging/%'),
           'noncurrent_bytes', coalesce(sum(x.s) filter (where not x.l), 0),
           'noncurrent_versions', count(*) filter (where not x.l),
           'unknown_bytes', coalesce(sum(x.s) filter (where x.k like 'files/%' and not exists (
                              select 1 from public.assets a where a.final_key = x.k and a.version_id = x.v)), 0),
           'unknown_versions', count(*) filter (where x.k like 'files/%' and not exists (
                              select 1 from public.assets a where a.final_key = x.k and a.version_id = x.v)),
           'delete_markers', greatest(coalesce((p_page ->> 'delete_markers')::integer, 0), 0))
    into v_page
    from jsonb_to_recordset(p_page -> 'versions') as x(k text, v text, s bigint, l boolean);
  if exists (select 1 from jsonb_to_recordset(p_page -> 'versions') as x(k text, v text, s bigint, l boolean)
              where x.k is null or x.s is null or x.s < 0 or x.l is null) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select jsonb_object_agg(t.key, to_jsonb((t.value)::bigint + coalesce((v_page ->> t.key)::bigint, 0)))
    into v_tally
    from jsonb_each_text(v_payload -> 'tally') t;
  v_payload := jsonb_set(v_payload, '{tally}', v_tally);

  if (p_page ->> 'truncated')::boolean is true then
    if coalesce(p_page ->> 'next_key_marker', '') = '' then
      raise exception using errcode = 'P0001', message = 'invalid_request';
    end if;
    v_payload := v_payload || jsonb_build_object('key_marker', p_page -> 'next_key_marker',
                                                 'version_id_marker', p_page -> 'next_version_id_marker');
    if p_more then
      update private.jobs set payload = v_payload, locked_at = clock_timestamp(), updated_at = clock_timestamp()
       where id = p_job_id;
      return jsonb_build_object('action', 'list', 'key_marker', v_payload -> 'key_marker',
                                'version_id_marker', v_payload -> 'version_id_marker');
    end if;
    perform private.storage_reconcile_pause(p_job_id, v_payload, clock_timestamp(), 'continue');
    return jsonb_build_object('action', 'later');
  end if;

  -- หน้าสุดท้าย: เทียบกับยอดที่ระบบนับตอนนี้ (ล็อกแถวตั้งค่าเหมือน reserve_storage — ไม่ชนกับการจองที่กำลังนับ)
  select s.* into v_settings from public.storage_settings s where s.singleton for update;
  select coalesce(sum(a.size_bytes), 0) into v_assets from public.assets a;
  v_reserved := private.storage_used_bytes() - v_settings.storage_offset_bytes - v_assets;
  v_b2 := (v_tally ->> 'bytes')::bigint;
  v_diff := v_b2 - (v_assets + v_reserved);
  v_offset := greatest(v_diff, 0);
  v_exceeds := abs(v_diff) >= v_settings.reconcile_warn_bytes
               or abs(v_diff) * 100 >= v_settings.reconcile_warn_pct * greatest(v_b2, v_assets + v_reserved, 1);
  update public.storage_settings
     set storage_offset_bytes = v_offset, reconciled_at = clock_timestamp(), updated_at = clock_timestamp()
   where singleton;
  insert into public.storage_reconciliations (
    job_id, started_at, b2_bytes, b2_versions, breakdown, db_assets_bytes, db_reserved_bytes, diff_bytes,
    offset_before_bytes, offset_after_bytes, exceeds_threshold, requests, runs)
  values (
    p_job_id, (v_payload ->> 'started_at')::timestamptz, v_b2, (v_tally ->> 'versions')::integer,
    v_tally - 'bytes' - 'versions', v_assets, v_reserved, v_diff,
    v_settings.storage_offset_bytes, v_offset, v_exceeds,
    (v_payload ->> 'requests')::integer, (v_payload ->> 'runs')::integer);
  update private.jobs set payload = v_payload where id = p_job_id;
  perform public.jobs_complete(p_job_id, format('diff %s offset %s requests %s', v_diff, v_offset,
                                                v_payload ->> 'requests'));
  return jsonb_build_object('action', 'done', 'b2_bytes', v_b2, 'diff_bytes', v_diff, 'offset_bytes', v_offset,
                            'exceeds_threshold', v_exceeds, 'requests', (v_payload ->> 'requests')::integer);
end
$$;

revoke all on function private.storage_reconcile_pause(bigint, jsonb, timestamptz, text),
  private.b2_next_day() from public, anon, authenticated;
revoke all on function public.storage_reconcile_start(bigint), public.storage_reconcile_step(bigint, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.storage_reconcile_start(bigint), public.storage_reconcile_step(bigint, jsonb, boolean)
  to service_role;
