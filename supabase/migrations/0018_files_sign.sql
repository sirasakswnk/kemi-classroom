-- 0018_files_sign: สิทธิ์เปิดไฟล์และงบเปิดดูรายวัน สำหรับ POST /files/sign (Edge Function `files`) — P3-05
-- TECHNICAL_DESIGN 9, 9.2, 9.3 ข้อ 2–3, 10 (/files/sign); TECHNICAL_BUILD_PLAN 5 (files)
--
-- แบ่งสิทธิ์เป็นสองชั้นแบบเดียวกับ 0017:
--   1. authorize_files — เรียกด้วย JWT ของผู้ใช้ (authenticated): คืนเฉพาะ id ที่ผู้ใช้เปิดได้ (ไม่คืน key/เวอร์ชัน/
--      checksum ที่ซ่อนไว้ใน 0011) และนับเพดานครั้งต่อบัญชี (rate_limits)
--   2. files_sign_begin — เรียกได้เฉพาะ service_role: อ่าน final_key/version_id/ชนิด/ขนาด/ชื่อ แล้วตรวจ + นับงบเปิดดู
--      ของวันในขั้นเดียว (ล็อกแถวตัวนับ view ของวันนั้น) — Edge Function ส่งเฉพาะ id ที่ข้อ 1 คืนมา
-- สิทธิ์ตามวัตถุประสงค์ (เหมือน RLS อ่านของ 0010/0011 — ผู้ดูแลอ่านได้โดยไม่ต้องอยู่ในโหมดผู้ดูแล):
--   - ไฟล์โจทย์/ประกาศ = สิทธิ์อ่านโพสต์ (สมาชิกขณะนี้ + ครูเจ้าของห้อง/ผู้ดูแล)
--   - ไฟล์เฉลย = ครูเจ้าของห้อง/ผู้ดูแล และสมาชิกเมื่อเผยแพร่แล้ว (private.can_read_solution)
--   - ไฟล์ที่ยังไม่ผูก = เจ้าของ (ผู้อัปโหลด) เท่านั้น เช่นดูตัวอย่างก่อนโพสต์
--   - ไฟล์งานส่ง (P3-07/P3-08) และรูปเครื่องราง (ระยะ 5) เพิ่มเมื่อมีตารางผูก — ตอนนี้เข้าข้อ "ยังไม่ผูก"
--   - ไฟล์ที่ไม่ ready (copying/deleting) ไม่มีใครเปิดได้
--
-- รหัสที่หน้าเว็บอาจเจอ (Edge Function ส่งต่อ): forbidden, rate_limited, download_budget_reached
-- รหัสภายใน: invalid_request, account_required

-- ---------------------------------------------------------------------------
-- 1. ค่าจำกัด [ค่าที่ Claude เลือก — ปรับได้ในไฟล์นี้]
-- ---------------------------------------------------------------------------
create function private.files_sign_limits()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'max_files', 20,               -- ไฟล์โจทย์ 10 + เฉลย 10 (SYSTEM_SPEC ส่วน 3) ต่อคำขอ
    'rate_limit', 120,             -- ขอลิงก์ได้ 120 ครั้งต่อ 10 นาทีต่อบัญชี
    'rate_window_minutes', 10)
$$;

-- รายการ id ที่หน้าเว็บส่ง: 1..max_files ตัว ไม่มี null — ตัดตัวซ้ำโดยคงลำดับแรกที่พบ
create function private.files_sign_ids(p_asset_ids uuid[])
returns uuid[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if p_asset_ids is null or cardinality(p_asset_ids) < 1 or array_position(p_asset_ids, null) is not null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select array_agg(u.id order by u.first_n) into v_ids
    from (select x.id, min(x.n) as first_n
            from unnest(p_asset_ids) with ordinality x(id, n)
           group by x.id) u;
  if cardinality(v_ids) > (private.files_sign_limits() ->> 'max_files')::integer then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  return v_ids;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. สิทธิ์เปิดไฟล์ (JWT ของผู้ใช้)
-- ---------------------------------------------------------------------------
-- คืน id ที่เปิดได้ตามลำดับที่ขอ — id ที่ไม่มีสิทธิ์และ id ที่ไม่มีอยู่ถูกตัดออกเหมือนกัน (ไม่บอกว่ามีไฟล์นั้นหรือไม่)
-- Edge Function ตอบ forbidden ทั้งชุดถ้าได้ไม่ครบ; นับเพดานครั้งก่อนตรวจ จึงไล่เดา id ได้ไม่เกินเพดาน
create function public.authorize_files(p_asset_ids uuid[])
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
             else false
           end), '{}'::uuid[]);
end
$$;
revoke all on function public.authorize_files(uuid[]) from public, anon;
grant execute on function public.authorize_files(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. ข้อมูลสำหรับลงลายเซ็น + ตรวจและนับงบเปิดดูรายวัน (service_role)
-- ---------------------------------------------------------------------------
-- งบนับต่อไฟล์ที่ออกลิงก์: 1 คำขอ Class B + ขนาดไฟล์เต็ม (เปิดดูและดาวน์โหลดนับเหมือนกัน) ลงแถว view ของวัน UTC
-- ล็อกแถวตัวนับของวันนั้น (FOR UPDATE) ก่อนอ่านยอด — คำขอพร้อมกันรอกันทีละราย จึงผ่านงบรวมกันไม่ได้
-- ครบงบ (ยอด + คำขอนี้ เกินงบไบต์หรือจำนวนคำขอ) → download_budget_reached ไม่นับ ไม่ออกลิงก์ (ทั้งชุด)
-- ไฟล์ไม่ ready แล้ว (เช่นเพิ่งเข้าคิวลบหลังตรวจสิทธิ์) → forbidden
create function public.files_sign_begin(p_asset_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := private.files_sign_ids(p_asset_ids);
  v_files jsonb;
  v_count integer;
  v_bytes bigint;
  v_day date := (clock_timestamp() at time zone 'UTC')::date;
  v_usage public.b2_daily_usage;
  v_settings public.storage_settings;
begin
  select jsonb_agg(jsonb_build_object(
           'id', a.id,
           'final_key', a.final_key,
           'version_id', a.version_id,
           'content_type', a.content_type,
           'size_bytes', a.size_bytes,
           'file_name', a.file_name) order by u.n),
         count(*)::integer,
         coalesce(sum(a.size_bytes), 0)::bigint
    into v_files, v_count, v_bytes
    from unnest(v_ids) with ordinality u(id, n)
    join public.assets a on a.id = u.id and a.status = 'ready';
  if v_count <> cardinality(v_ids) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  insert into public.b2_daily_usage (day, source) values (v_day, 'view') on conflict (day, source) do nothing;
  select u.* into v_usage from public.b2_daily_usage u where u.day = v_day and u.source = 'view' for update;
  select s.* into v_settings from public.storage_settings s where s.singleton;
  if v_usage.class_b_requests + v_count > v_settings.daily_view_budget_requests
     or v_usage.download_bytes + v_bytes > v_settings.daily_view_budget_bytes then
    raise exception using errcode = 'P0001', message = 'download_budget_reached';
  end if;
  update public.b2_daily_usage u
     set class_b_requests = u.class_b_requests + v_count,
         download_bytes = u.download_bytes + v_bytes,
         updated_at = clock_timestamp()
   where u.day = v_day and u.source = 'view';
  return jsonb_build_object('files', v_files);
end
$$;
revoke all on function public.files_sign_begin(uuid[]) from public, anon, authenticated;
grant execute on function public.files_sign_begin(uuid[]) to service_role;
