-- 0054_retention: สถานะเก็บข้อมูลตามอายุของภาคเรียนเก่า + รายการไฟล์สำหรับ ZIP + บันทึกว่าดาวน์โหลดครบแล้ว (P6-05a1)
-- อ้างอิง: SYSTEM_SPEC ข้อ 55, 62, J9.2, J10.4; TECHNICAL_DESIGN 2 (retention_requests), 10 (POST /exports), 12;
--          TECHNICAL_BUILD_PLAN 4.2 แถว 12; UX_DESIGN T07 + แบบ v2 retRow
-- หลัก:
--   - ภาคเรียนเก่า = ภาคเรียนที่มีจุดเริ่มนับอายุ (ended_at ถ้ากดจบ ไม่งั้น superseded_at — 0042) แบ่ง 2 หมวด
--     files (ไฟล์โจทย์ งานนักเรียน เฉลย: +60 วัน) และ data (คะแนน เวลาส่ง ความคิดเห็น: +1 ปี)
--   - ครบอายุ = “เสนอให้ลบ” ที่คำนวณตอนอ่าน (ไม่มีงานตั้งเวลา ไม่ลบเอง ไม่แจ้งเตือน) — ลบจริงต้องดาวน์โหลดแล้วและครู
--     ยืนยัน (confirm-delete ใน P6-05b)
--   - “ดาวน์โหลดแล้ว” = หน้าเว็บของครูรายงานว่าได้ไฟล์ครบ: จำนวน ไบต์ และ fingerprint ของชุดไฟล์ต้องตรงกับชุดปัจจุบัน
--     ตอนบันทึก ถ้าชุดไฟล์เปลี่ยนภายหลัง (เช่นครูแนบเฉลยเพิ่มในภาคเรียนที่กดจบ) สถานะกลับเป็นยังไม่ได้ดาวน์โหลด
--     (download_stale) และปุ่มยืนยันลบใช้ไม่ได้จนดาวน์โหลดใหม่
--   - ไฟล์ของภาคเรียน = asset ที่ผูกกับโพสต์/เฉลย/งานส่งของห้องในภาคเรียนนั้น (รูปเครื่องรางไม่ผูกภาคเรียน ไม่นับ;
--     ไฟล์ที่ไม่ผูกที่ใดถูกล้างตามกฎไฟล์กำพร้า 0023)
--   - ภาคเรียนใช้ร่วมทุกห้อง (1.2) จึงนับทุกห้องของภาคเรียนเหมือน term_overview (0042)
--   - หมวด data: fingerprint/รายการสำหรับ CSV มากับ P6-05a2 — ตอนนี้ downloaded = false เสมอ
-- รหัสใหม่: export_mismatch (จำนวน/ไบต์/ชุดไฟล์ไม่ตรงตอนบันทึกว่าดาวน์โหลดแล้ว) — ต้องเพิ่มแถวในตาราง UX 7.1
-- รหัสเดิม: invalid_request, rate_limited, forbidden, admin_mode_required, account_required

-- ---------------------------------------------------------------------------
-- 1. ค่าตั้ง [ค่าที่ Claude เลือก — ปรับได้ในไฟล์นี้]
-- ---------------------------------------------------------------------------
create function private.retention_limits()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'files_keep', '60 days',          -- ข้อ 55 / J9.2
    'data_keep', '1 year',            -- ข้อ 62 / J9.2
    'page_max', 20,                   -- เท่ากับ files_sign_limits().max_files (Edge Function ลงลายเซ็นทั้งหน้าในคำขอเดียว)
    'page_rate_limit', 600,           -- หน้ารายการไฟล์ 600 หน้าต่อ 10 นาทีต่อบัญชี (≈ 12,000 ไฟล์)
    'page_rate_window_minutes', 10)
$$;

-- ---------------------------------------------------------------------------
-- 2. ตาราง
-- ---------------------------------------------------------------------------
-- หนึ่งแถวต่อ (ภาคเรียน, หมวด) เกิดเมื่อครูดาวน์โหลดครบครั้งแรก — ไม่มีแถว = ยังไม่เคยดาวน์โหลด
-- เขียนผ่าน RPC เท่านั้น: RLS เปิด ไม่มี policy ไม่ GRANT ตาราง (หน้าเว็บอ่านสถานะผ่าน term_overview)
create table public.retention_requests (
  term_id uuid not null references public.terms (id),
  scope text not null check (scope in ('files', 'data')),
  -- ชุดที่ดาวน์โหลดครบล่าสุด (ทับเมื่อดาวน์โหลดใหม่)
  downloaded_at timestamptz not null,
  downloaded_by_account_id uuid references public.accounts (id) on delete set null,
  downloaded_count integer not null check (downloaded_count >= 0),
  downloaded_bytes bigint not null check (downloaded_bytes >= 0),
  downloaded_fingerprint text not null check (downloaded_fingerprint ~ '^[0-9a-f]{32}$'),
  -- ครูยืนยันลบ / ลบเสร็จ — P6-05b เป็นผู้ตั้ง
  confirmed_at timestamptz,
  confirmed_by_account_id uuid references public.accounts (id) on delete set null,
  confirmed_early boolean,
  deleted_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (term_id, scope),
  check ((confirmed_at is null) = (confirmed_early is null)),
  check (deleted_at is null or confirmed_at is not null),
  -- ลบก่อนครบอายุได้เฉพาะไฟล์ (J10.4) — คะแนนและความคิดเห็นต้องครบ 1 ปี
  check (scope = 'files' or confirmed_early is not true)
);
create index retention_requests_downloaded_by_account_id_idx on public.retention_requests (downloaded_by_account_id);
create index retention_requests_confirmed_by_account_id_idx on public.retention_requests (confirmed_by_account_id);

alter table public.retention_requests enable row level security;

-- ---------------------------------------------------------------------------
-- 3. ชุดไฟล์ของภาคเรียน — ใช้ภายใน ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
-- จุดเริ่มนับอายุ (null = ภาคเรียนที่ยังเปิด ยังไม่นับ)
create function private.term_retention_from(p_term public.terms)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_term.ended_at, p_term.superseded_at)
$$;

-- asset ที่ผูกกับโพสต์/เฉลย/งานส่งของห้องในภาคเรียน (เฉลยผูกด้วย solution_id = post id ของงาน)
create function private.retention_files(p_term_id uuid)
returns table (asset_id uuid, size_bytes bigint, attachment_id uuid, post_id uuid, submission_id uuid)
language sql
stable
set search_path = ''
as $$
  select a.id, a.size_bytes, t.id, p.id, t.submission_id
    from public.attachments t
    join public.assets a on a.id = t.asset_id and a.status = 'ready'
    left join public.submissions s on s.id = t.submission_id
    join public.posts p on p.id = coalesce(t.post_id, t.solution_id, s.assignment_id)
    join public.classrooms c on c.id = p.classroom_id
   where c.term_id = p_term_id
$$;

-- { count, bytes, fingerprint } ของชุดไฟล์ตอนนี้ — fingerprint = md5 ของ "asset_id:ขนาด" เรียงตาม id
-- (ชุดว่าง = md5 ของสตริงว่าง) ใช้เทียบว่าชุดที่ดาวน์โหลดยังเป็นชุดปัจจุบัน
create function private.retention_files_snapshot(p_term_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'count', count(*)::integer,
    'bytes', coalesce(sum(f.size_bytes), 0)::bigint,
    'fingerprint', md5(coalesce(string_agg(f.asset_id::text || ':' || f.size_bytes, ',' order by f.asset_id), '')))
    from private.retention_files(p_term_id) f
$$;

-- หมวด data: เติมใน P6-05a2 (รายการคะแนน/เวลาส่ง/ความคิดเห็นสำหรับ CSV) — null = ยังดาวน์โหลดไม่ได้
create function private.retention_data_snapshot(p_term_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select null::jsonb where p_term_id is not null
$$;

-- ---------------------------------------------------------------------------
-- 4. สถานะต่อภาคเรียนเก่า (T07) — ใช้ใน term_overview
-- ---------------------------------------------------------------------------
-- ผล: { files: { due_at, expired, count, bytes, downloaded, downloaded_at, download_stale, confirmed_at, deleted_at,
--                can_confirm, early },
--       data:  { due_at, expired, downloaded, downloaded_at, download_stale, confirmed_at, deleted_at,
--                files_cleared, can_confirm } }
--   downloaded     = ชุดที่ดาวน์โหลดครบล่าสุดตรงกับชุดตอนนี้ (ชุดว่างไม่ต้องดาวน์โหลด = false)
--   download_stale = เคยดาวน์โหลดแต่ชุดเปลี่ยนไปแล้ว → ต้องดาวน์โหลดใหม่
--   can_confirm    = ปุ่มยืนยันลบกดได้: files — ดาวน์โหลดแล้วและยังไม่ยืนยัน (ก่อนครบ 60 วันได้ = early, J10.4);
--                    data — ครบ 1 ปี ดาวน์โหลดแล้ว ยังไม่ยืนยัน และไม่มีไฟล์ของภาคเรียนเหลือ (files_cleared —
--                    ลบงานส่งก่อนไฟล์จะทิ้ง asset ให้ตัวล้างไฟล์กำพร้าลบโดยครูไม่ได้ยืนยัน)
create function private.retention_status(p_term public.terms)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_limits jsonb := private.retention_limits();
  v_from timestamptz := private.term_retention_from(p_term);
  v_files jsonb := private.retention_files_snapshot(p_term.id);
  v_data jsonb := private.retention_data_snapshot(p_term.id);
  v_rf public.retention_requests;
  v_rd public.retention_requests;
  v_files_due timestamptz;
  v_data_due timestamptz;
  v_files_dl boolean;
  v_data_dl boolean;
  v_cleared boolean;
begin
  if v_from is null then
    return null;
  end if;
  v_files_due := v_from + (v_limits ->> 'files_keep')::interval;
  v_data_due := v_from + (v_limits ->> 'data_keep')::interval;
  select r.* into v_rf from public.retention_requests r where r.term_id = p_term.id and r.scope = 'files';
  select r.* into v_rd from public.retention_requests r where r.term_id = p_term.id and r.scope = 'data';

  v_files_dl := (v_files ->> 'count')::integer > 0
                and v_rf.downloaded_fingerprint is not distinct from v_files ->> 'fingerprint'
                and v_rf.downloaded_count is not distinct from (v_files ->> 'count')::integer
                and v_rf.downloaded_bytes is not distinct from (v_files ->> 'bytes')::bigint;
  v_data_dl := v_data is not null and (v_data ->> 'count')::integer > 0
               and v_rd.downloaded_fingerprint is not distinct from v_data ->> 'fingerprint'
               and v_rd.downloaded_count is not distinct from (v_data ->> 'count')::integer
               and v_rd.downloaded_bytes is not distinct from (v_data ->> 'bytes')::bigint;
  v_cleared := (v_files ->> 'count')::integer = 0;

  return jsonb_build_object(
    'files', jsonb_build_object(
      'due_at', v_files_due,
      'expired', v_now >= v_files_due,
      'count', (v_files ->> 'count')::integer,
      'bytes', (v_files ->> 'bytes')::bigint,
      'downloaded', v_files_dl,
      'downloaded_at', v_rf.downloaded_at,
      'download_stale', v_rf.downloaded_at is not null and not v_files_dl,
      'confirmed_at', v_rf.confirmed_at,
      'deleted_at', v_rf.deleted_at,
      'can_confirm', v_files_dl and v_rf.confirmed_at is null,
      'early', v_now < v_files_due),
    'data', jsonb_build_object(
      'due_at', v_data_due,
      'expired', v_now >= v_data_due,
      'downloaded', v_data_dl,
      'downloaded_at', v_rd.downloaded_at,
      'download_stale', v_rd.downloaded_at is not null and not v_data_dl,
      'confirmed_at', v_rd.confirmed_at,
      'deleted_at', v_rd.deleted_at,
      'files_cleared', v_cleared,
      'can_confirm', v_now >= v_data_due and v_data_dl and v_cleared and v_rd.confirmed_at is null));
end
$$;

-- term_overview (0042) + สถานะเก็บข้อมูลของแต่ละภาคเรียนเก่า: old_terms[].files / old_terms[].data
-- (คีย์เดิมคงไว้ทั้งหมด: files_due/data_due เท่ากับ files.due_at/data.due_at)
create or replace function public.term_overview(p_admin_mode boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_term_id uuid;
begin
  perform private.require_teacher(p_admin_mode);
  select c.term_id into v_term_id from public.term_control c where c.singleton;
  if v_term_id is null then
    raise exception using errcode = 'P0001', message = 'no_term';
  end if;

  return jsonb_build_object(
    'term', private.term_state(),
    'classrooms', (select count(*)::integer from public.classrooms c where c.term_id = v_term_id),
    'students', (select count(distinct m.student_id)::integer
                   from public.memberships m join public.classrooms c on c.id = m.classroom_id
                  where c.term_id = v_term_id),
    'tokens', (select coalesce(sum(w.balance), 0)::integer from public.wallets w where w.term_id = v_term_id),
    'waiting', (select count(*)::integer
                  from public.submissions s
                  join public.posts p on p.id = s.assignment_id
                  join public.classrooms c on c.id = p.classroom_id
                 where c.term_id = v_term_id and not private.submission_latest_graded(s.id)),
    'old_terms', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id,
               'name', t.name,
               'how', case when t.ended_at is not null then 'end' else 'start' end,
               'retention_from', r.from_at,
               'files_due', st -> 'files' -> 'due_at',
               'data_due', st -> 'data' -> 'due_at',
               'files', st -> 'files',
               'data', st -> 'data') order by r.from_at desc, t.id)
        from public.terms t
        cross join lateral (select private.term_retention_from(t) as from_at) r
        cross join lateral (select private.retention_status(t) as st) s
       where r.from_at is not null), '[]'::jsonb));
end
$$;

-- ---------------------------------------------------------------------------
-- 5. รายการไฟล์สำหรับ ZIP (POST /exports — Edge Function `files` เรียกในนามผู้ใช้ แล้วลงลายเซ็นด้วย files_sign_begin)
-- ---------------------------------------------------------------------------
-- p_after: asset_id สุดท้ายของหน้าก่อน (null = หน้าแรก) — เรียงตาม asset_id ทุกหน้าคืน fingerprint/ยอดรวมของชุด
-- ตอนนี้ ให้หน้าเว็บหยุดเมื่อชุดเปลี่ยนระหว่างดาวน์โหลด และส่ง fingerprint ของหน้าแรกกลับมาตอนบันทึกว่าครบ
-- ผล: { term_id, fingerprint, total_count, total_bytes, next_after (null = หน้าสุดท้าย),
--       files: [{ asset_id, file_name, content_type, size_bytes, purpose ('post' | 'solution' | 'submission'),
--                 position, classroom_id, classroom_name, post_id, post_kind, post_title,
--                 student: null | { student_id, student_code, display_name, group_name, roll_number } }] }
-- ไม่มี key/version ของ B2 (อยู่ใน files_sign_begin ที่เรียกได้เฉพาะ service_role)
create function public.export_files_page(
  p_term_id uuid,
  p_after uuid default null,
  p_limit integer default 20,
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
  v_limits jsonb := private.retention_limits();
  v_term public.terms;
  v_snapshot jsonb;
  v_files jsonb;
  v_last uuid;
  v_more boolean;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_term_id is null or p_limit is null or p_limit not between 1 and (v_limits ->> 'page_max')::integer then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select t.* into v_term from public.terms t where t.id = p_term_id;
  -- ดาวน์โหลดได้เฉพาะภาคเรียนเก่า (กดจบหรือมีภาคเรียนใหม่ทับแล้ว)
  if v_term.id is null or private.term_retention_from(v_term) is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  perform private.rate_limit_hit(v_account.id, 'export_files', (v_limits ->> 'page_rate_limit')::integer,
                                 make_interval(mins => (v_limits ->> 'page_rate_window_minutes')::integer));

  v_snapshot := private.retention_files_snapshot(p_term_id);
  select jsonb_agg(jsonb_build_object(
           'asset_id', a.id,
           'file_name', a.file_name,
           'content_type', a.content_type,
           'size_bytes', a.size_bytes,
           'purpose', a.purpose,
           'position', t.position,
           'classroom_id', c.id,
           'classroom_name', c.name,
           'post_id', p.id,
           'post_kind', p.kind,
           'post_title', p.title,
           'student', case when st.id is null then null else jsonb_build_object(
                        'student_id', st.id,
                        'student_code', st.student_code,
                        'display_name', st.display_name,
                        'group_name', re.group_name,
                        'roll_number', re.roll_number) end) order by a.id),
         max(a.id::text)::uuid
    into v_files, v_last
    from (select f.asset_id, f.attachment_id, f.post_id, f.submission_id
            from private.retention_files(p_term_id) f
           where p_after is null or f.asset_id > p_after
           order by f.asset_id
           limit p_limit) f
    join public.assets a on a.id = f.asset_id
    join public.attachments t on t.id = f.attachment_id
    join public.posts p on p.id = f.post_id
    join public.classrooms c on c.id = p.classroom_id
    left join public.submissions s on s.id = f.submission_id
    left join public.students st on st.id = s.student_id
    left join public.roster_entries re on re.term_id = p_term_id and re.student_id = st.id;
  v_more := v_last is not null
            and exists (select 1 from private.retention_files(p_term_id) f where f.asset_id > v_last);

  return jsonb_build_object(
    'term_id', p_term_id,
    'fingerprint', v_snapshot ->> 'fingerprint',
    'total_count', (v_snapshot ->> 'count')::integer,
    'total_bytes', (v_snapshot ->> 'bytes')::bigint,
    'next_after', case when v_more then v_last end,
    'files', coalesce(v_files, '[]'::jsonb));
end
$$;
revoke all on function public.export_files_page(uuid, uuid, integer, boolean) from public, anon;
grant execute on function public.export_files_page(uuid, uuid, integer, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. บันทึกว่าดาวน์โหลดครบแล้ว (หน้าเว็บเรียกหลังเขียน ZIP/CSV เสร็จ)
-- ---------------------------------------------------------------------------
-- p_count/p_bytes = ที่หน้าเว็บนับได้จากไฟล์ที่เขียนลง ZIP จริง · p_fingerprint = fingerprint จากหน้าแรก
-- ต้องตรงกับชุดตอนนี้ทั้งสามค่า ไม่งั้น export_mismatch (ชุดเปลี่ยนระหว่างดาวน์โหลด หรือได้ไม่ครบ) — ชุดว่างบันทึกไม่ได้
-- เรียกซ้ำด้วยชุดเดิม = ทับเวลาเดิม (idempotent ไม่ต้องใช้ request key)
-- ผล: retention_status ของภาคเรียนนั้น (หมวดเดียวกับที่บันทึกอยู่ใน files/data)
create function public.export_mark_downloaded(
  p_term_id uuid,
  p_scope text,
  p_fingerprint text,
  p_count integer,
  p_bytes bigint,
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
  v_term public.terms;
  v_snapshot jsonb;
  v_now timestamptz;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_term_id is null or p_scope is null or p_scope not in ('files', 'data')
     or p_fingerprint is null or p_count is null or p_bytes is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select t.* into v_term from public.terms t where t.id = p_term_id;
  if v_term.id is null or private.term_retention_from(v_term) is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_snapshot := case p_scope when 'files' then private.retention_files_snapshot(p_term_id)
                             else private.retention_data_snapshot(p_term_id) end;
  if v_snapshot is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  if (v_snapshot ->> 'count')::integer = 0
     or p_fingerprint <> v_snapshot ->> 'fingerprint'
     or p_count <> (v_snapshot ->> 'count')::integer
     or p_bytes <> (v_snapshot ->> 'bytes')::bigint then
    raise exception using errcode = 'P0001', message = 'export_mismatch';
  end if;

  v_now := clock_timestamp();
  insert into public.retention_requests as r
    (term_id, scope, downloaded_at, downloaded_by_account_id, downloaded_count, downloaded_bytes, downloaded_fingerprint)
  values (p_term_id, p_scope, v_now, v_account.id, p_count, p_bytes, p_fingerprint)
  on conflict (term_id, scope) do update
    set downloaded_at = excluded.downloaded_at,
        downloaded_by_account_id = excluded.downloaded_by_account_id,
        downloaded_count = excluded.downloaded_count,
        downloaded_bytes = excluded.downloaded_bytes,
        downloaded_fingerprint = excluded.downloaded_fingerprint,
        updated_at = excluded.downloaded_at;
  return private.retention_status(v_term);
end
$$;
revoke all on function public.export_mark_downloaded(uuid, text, text, integer, bigint, boolean) from public, anon;
grant execute on function public.export_mark_downloaded(uuid, text, text, integer, bigint, boolean) to authenticated;
