-- 0003_roster: ภาคเรียน ตัวควบคุมเทอม นักเรียน รายชื่อตามห้อง และ RPC นำเข้ารายชื่อ
-- อ้างอิง: TECHNICAL_DESIGN 2, 4, 7; TECHNICAL_BUILD_PLAN 4.1, 4.2 แถว 3 (ส่วนแรก — classrooms/memberships อยู่ migration ถัดไป)
-- หลัก: หน้าเว็บอ่านไฟล์ Excel เอง ส่งเฉพาะ 5 ช่อง (เลขที่ เลขประจำตัว คำนำหน้า ชื่อ นามสกุล) มาตรวจ/บันทึกที่นี่
--       การนำเข้าไม่ผูกสมาชิกห้อง ไม่ลบคนที่หายจากไฟล์ และไม่แตะการผูกบัญชี (account_id)

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------

-- ภาคเรียน: เริ่มด้วยการกดของครู (ระยะ 5) — เทอมแรกมาจาก seed
create table public.terms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 60),
  status text not null default 'active' check (status in ('active', 'ended', 'superseded')),
  started_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz,
  superseded_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);

-- ตัวควบคุมเทอมแถวเดียวของทั้งระบบ (ใช้ร่วม 3 ห้อง, 1.2) — ล็อกเป็นลำดับแรกเสมอ (BUILD_PLAN 4.1 ข้อ 5)
create table public.term_control (
  singleton boolean primary key default true check (singleton),
  term_id uuid not null references public.terms (id),
  epoch integer not null default 1 check (epoch >= 1),
  status text not null default 'active' check (status in ('active', 'ended')),
  started_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);

-- นักเรียนตามรายชื่อของครู: เลขประจำตัวเป็นข้อความ (เก็บศูนย์นำหน้า), ชื่อ = “ชื่อ นามสกุล” (ส่วน 4)
create table public.students (
  id uuid primary key default gen_random_uuid(),
  student_code text not null unique check (student_code ~ '^[0-9]{1,20}$'),
  name_prefix text check (name_prefix is null or (name_prefix = btrim(name_prefix) and length(name_prefix) between 1 and 30)),
  display_name text not null check (display_name = btrim(display_name) and length(display_name) between 1 and 200),
  account_id uuid unique references public.accounts (id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

-- รายชื่อในแต่ละภาคเรียน: ห้องตามไฟล์ที่ครูเลือกตอนนำเข้า + เลขที่ — ไม่ใช่สมาชิกห้องอัตโนมัติ
-- เลขที่ไม่ซ้ำในห้องเดียวกันแบบตรวจตอนจบ transaction ได้ (นำเข้าซ้ำที่สลับเลขที่กันจะไม่ชนระหว่างทาง)
create table public.roster_entries (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.terms (id),
  student_id uuid not null references public.students (id),
  group_name text not null check (group_name = btrim(group_name) and length(group_name) between 1 and 30),
  roll_number integer not null check (roll_number between 1 and 999),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint roster_entries_term_student_key unique (term_id, student_id),
  constraint roster_entries_group_roll_key unique (term_id, group_name, roll_number)
    deferrable initially immediate
);
create index roster_entries_student_id_idx on public.roster_entries (student_id);

alter table public.terms enable row level security;
alter table public.term_control enable row level security;
alter table public.students enable row level security;
alter table public.roster_entries enable row level security;

-- ---------------------------------------------------------------------------
-- 2. สิทธิ์อ่าน (เขียนผ่าน RPC เท่านั้น)
-- ---------------------------------------------------------------------------

-- ครูหรือผู้ดูแลหรือไม่ — ใช้ใน policy จึงคืน boolean (require_teacher ใช้ใน policy ไม่ได้เพราะ raise)
-- ผู้ดูแลนอกโหมดผู้ดูแลอ่านได้ทางเทคนิค การไม่แสดงข้อมูลห้องเป็นการแยกหน้าที่ในหน้าเว็บ (TECHNICAL_DESIGN 3)
create function private.is_teacher_or_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.accounts a
     where a.auth_user_id = auth.uid() and a.role in ('teacher', 'admin')
  )
$$;
grant execute on function private.is_teacher_or_admin() to authenticated;

grant select on public.terms, public.term_control, public.students, public.roster_entries to authenticated;

-- ชื่อและสถานะภาคเรียนไม่ใช่ข้อมูลส่วนตัว (แสดงบนแถบห้องเรียนของทุกคน)
create policy terms_select_all on public.terms for select to authenticated using (true);
create policy term_control_select_all on public.term_control for select to authenticated using (true);

create policy students_select on public.students
  for select to authenticated
  using ((select private.is_teacher_or_admin()) or account_id = (select private.current_account()));

create policy roster_entries_select on public.roster_entries
  for select to authenticated
  using (
    (select private.is_teacher_or_admin())
    or student_id in (
      select s.id from public.students s where s.account_id = (select private.current_account())
    )
  );

-- ---------------------------------------------------------------------------
-- 3. กันคำขอซ้ำด้วย request key (BUILD_PLAN 4.1 ข้อ 6) — ใช้ภายใน RPC เท่านั้น
-- ---------------------------------------------------------------------------

-- ผลเดิมของคำขอเดียวกัน; key เดิมแต่เนื้อหาคำขอต่าง (operation ต่าง) = ข้อผิดพลาด
create function private.receipt_lookup(p_account uuid, p_key uuid, p_operation text)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_receipt private.operation_receipts;
begin
  select r.* into v_receipt
    from private.operation_receipts r
   where r.account_id = p_account and r.request_key = p_key and r.expires_at > clock_timestamp();
  if not found then
    return null;
  end if;
  if v_receipt.operation <> p_operation then
    raise exception using errcode = 'P0001', message = 'request_key_conflict';
  end if;
  return v_receipt.result;
end
$$;

create function private.receipt_store(p_account uuid, p_key uuid, p_operation text, p_result jsonb)
returns void
language sql
set search_path = ''
as $$
  insert into private.operation_receipts (account_id, request_key, operation, result)
  values (p_account, p_key, p_operation, p_result)
  on conflict (account_id, request_key) do update
    set operation = excluded.operation,
        result = excluded.result,
        created_at = clock_timestamp(),
        expires_at = clock_timestamp() + interval '24 hours'
$$;

-- ---------------------------------------------------------------------------
-- 4. ตรวจและเทียบรายชื่อที่จะนำเข้า (ใช้ทั้ง preview และ commit)
-- ---------------------------------------------------------------------------
-- p_rows: [{ row?, roll_number: number, student_code: string, name_prefix?, first_name, last_name }]
-- ผลต่อแถว status: new (นักเรียนใหม่) | added (มีแล้วแต่ยังไม่อยู่ในเทอมนี้) | moved (ย้ายจากห้องอื่น)
--                  | updated (ชื่อ/คำนำหน้า/เลขที่เปลี่ยน) | unchanged | error
-- errors ต่อแถว: roll_required, roll_invalid, roll_duplicate, roll_taken, code_required, code_invalid,
--                code_duplicate, name_required — หน้าเว็บแปลงเป็นข้อความเอง
-- errors ทั้งชุด: no_term, group_invalid, rows_count (1–300 แถว)
create function private.roster_import_plan(p_group_name text, p_rows jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_term public.terms;
  v_group text := btrim(coalesce(p_group_name, ''));
  v_errors text[] := '{}';
  v_rows jsonb;
  v_missing jsonb;
  v_counts jsonb;
begin
  select t.* into v_term
    from public.term_control c
    join public.terms t on t.id = c.term_id
   where c.singleton;
  if not found then
    v_errors := v_errors || 'no_term'::text;
  end if;
  if v_group = '' or length(v_group) > 30 then
    v_errors := v_errors || 'group_invalid'::text;
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 300 then
    v_errors := v_errors || 'rows_count'::text;
  end if;
  if cardinality(v_errors) > 0 then
    return jsonb_build_object('ok', false, 'errors', to_jsonb(v_errors), 'group_name', v_group,
                              'rows', '[]'::jsonb, 'missing', '[]'::jsonb);
  end if;

  with src as (
    select (e.ord - 1)::int as idx, e.value as r
      from jsonb_array_elements(p_rows) with ordinality as e(value, ord)
  ), norm as (
    select s.idx,
           s.r -> 'row' as source_row,
           jsonb_typeof(s.r -> 'roll_number') as roll_type,
           case when jsonb_typeof(s.r -> 'roll_number') = 'number'
                 and (s.r ->> 'roll_number') ~ '^[0-9]{1,3}$'
                 and (s.r ->> 'roll_number')::int between 1 and 999
                then (s.r ->> 'roll_number')::int end as roll,
           jsonb_typeof(s.r -> 'student_code') as code_type,
           case when jsonb_typeof(s.r -> 'student_code') = 'string'
                then btrim(s.r ->> 'student_code') end as code,
           nullif(btrim(coalesce(s.r ->> 'name_prefix', '')), '') as prefix,
           btrim(coalesce(s.r ->> 'first_name', '')) as first_name,
           btrim(coalesce(s.r ->> 'last_name', '')) as last_name
      from src s
  ), checked as (
    select n.*,
           case when n.first_name <> '' and n.last_name <> ''
                then n.first_name || ' ' || n.last_name end as display_name,
           array_remove(array[
             case when n.roll_type is null or n.roll_type = 'null' then 'roll_required'
                  when n.roll is null then 'roll_invalid' end,
             case when n.code_type is not null and n.code_type not in ('string', 'null') then 'code_invalid'
                  when coalesce(n.code, '') = '' then 'code_required'
                  when n.code !~ '^[0-9]{1,20}$' then 'code_invalid' end,
             case when n.first_name = '' or n.last_name = '' then 'name_required' end,
             case when coalesce(n.code, '') <> ''
                   and count(*) over (partition by coalesce(n.code, '')) > 1 then 'code_duplicate' end,
             case when n.roll is not null
                   and count(*) over (partition by n.roll) > 1 then 'roll_duplicate' end
           ], null) as errs
      from norm n
  ), file_codes as (
    select c.code from checked c where coalesce(c.code, '') <> ''
  ), matched as (
    select c.*,
           st.id as student_id,
           st.name_prefix as old_prefix,
           st.display_name as old_name,
           st.account_id is not null as bound,
           re.group_name as old_group,
           re.roll_number as old_roll,
           -- เลขที่นี้ในห้องนี้เป็นของนักเรียนที่ไม่อยู่ในไฟล์ (ครูต้องแก้ก่อน)
           exists (
             select 1
               from public.roster_entries t
               join public.students ts on ts.id = t.student_id
              where t.term_id = v_term.id and t.group_name = v_group and t.roll_number = c.roll
                and not exists (select 1 from file_codes f where f.code = ts.student_code)
           ) as roll_taken
      from checked c
      left join public.students st on cardinality(c.errs) = 0 and st.student_code = c.code
      left join public.roster_entries re on re.student_id = st.id and re.term_id = v_term.id
  ), planned as (
    select m.*,
           case when m.roll_taken then m.errs || 'roll_taken'::text else m.errs end as all_errs,
           array_remove(array[
             case when m.old_prefix is distinct from m.prefix then 'name_prefix' end,
             case when m.old_name is distinct from m.display_name then 'display_name' end,
             case when m.old_roll is distinct from m.roll then 'roll_number' end
           ], null) as changed
      from matched m
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'index', p.idx,
           'row', p.source_row,
           'roll_number', p.roll,
           'student_code', p.code,
           'name_prefix', p.prefix,
           'display_name', p.display_name,
           'status', case
               when cardinality(p.all_errs) > 0 then 'error'
               when p.student_id is null then 'new'
               when p.old_group is null then 'added'
               when p.old_group <> v_group then 'moved'
               when cardinality(p.changed) > 0 then 'updated'
               else 'unchanged' end,
           'errors', to_jsonb(p.all_errs),
           'changes', case when p.student_id is null then '[]'::jsonb else to_jsonb(p.changed) end,
           'from_group', case when p.old_group is distinct from v_group then p.old_group end,
           'bound', coalesce(p.bound, false)
         ) order by p.idx), '[]'::jsonb)
    into v_rows
    from planned p;

  -- คนที่อยู่ในห้องนี้ของเทอมนี้แต่ไม่อยู่ในไฟล์: แจ้งให้ครูเห็น ไม่ลบ
  select coalesce(jsonb_agg(jsonb_build_object(
           'student_code', s.student_code,
           'display_name', s.display_name,
           'roll_number', e.roll_number,
           'bound', s.account_id is not null
         ) order by e.roll_number), '[]'::jsonb)
    into v_missing
    from public.roster_entries e
    join public.students s on s.id = e.student_id
   where e.term_id = v_term.id and e.group_name = v_group
     and not exists (
       select 1 from jsonb_array_elements(p_rows) x
        where jsonb_typeof(x -> 'student_code') = 'string' and btrim(x ->> 'student_code') = s.student_code
     );

  select jsonb_build_object(
           'rows', count(*),
           'new', count(*) filter (where x ->> 'status' = 'new'),
           'added', count(*) filter (where x ->> 'status' = 'added'),
           'moved', count(*) filter (where x ->> 'status' = 'moved'),
           'updated', count(*) filter (where x ->> 'status' = 'updated'),
           'unchanged', count(*) filter (where x ->> 'status' = 'unchanged'),
           'errors', count(*) filter (where x ->> 'status' = 'error'),
           'missing', jsonb_array_length(v_missing))
    into v_counts
    from jsonb_array_elements(v_rows) x;

  return jsonb_build_object(
    'ok', (v_counts ->> 'errors')::int = 0,
    'errors', '[]'::jsonb,
    'term', jsonb_build_object('id', v_term.id, 'name', v_term.name),
    'group_name', v_group,
    'counts', v_counts,
    'rows', v_rows,
    'missing', v_missing
  );
end
$$;

-- ---------------------------------------------------------------------------
-- 5. RPC ของครู: ดูตัวอย่าง และยืนยันนำเข้า (TECHNICAL_DESIGN 10: /teacher/roster/preview, /commit)
-- ---------------------------------------------------------------------------

create function public.preview_roster_import(
  p_group_name text,
  p_rows jsonb,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_teacher(p_admin_mode);
  return private.roster_import_plan(p_group_name, p_rows);
end
$$;
grant execute on function public.preview_roster_import(text, jsonb, boolean) to authenticated;

-- ตรวจซ้ำภายใต้ล็อกแล้วบันทึกทั้งชุดใน transaction เดียว; มีข้อผิดพลาด = ไม่บันทึกอะไรเลย (committed: false)
-- คำขอซ้ำด้วย request key เดิม (เนื้อหาเดิม) คืนผลเดิม
create function public.commit_roster_import(
  p_group_name text,
  p_rows jsonb,
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
  v_group text := btrim(coalesce(p_group_name, ''));
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_plan jsonb;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;

  v_operation := 'commit_roster_import:' || md5(v_group || ':' || coalesce(p_rows::text, ''));
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: term_control ก่อน แล้วค่อยห้องที่นำเข้า (นำเข้าห้องเดียวกันพร้อมกันได้ทีละคำขอ)
  select c.term_id into v_term_id from public.term_control c where c.singleton for share;
  perform pg_advisory_xact_lock(hashtextextended('roster:' || coalesce(v_term_id::text, '') || ':' || v_group, 0));

  v_plan := private.roster_import_plan(v_group, p_rows);
  if not coalesce((v_plan ->> 'ok')::boolean, false) then
    return v_plan || jsonb_build_object('committed', false);
  end if;

  set constraints public.roster_entries_group_roll_key deferred;

  insert into public.students (student_code, name_prefix, display_name)
  select x ->> 'student_code', x ->> 'name_prefix', x ->> 'display_name'
    from jsonb_array_elements(v_plan -> 'rows') x
   where x ->> 'status' = 'new';

  update public.students s
     set name_prefix = x ->> 'name_prefix',
         display_name = x ->> 'display_name',
         updated_at = clock_timestamp()
    from jsonb_array_elements(v_plan -> 'rows') x
   where s.student_code = x ->> 'student_code'
     and x ->> 'status' in ('added', 'moved', 'updated')
     and (s.name_prefix is distinct from x ->> 'name_prefix'
          or s.display_name is distinct from x ->> 'display_name');

  insert into public.roster_entries as e (term_id, student_id, group_name, roll_number)
  select v_term_id, s.id, v_group, (x ->> 'roll_number')::int
    from jsonb_array_elements(v_plan -> 'rows') x
    join public.students s on s.student_code = x ->> 'student_code'
   where x ->> 'status' in ('new', 'added', 'moved', 'updated')
  on conflict on constraint roster_entries_term_student_key do update
    set group_name = excluded.group_name,
        roll_number = excluded.roll_number,
        updated_at = clock_timestamp()
    where (e.group_name, e.roll_number) is distinct from (excluded.group_name, excluded.roll_number);

  v_result := v_plan || jsonb_build_object('committed', true);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
grant execute on function public.commit_roster_import(text, jsonb, uuid, boolean) to authenticated;
