-- 0055_retention_data: หมวด data ของภาคเรียนเก่า — คะแนน เวลาส่ง และความคิดเห็นสำหรับ CSV (P6-05a2)
-- อ้างอิง: SYSTEM_SPEC ข้อ 62, J9.2, J9.3; TECHNICAL_DESIGN 10 (CSV คะแนนสร้างจากข้อมูลในฐานข้อมูล), 12; 0054_retention
-- หลัก:
--   - หนึ่งแถวต่อ (งาน, นักเรียน) ของงาน (homework) ในห้องของภาคเรียน เมื่อนักเรียนเป็นสมาชิกห้องตอนนี้ หรือมีงานส่ง
--     หรือมีความคิดเห็นในงานนั้น (สมาชิกที่ยังไม่ส่งได้แถว “ยังไม่ส่ง” เหมือนตารางคะแนน) — ประกาศไม่มีคะแนน ไม่นับ
--   - ความคิดเห็นรวมเป็นรายการในแถวของคู่นั้น เรียงตามเวลา; ที่ยกเลิกแล้วส่งแค่ว่าใครเขียนเมื่อไรและถูกยกเลิก
--     ไม่ส่งเนื้อข้อความ (ตารางเก็บ body = null อยู่แล้ว ที่นี่บังคับซ้ำ)
--   - snapshot ของหมวด: count = จำนวนแถว, bytes = 0 (ไม่มีไฟล์ — หน้าเว็บส่ง 0), fingerprint = md5 ของทุกแถวเรียงตาม
--     (งาน, นักเรียน) — ครูแก้คะแนน/เขียนหรือยกเลิกความคิดเห็น/เปลี่ยนชื่องานหลังดาวน์โหลด → ต้องดาวน์โหลดใหม่
--   - ยืนยันลบคะแนนได้เมื่อครบ 1 ปี ไม่มีไฟล์ของภาคเรียนเหลือ และดาวน์โหลดชุดปัจจุบันแล้ว — ภาคเรียนที่ไม่มีแถวเลย
--     (ไม่มีงาน) ไม่ต้องดาวน์โหลดก่อน
-- รหัสเดิม: invalid_request, rate_limited, forbidden, admin_mode_required, account_required

-- ---------------------------------------------------------------------------
-- 1. ค่าตั้ง (0054 + ช่องใหม่)
-- ---------------------------------------------------------------------------
create or replace function private.retention_limits()
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
    'page_rate_window_minutes', 10,
    'data_rate_limit', 30,            -- ข้อมูลคะแนนทั้งภาคเรียน 30 ครั้งต่อ 10 นาทีต่อบัญชี
    'data_rate_window_minutes', 10)
$$;

-- ---------------------------------------------------------------------------
-- 2. แถวของหมวด data — ใช้ภายใน ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
-- graded_current: null = ยังไม่ส่ง · false = รอตรวจ (ยังไม่ตรวจหรือส่งแก้หลังตรวจ) · true = ตรวจฉบับล่าสุดแล้ว
-- คะแนนเป็นผลตรวจล่าสุดที่บันทึกไว้ (ส่งแก้หลังตรวจยังเห็นคะแนนเดิมพร้อม graded_current = false)
-- comments: [{ id, author ('teacher' | 'student'), created_at, retracted, body (null เมื่อยกเลิก) }]
create function private.retention_data_rows(p_term_id uuid)
returns table (
  classroom_id uuid,
  classroom_name text,
  post_id uuid,
  post_title text,
  post_version integer,
  published_at timestamptz,
  full_score integer,
  due_at timestamptz,
  student_id uuid,
  student_code text,
  display_name text,
  group_name text,
  roll_number integer,
  member boolean,
  submission_id uuid,
  first_submitted_at timestamptz,
  last_submitted_at timestamptz,
  content_revision integer,
  graded_current boolean,
  raw_score integer,
  passed boolean,
  timing text,
  applied_penalty_pct integer,
  net_score integer,
  graded_at timestamptz,
  grade_version integer,
  comments jsonb
)
language sql
stable
set search_path = ''
as $$
  with hw as (
    select p.id, p.title, p.version, p.published_at, a.full_score, a.due_at, c.id as classroom_id, c.name as classroom_name
      from public.posts p
      join public.assignments a on a.post_id = p.id
      join public.classrooms c on c.id = p.classroom_id
     where c.term_id = p_term_id
  ),
  pairs as (
    select hw.id as post_id, m.student_id from hw join public.memberships m on m.classroom_id = hw.classroom_id
    union
    select s.assignment_id, s.student_id from public.submissions s join hw on hw.id = s.assignment_id
    union
    select k.assignment_id, k.student_id from public.comments k join hw on hw.id = k.assignment_id
  )
  select hw.classroom_id, hw.classroom_name, hw.id, hw.title, hw.version, hw.published_at, hw.full_score, hw.due_at,
         st.id, st.student_code, st.display_name, re.group_name, re.roll_number,
         exists (select 1 from public.memberships m where m.classroom_id = hw.classroom_id and m.student_id = st.id),
         s.id, s.first_submitted_at, s.last_submitted_at, s.content_revision,
         case when s.id is not null then private.submission_latest_graded(s.id) end,
         g.raw_score, g.passed, g.timing, g.applied_penalty_pct, g.net_score, g.graded_at, g.version,
         cm.comments
    from pairs x
    join hw on hw.id = x.post_id
    join public.students st on st.id = x.student_id
    left join public.roster_entries re on re.term_id = p_term_id and re.student_id = st.id
    left join public.submissions s on s.assignment_id = x.post_id and s.student_id = x.student_id
    left join public.grades g on g.submission_id = s.id
    cross join lateral (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', k.id,
               'author', case when ac.role = 'student' then 'student' else 'teacher' end,
               'created_at', k.created_at,
               'retracted', k.retracted_at is not null,
               'body', case when k.retracted_at is null then k.body end) order by k.created_at, k.id), '[]'::jsonb)
             as comments
        from public.comments k
        left join public.accounts ac on ac.id = k.author_account_id
       where k.assignment_id = x.post_id and k.student_id = x.student_id) cm
$$;

-- { count, bytes (0), fingerprint } — fingerprint จากทุกคอลัมน์ของทุกแถว (เวลาเป็น UTC ไม่ขึ้นกับ TimeZone ของ session)
create or replace function private.retention_data_snapshot(p_term_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'count', count(*)::integer,
    'bytes', 0,
    'fingerprint', md5(coalesce(string_agg(concat_ws('|',
        r.classroom_id, r.classroom_name, r.post_id, r.post_title, r.post_version,
        extract(epoch from r.published_at), r.full_score, extract(epoch from r.due_at),
        r.student_id, r.student_code, r.display_name, r.group_name, r.roll_number, r.member,
        r.submission_id, extract(epoch from r.first_submitted_at), extract(epoch from r.last_submitted_at),
        r.content_revision, r.graded_current, r.raw_score, r.passed, r.timing, r.applied_penalty_pct, r.net_score,
        extract(epoch from r.graded_at), r.grade_version,
        (select string_agg(concat_ws('/', c ->> 'id', c ->> 'author', extract(epoch from (c ->> 'created_at')::timestamptz),
                                     c ->> 'retracted', md5(coalesce(c ->> 'body', ''))), ';' order by o)
           from jsonb_array_elements(r.comments) with ordinality e(c, o))),
      ',' order by r.post_id, r.student_id), '')))
    from private.retention_data_rows(p_term_id) r
$$;

-- ---------------------------------------------------------------------------
-- 3. สถานะ (0054) — หมวด data เพิ่ม count และยืนยันได้โดยไม่ต้องดาวน์โหลดเมื่อไม่มีแถว
-- ---------------------------------------------------------------------------
create or replace function private.retention_status(p_term public.terms)
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
  v_data_dl := (v_data ->> 'count')::integer > 0
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
      'count', (v_data ->> 'count')::integer,
      'downloaded', v_data_dl,
      'downloaded_at', v_rd.downloaded_at,
      'download_stale', v_rd.downloaded_at is not null and not v_data_dl,
      'confirmed_at', v_rd.confirmed_at,
      'deleted_at', v_rd.deleted_at,
      'files_cleared', v_cleared,
      'can_confirm', v_now >= v_data_due and v_cleared and v_rd.confirmed_at is null
                     and (v_data_dl or (v_data ->> 'count')::integer = 0)));
end
$$;

-- ---------------------------------------------------------------------------
-- 4. ข้อมูลคะแนนทั้งภาคเรียนสำหรับ CSV (หน้าเว็บสร้าง CSV เอง แล้วเรียก export_mark_downloaded หมวด data)
-- ---------------------------------------------------------------------------
-- ผล: { term_id, term_name, fingerprint, count, bytes (0),
--       rows: [{ classroom_name, post_id, post_title, full_score, due_at, student_code, display_name, group_name,
--                roll_number, member, first_submitted_at, last_submitted_at, content_revision, graded_current,
--                raw_score, passed, timing, applied_penalty_pct, net_score, graded_at, comments }] }
-- เรียงตาม ห้อง → เวลาโพสต์งาน → เลขที่ (ไม่มีในรายชื่อไว้ท้าย) → รหัสนักเรียน
create function public.export_term_data(p_term_id uuid, p_admin_mode boolean default false)
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
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_term_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  select t.* into v_term from public.terms t where t.id = p_term_id;
  if v_term.id is null or private.term_retention_from(v_term) is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  perform private.rate_limit_hit(v_account.id, 'export_data', (v_limits ->> 'data_rate_limit')::integer,
                                 make_interval(mins => (v_limits ->> 'data_rate_window_minutes')::integer));

  v_snapshot := private.retention_data_snapshot(p_term_id);
  return jsonb_build_object(
    'term_id', v_term.id,
    'term_name', v_term.name,
    'fingerprint', v_snapshot ->> 'fingerprint',
    'count', (v_snapshot ->> 'count')::integer,
    'bytes', 0,
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'classroom_name', r.classroom_name,
               'post_id', r.post_id,
               'post_title', r.post_title,
               'full_score', r.full_score,
               'due_at', r.due_at,
               'student_code', r.student_code,
               'display_name', r.display_name,
               'group_name', r.group_name,
               'roll_number', r.roll_number,
               'member', r.member,
               'first_submitted_at', r.first_submitted_at,
               'last_submitted_at', r.last_submitted_at,
               'content_revision', r.content_revision,
               'graded_current', r.graded_current,
               'raw_score', r.raw_score,
               'passed', r.passed,
               'timing', r.timing,
               'applied_penalty_pct', r.applied_penalty_pct,
               'net_score', r.net_score,
               'graded_at', r.graded_at,
               'comments', (select coalesce(jsonb_agg(c - 'id' order by o), '[]'::jsonb)
                              from jsonb_array_elements(r.comments) with ordinality e(c, o)))
             order by r.classroom_name, r.classroom_id, r.published_at, r.post_id,
                      r.roll_number nulls last, r.student_code)
        from private.retention_data_rows(p_term_id) r), '[]'::jsonb));
end
$$;
revoke all on function public.export_term_data(uuid, boolean) from public, anon;
grant execute on function public.export_term_data(uuid, boolean) to authenticated;
