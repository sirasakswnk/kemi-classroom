-- 0005_classrooms: ชั้นเรียน รหัสห้อง สมาชิก — TECHNICAL_DESIGN ส่วน 2, 4, 10; UX_DESIGN ส่วน 4, 9
-- หลัก: ครูสร้างห้องในภาคเรียนปัจจุบัน ระบบสุ่มรหัส 6 ตัว; นักเรียนที่ผูกชื่อแล้วเข้าห้องด้วยรหัสหรือลิงก์ /join/:code
--       (ไม่จำกัดว่ารหัสใช้ได้กับนักเรียนห้องไหน — ยืนยัน 3 ต.ค. 2026); ครูปิด/เปิดการเข้าห้องด้วยรหัสเดิม
--       และเอานักเรียนออกได้โดยลบเฉพาะ membership; ทุก RLS/RPC ของห้องตรวจ membership ทุกคำขอ

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
create table public.classrooms (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.terms (id),
  teacher_id uuid not null references public.teachers (id),
  name text not null check (name = btrim(name) and length(name) between 1 and 80),
  description text check (description is null or length(description) <= 2000),
  -- A–Z และ 2–9 ตัด I, L, O (และ 0, 1) ที่อ่านสับสน; ลิงก์เชิญ /join/:code ใช้รหัสเดียวกัน
  join_code text not null unique check (join_code ~ '^[A-HJKMNP-Z2-9]{6}$'),
  join_enabled boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index classrooms_term_id_idx on public.classrooms (term_id);
create index classrooms_teacher_id_idx on public.classrooms (teacher_id);

-- สมาชิก: ลบแถวเมื่อครูเอาออก — งาน คะแนน ความคิดเห็น โทเคน ผูกกับนักเรียน/งาน ห้ามอ้างแถวนี้ (ทดสอบใน pgTAP)
create table public.memberships (
  classroom_id uuid not null references public.classrooms (id) on delete cascade,
  student_id uuid not null references public.students (id),
  joined_at timestamptz not null default clock_timestamp(),
  primary key (classroom_id, student_id)
);
create index memberships_student_id_idx on public.memberships (student_id);

alter table public.classrooms enable row level security;
alter table public.memberships enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ฟังก์ชันช่วยของ RLS (อยู่ใน private: EXECUTE ให้ authenticated ไม่ให้ USAGE — 3.1 ข้อ 5)
-- ---------------------------------------------------------------------------
-- นักเรียนที่ผูกกับบัญชีผู้เรียก (null = ไม่ใช่นักเรียนหรือยังไม่ผูกชื่อ)
create function private.current_student()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
    from public.students s
    join public.accounts a on a.id = s.account_id
   where a.auth_user_id = auth.uid()
$$;
grant execute on function private.current_student() to authenticated;

-- ผู้เรียกเป็นสมาชิกห้องนี้ขณะนี้หรือไม่ (อ่านสดทุกคำขอ: เอาออกแล้วอ่านไม่ได้ทันที)
create function private.is_member(p_classroom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
     where m.classroom_id = p_classroom_id and m.student_id = private.current_student()
  )
$$;
grant execute on function private.is_member(uuid) to authenticated;

-- ครูเจ้าของห้อง หรือผู้ดูแล (อ่านได้โดยไม่ต้องอยู่ในโหมดผู้ดูแล — การเขียนผ่าน RPC ตรวจโหมดเอง)
create function private.can_teach_classroom(p_classroom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.accounts a
     where a.auth_user_id = auth.uid()
       and (a.role = 'admin'
            or (a.role = 'teacher'
                and exists (select 1 from public.classrooms c
                             where c.id = p_classroom_id and c.teacher_id = a.teacher_id)))
  )
$$;
grant execute on function private.can_teach_classroom(uuid) to authenticated;

grant select on public.classrooms, public.memberships to authenticated;

create policy classrooms_select on public.classrooms
  for select to authenticated
  using (private.can_teach_classroom(id) or private.is_member(id));

create policy memberships_select on public.memberships
  for select to authenticated
  using (student_id = (select private.current_student()) or private.can_teach_classroom(classroom_id));

-- ---------------------------------------------------------------------------
-- 3. ฟังก์ชันช่วยภายใน RPC (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- รหัสห้องสุ่มจาก gen_random_bytes (ไม่ใช้ random()) ตัดไบต์ ≥ 248 ทิ้งเพื่อไม่ให้บางตัวอักษรออกบ่อยกว่า (248 = 31 × 8)
create function private.new_join_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text := '';
  v_bytes bytea;
  v_byte integer;
begin
  while length(v_code) < 6 loop
    v_bytes := extensions.gen_random_bytes(16);
    for i in 0 .. 15 loop
      v_byte := get_byte(v_bytes, i);
      if v_byte < 248 then
        v_code := v_code || substr(v_alphabet, v_byte % 31 + 1, 1);
        exit when length(v_code) = 6;
      end if;
    end loop;
  end loop;
  return v_code;
end
$$;

-- รหัสที่ผู้ใช้พิมพ์: ไม่สนตัวพิมพ์เล็กใหญ่ ตัดช่องว่างและขีด
create function private.normalize_join_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[[:space:] ​-]', '', 'g'))
$$;

-- ตรวจเพดานก่อนทำรายการ (ไม่นับครั้งนี้) — คืนจำนวนครั้งที่เหลือ; นับเพิ่มด้วย private.rate_limit_hit (0004)
create function private.rate_limit_check(p_account uuid, p_action text, p_limit integer, p_window interval)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_used integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('rate:' || p_account || ':' || p_action, 0));
  select coalesce(sum(r.hits), 0)::integer into v_used
    from private.rate_limits r
   where r.account_id = p_account and r.action = p_action and r.window_start > clock_timestamp() - p_window;
  if v_used >= p_limit then
    raise exception using errcode = 'P0001', message = 'rate_limited';
  end if;
  return p_limit - v_used;
end
$$;

-- ครูเจ้าของห้อง หรือผู้ดูแลในโหมดผู้ดูแล; ล็อกแถวห้องไว้แก้ (ห้องที่ไม่มี/ไม่ใช่ของครูคนนี้ = forbidden)
create function private.require_classroom_teacher(p_classroom_id uuid, p_admin_mode boolean)
returns public.classrooms
language plpgsql
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_classroom public.classrooms;
begin
  v_account := private.require_teacher(p_admin_mode);
  select c.* into v_classroom from public.classrooms c where c.id = p_classroom_id for update;
  if not found or (v_account.role = 'teacher' and v_classroom.teacher_id <> v_account.teacher_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return v_classroom;
end
$$;

-- นักเรียนที่ผูกชื่อแล้ว (ใช้กับการเข้าห้อง)
create function private.require_bound_student()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_student_id uuid;
begin
  v_account := private.require_student_account();
  select s.id into v_student_id from public.students s where s.account_id = v_account.id;
  if v_student_id is null then
    raise exception using errcode = 'P0001', message = 'identity_required';
  end if;
  return v_student_id;
end
$$;

-- RPC ของห้องฝั่งนักเรียน (ระยะ 3 ขึ้นไป) เรียกก่อนทุกครั้ง: ไม่ใช่สมาชิกขณะนี้ → not_member (UX 7.1)
create function private.require_member(p_classroom_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_student_id uuid := private.current_student();
begin
  if v_student_id is null or not exists (
    select 1 from public.memberships m where m.classroom_id = p_classroom_id and m.student_id = v_student_id
  ) then
    raise exception using errcode = 'P0001', message = 'not_member';
  end if;
  return v_student_id;
end
$$;

-- ข้อมูลห้องที่นักเรียนเห็นก่อนกดเข้าร่วม (ไม่มีรหัส ไม่มีรายชื่อสมาชิก)
create function private.classroom_card(p_classroom_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'id', c.id,
           'name', c.name,
           'teacher_name', t.display_name,
           'member_count', (select count(*) from public.memberships m where m.classroom_id = c.id))
    from public.classrooms c
    join public.teachers t on t.id = c.teacher_id
   where c.id = p_classroom_id
$$;

-- ---------------------------------------------------------------------------
-- 4. ครู: สร้างห้อง (POST /classrooms) · ปิด/เปิดการเข้าห้อง (PATCH /classrooms/:id/join) · เอาออก (remove_member)
-- ---------------------------------------------------------------------------
-- ผล: { classroom_id, name, description, join_code, join_enabled, term: { id, name } }
-- ผู้ดูแลในโหมดผู้ดูแลต้องระบุ p_teacher_id (ห้องต้องมีครูเจ้าของ); ครูส่งค่านี้มาจะไม่ถูกใช้
create function public.create_classroom(
  p_name text,
  p_description text,
  p_request_key uuid,
  p_teacher_id uuid default null,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_name text := btrim(coalesce(p_name, ''));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_teacher_id uuid;
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_status text;
  v_classroom public.classrooms;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if v_account.role = 'teacher' then
    v_teacher_id := v_account.teacher_id;
  else
    select t.id into v_teacher_id from public.teachers t where t.id = p_teacher_id;
    if v_teacher_id is null then
      raise exception using errcode = 'P0001', message = 'teacher_required';
    end if;
  end if;
  if length(v_name) not between 1 and 80 then
    raise exception using errcode = 'P0001', message = 'name_invalid';
  end if;

  v_operation := 'create_classroom:' || md5(v_name || E'\n' || coalesce(v_description, '') || E'\n' || v_teacher_id);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: term_control ก่อนเสมอ (BUILD_PLAN 4.1 ข้อ 5)
  select c.term_id, c.status into v_term_id, v_status from public.term_control c where c.singleton for share;
  if v_term_id is null then
    raise exception using errcode = 'P0001', message = 'no_term';
  end if;
  if v_status <> 'active' then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;

  -- รหัสชนกับห้องอื่น → สุ่มใหม่ (โอกาสชนต่ำมาก จำกัดรอบกันวนไม่จบ)
  for i in 1 .. 20 loop
    insert into public.classrooms (term_id, teacher_id, name, description, join_code)
    values (v_term_id, v_teacher_id, v_name, v_description, private.new_join_code())
    on conflict (join_code) do nothing
    returning * into v_classroom;
    exit when v_classroom.id is not null;
  end loop;
  if v_classroom.id is null then
    raise exception using errcode = 'P0001', message = 'join_code_exhausted';
  end if;

  v_result := jsonb_build_object(
    'classroom_id', v_classroom.id,
    'name', v_classroom.name,
    'description', v_classroom.description,
    'join_code', v_classroom.join_code,
    'join_enabled', v_classroom.join_enabled,
    'term', jsonb_build_object('id', v_term_id, 'name', (select t.name from public.terms t where t.id = v_term_id)));
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
grant execute on function public.create_classroom(text, text, uuid, uuid, boolean) to authenticated;

-- ปิด/เปิดการเข้าห้อง: เปิดกลับใช้รหัสเดิม ไม่กระทบสมาชิกเดิม; เรียกซ้ำได้ผลเดิม
create function public.set_join_enabled(p_classroom_id uuid, p_enabled boolean, p_admin_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_classroom public.classrooms;
begin
  v_classroom := private.require_classroom_teacher(p_classroom_id, p_admin_mode);
  if v_classroom.join_enabled is distinct from p_enabled then
    update public.classrooms c
       set join_enabled = p_enabled, updated_at = clock_timestamp()
     where c.id = v_classroom.id;
  end if;
  return jsonb_build_object('classroom_id', v_classroom.id, 'join_enabled', p_enabled, 'join_code', v_classroom.join_code);
end
$$;
grant execute on function public.set_join_enabled(uuid, boolean, boolean) to authenticated;

-- เอานักเรียนออก: ลบเฉพาะ membership (ยืนยัน 3 ต.ค. 2026) เรียกซ้ำได้ผลเดิม
create function public.remove_member(p_classroom_id uuid, p_student_id uuid, p_admin_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_classroom public.classrooms;
  v_removed boolean;
begin
  v_classroom := private.require_classroom_teacher(p_classroom_id, p_admin_mode);
  delete from public.memberships m
   where m.classroom_id = v_classroom.id and m.student_id = p_student_id;
  v_removed := found;
  return jsonb_build_object('classroom_id', v_classroom.id, 'student_id', p_student_id, 'removed', v_removed);
end
$$;
grant execute on function public.remove_member(uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. นักเรียน: หาห้องจากรหัส (GET /classrooms/lookup) · เข้าร่วม (POST /classrooms/join)
-- ---------------------------------------------------------------------------
-- ใส่รหัสผิด (ไม่พบห้อง) นับใน rate_limits [ข้อเสนอ] 10 ครั้งต่อ 10 นาทีต่อบัญชี ใช้ตัวนับเดียวกันทั้ง lookup และ join;
-- ครบเพดานแล้วปฏิเสธทุกรหัส (รวมรหัสที่ถูก) จนพ้นช่วงเวลา — ผลที่คาดได้คืนเป็น status ไม่ raise:
--   found     → { status, classroom: { id, name, teacher_name, member_count } }
--   member    → อยู่ในห้องนี้แล้ว (ได้ classroom เหมือนกัน)
--   closed    → ครูปิดการเข้าห้องอยู่ (ไม่บอกชื่อห้อง)
--   not_found → { status, remaining }
create function private.find_classroom_for_join(p_code text, p_student_id uuid, p_account_id uuid, p_lock boolean)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_code text := private.normalize_join_code(p_code);
  v_classroom public.classrooms;
  v_term_id uuid;
  v_term_status text;
  v_remaining integer;
begin
  perform private.rate_limit_check(p_account_id, 'classroom_code', 10, interval '10 minutes');

  -- ลำดับล็อก: term_control ก่อน แล้วค่อยแถวห้อง (กันชนกับการปิดการเข้าห้องที่ล็อก FOR UPDATE)
  select c.term_id, c.status into v_term_id, v_term_status from public.term_control c where c.singleton for share;
  if v_code ~ '^[A-HJKMNP-Z2-9]{6}$' then
    if p_lock then
      select c.* into v_classroom from public.classrooms c where c.join_code = v_code for share;
    else
      select c.* into v_classroom from public.classrooms c where c.join_code = v_code;
    end if;
  end if;

  if v_classroom.id is null then
    v_remaining := private.rate_limit_hit(p_account_id, 'classroom_code', 10, interval '10 minutes');
    return jsonb_build_object('status', 'not_found', 'remaining', v_remaining);
  end if;
  if exists (select 1 from public.memberships m where m.classroom_id = v_classroom.id and m.student_id = p_student_id) then
    return jsonb_build_object('status', 'member', 'classroom', private.classroom_card(v_classroom.id));
  end if;
  if v_classroom.term_id is distinct from v_term_id or v_term_status <> 'active' then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;
  if not v_classroom.join_enabled then
    return jsonb_build_object('status', 'closed');
  end if;
  return jsonb_build_object('status', 'found', 'classroom', private.classroom_card(v_classroom.id));
end
$$;

create function public.lookup_classroom(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid := private.require_bound_student();
begin
  return private.find_classroom_for_join(p_code, v_student_id, private.current_account(), false);
end
$$;
grant execute on function public.lookup_classroom(text) to authenticated;

-- เข้าซ้ำได้ผลเดิม (member) ด้วย PK (classroom_id, student_id); สำเร็จ → { status: 'joined', classroom }
create function public.join_classroom(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid := private.require_bound_student();
  v_found jsonb;
  v_classroom_id uuid;
begin
  v_found := private.find_classroom_for_join(p_code, v_student_id, private.current_account(), true);
  if v_found ->> 'status' <> 'found' then
    return v_found;
  end if;
  v_classroom_id := (v_found #>> '{classroom,id}')::uuid;
  insert into public.memberships (classroom_id, student_id)
  values (v_classroom_id, v_student_id)
  on conflict (classroom_id, student_id) do nothing;
  if not found then
    return jsonb_build_object('status', 'member', 'classroom', private.classroom_card(v_classroom_id));
  end if;
  return jsonb_build_object('status', 'joined', 'classroom', private.classroom_card(v_classroom_id));
end
$$;
grant execute on function public.join_classroom(text) to authenticated;
