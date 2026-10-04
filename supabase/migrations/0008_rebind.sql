-- 0008_rebind: รายชื่อนักเรียนของครู (T05) และแก้การผูกบัญชี — TECHNICAL_DESIGN 3.1 ข้อ 6, ตาราง API (rebind 2 แบบ),
-- UX_DESIGN ส่วน 10 [ข้อเสนอ 4 ต.ค. 2026]
-- หลัก: ครู หรือผู้ดูแลในโหมดผู้ดูแลเท่านั้น; ทำใน transaction เดียว: เปลี่ยน students.account_id แล้วลบ auth.sessions
--       (refresh token ถูกลบตามแบบ cascade) ของบัญชีเดิม; access token เก่าที่ยังไม่หมดอายุไม่ได้สิทธิ์นักเรียนคนเดิม
--       เพราะทุก RLS/RPC อ่านการผูกจากฐานข้อมูลสด (3.1 ข้อ 4); ไม่แตะ membership งาน คะแนน หรือโทเคน (อยู่กับนักเรียน)

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ GRANT ใคร)
-- ---------------------------------------------------------------------------
-- อีเมลปิดบางส่วนสำหรับหน้าครู (แบบ v2: ตัวแรก + ••••• + @โดเมน)
create function private.mask_email(p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when p_email is null then null
           when position('@' in p_email) <= 1 then '•••••'
           else left(p_email, 1) || '•••••' || substr(p_email, position('@' in p_email))
         end
$$;

-- เพิกถอนการเข้าสู่ระบบทั้งหมดของบัญชี: refresh token ใช้ต่อไม่ได้ (ลบตาม session แบบ cascade + token รุ่นเก่าที่ไม่มี session)
create function private.revoke_sessions(p_auth_user_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_auth_user_id is null then
    return 0;
  end if;
  delete from auth.sessions s where s.user_id = p_auth_user_id;
  get diagnostics v_count = row_count;
  delete from auth.refresh_tokens t where t.user_id = p_auth_user_id::text;
  return v_count;
end
$$;

-- นักเรียนที่จะแก้ (ล็อกแถวไว้) — ไม่มี → student_not_found
create function private.lock_student(p_student_id uuid)
returns public.students
language plpgsql
set search_path = ''
as $$
declare
  v_student public.students;
begin
  select s.* into v_student from public.students s where s.id = p_student_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'student_not_found';
  end if;
  return v_student;
end
$$;

-- บัญชีปลายทางจากอีเมล: ต้องเคยเข้าสู่ระบบแล้ว (มีใน accounts) เป็นบัญชีนักเรียน และยังไม่ผูกกับนักเรียนคนอื่น
create function private.rebind_target(p_student public.students, p_email text)
returns public.accounts
language plpgsql
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_count integer;
  v_account public.accounts;
begin
  select count(*)::integer into v_count from public.accounts a where a.email = v_email;
  if v_email = '' or v_count = 0 then
    raise exception using errcode = 'P0001', message = 'account_not_found';
  end if;
  if v_count > 1 then
    raise exception using errcode = 'P0001', message = 'account_ambiguous';
  end if;
  select a.* into v_account from public.accounts a where a.email = v_email for update;
  if v_account.role <> 'student' then
    raise exception using errcode = 'P0001', message = 'account_not_student';
  end if;
  if v_account.id = p_student.account_id then
    raise exception using errcode = 'P0001', message = 'rebind_same_account';
  end if;
  if exists (select 1 from public.students s where s.account_id = v_account.id and s.id <> p_student.id) then
    raise exception using errcode = 'P0001', message = 'account_bound_elsewhere';
  end if;
  return v_account;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. T05 รายชื่อนักเรียนของภาคเรียนปัจจุบัน (อ่าน)
-- ---------------------------------------------------------------------------
-- ผล: [{ student_id, display_name, student_code, group_name, roll_number, bound, account_email (ปิดบางส่วน),
--        classrooms: [ชื่อห้องที่เข้าแล้วในภาคเรียนนี้] }] เรียงตามห้องตามรายชื่อและเลขที่
create function public.roster_overview(p_admin_mode boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_teacher(p_admin_mode);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'student_id', s.id,
             'display_name', s.display_name,
             'student_code', s.student_code,
             'group_name', e.group_name,
             'roll_number', e.roll_number,
             'bound', s.account_id is not null,
             'account_email', private.mask_email(a.email),
             'classrooms', coalesce((
               select jsonb_agg(c.name order by c.name)
                 from public.memberships m
                 join public.classrooms c on c.id = m.classroom_id and c.term_id = e.term_id
                where m.student_id = s.id), '[]'::jsonb)
           ) order by e.group_name, e.roll_number)
      from public.roster_entries e
      join public.term_control tc on tc.singleton and tc.term_id = e.term_id
      join public.students s on s.id = e.student_id
      left join public.accounts a on a.id = s.account_id
  ), '[]'::jsonb);
end
$$;
grant execute on function public.roster_overview(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. แก้การผูก
-- ---------------------------------------------------------------------------
-- หน้าทวนก่อนยืนยัน “ผูกกับบัญชีอื่น” (ไม่เปลี่ยนอะไร): { student_id, display_name, old_email (ปิดบางส่วน) | null, new_email }
create function public.rebind_preview(p_student_id uuid, p_email text, p_admin_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student public.students;
  v_target public.accounts;
begin
  perform private.require_teacher(p_admin_mode);
  select s.* into v_student from public.students s where s.id = p_student_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'student_not_found';
  end if;
  v_target := private.rebind_target(v_student, p_email);
  return jsonb_build_object(
    'student_id', v_student.id,
    'display_name', v_student.display_name,
    'old_email', private.mask_email((select a.email from public.accounts a where a.id = v_student.account_id)),
    'new_email', v_target.email);
end
$$;
grant execute on function public.rebind_preview(uuid, text, boolean) to authenticated;

-- ผูกกับบัญชีอื่น: ล็อกนักเรียน → ตรวจบัญชีปลายทาง → เปลี่ยน account_id → ลบ session ของบัญชีเดิม
-- เรียกซ้ำหลังสำเร็จ (บัญชีปลายทางผูกกับนักเรียนคนนี้อยู่แล้ว) คืนผลเดิมโดยไม่เปลี่ยนอะไร (changed = false)
create function public.rebind_student(p_student_id uuid, p_email text, p_admin_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student public.students;
  v_target public.accounts;
  v_old public.accounts;
  v_revoked integer;
begin
  perform private.require_teacher(p_admin_mode);
  v_student := private.lock_student(p_student_id);
  select a.* into v_old from public.accounts a where a.id = v_student.account_id;

  if v_old.id is not null and v_old.email = lower(btrim(coalesce(p_email, ''))) then
    return jsonb_build_object('student_id', v_student.id, 'display_name', v_student.display_name,
                              'old_email', null, 'new_email', v_old.email, 'revoked_sessions', 0, 'changed', false);
  end if;
  v_target := private.rebind_target(v_student, p_email);

  begin
    update public.students s
       set account_id = v_target.id, updated_at = clock_timestamp()
     where s.id = v_student.id;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'account_bound_elsewhere';
  end;
  v_revoked := private.revoke_sessions(v_old.auth_user_id);

  return jsonb_build_object('student_id', v_student.id, 'display_name', v_student.display_name,
                            'old_email', private.mask_email(v_old.email), 'new_email', v_target.email,
                            'revoked_sessions', v_revoked, 'changed', true);
end
$$;
grant execute on function public.rebind_student(uuid, text, boolean) to authenticated;

-- ถอดการผูก: นักเรียนเลือกชื่อใหม่เองผ่าน A02; บัญชีเดิมออกจากระบบ — ยังไม่ผูกอยู่แล้วคืน changed = false
create function public.unbind_student(p_student_id uuid, p_admin_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student public.students;
  v_old public.accounts;
  v_revoked integer;
begin
  perform private.require_teacher(p_admin_mode);
  v_student := private.lock_student(p_student_id);
  if v_student.account_id is null then
    return jsonb_build_object('student_id', v_student.id, 'display_name', v_student.display_name,
                              'old_email', null, 'revoked_sessions', 0, 'changed', false);
  end if;
  select a.* into v_old from public.accounts a where a.id = v_student.account_id;
  update public.students s
     set account_id = null, updated_at = clock_timestamp()
   where s.id = v_student.id;
  v_revoked := private.revoke_sessions(v_old.auth_user_id);
  return jsonb_build_object('student_id', v_student.id, 'display_name', v_student.display_name,
                            'old_email', private.mask_email(v_old.email), 'revoked_sessions', v_revoked,
                            'changed', true);
end
$$;
grant execute on function public.unbind_student(uuid, boolean) to authenticated;
