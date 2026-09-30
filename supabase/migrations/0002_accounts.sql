-- 0002_accounts: บัญชี ครู allowlist, ensure_account() และฟังก์ชันช่วยตรวจสิทธิ์
-- อ้างอิง: TECHNICAL_DESIGN 2, 3, 3.1; TECHNICAL_BUILD_PLAN 4.1 ข้อ 3, 9 (allow_test_logins)
-- หลัก: บทบาทมาจากตาราง accounts ขณะนั้นเสมอ ไม่ใช้ user_metadata และไม่ฝังบทบาทใน JWT

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------

-- ตัวครูผู้เป็นเจ้าของชั้นเรียน (ระบบนี้มี 1 คน แต่บัญชี Google ของครูมีได้หลายบัญชี)
create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(btrim(display_name)) > 0),
  created_at timestamptz not null default clock_timestamp()
);

-- บัญชีในระบบ 1 แถวต่อตัวตนจากผู้ให้บริการ
-- auth_user_id ไม่มี foreign key ไป auth.users เพื่อกู้ข้ามโปรเจกต์ได้ (3.1 ข้อ 7)
-- email = อีเมลที่ผู้ให้บริการยืนยันแล้วเท่านั้น (ไม่ยืนยัน = null)
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,
  provider text not null check (provider in ('google', 'email')),
  provider_subject text not null unique,
  email text check (email = lower(email)),
  role text not null default 'student' check (role in ('student', 'teacher', 'admin')),
  teacher_id uuid references public.teachers (id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check ((role = 'teacher') = (teacher_id is not null))
);
create index accounts_teacher_id_idx on public.accounts (teacher_id);

-- บัญชี Google ที่ผู้ดูแลอนุญาตให้เป็นครู (1.5) — อยู่ใน private เพราะมีอีเมลครูและหน้าเว็บไม่อ่านตรง
-- จับคู่ด้วย provider_subject ก่อน ถ้ายังไม่มีจึงจับด้วยอีเมลแล้วตรึง provider_subject ไว้ (3.1 ข้อ 3)
-- revoked_at ไม่ว่าง = เอาออกแล้ว; การเหลือรายการใช้งานอย่างน้อย 1 รายการ (L6) ตรวจใน RPC จัดการครู (0003)
create table private.teacher_allowlist (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers (id),
  email text check (email = lower(email)),
  provider_subject text,
  created_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  check (email is not null or provider_subject is not null)
);
create unique index teacher_allowlist_active_subject_key
  on private.teacher_allowlist (provider_subject)
  where revoked_at is null and provider_subject is not null;
create unique index teacher_allowlist_active_email_key
  on private.teacher_allowlist (email)
  where revoked_at is null and email is not null;
create index teacher_allowlist_teacher_id_idx on private.teacher_allowlist (teacher_id);

alter table public.teachers enable row level security;
alter table public.accounts enable row level security;
alter table private.teacher_allowlist enable row level security;

-- ตารางกลางของ 0001 ผูกกับบัญชี
alter table private.operation_receipts
  add constraint operation_receipts_account_id_fkey
  foreign key (account_id) references public.accounts (id) on delete cascade;
alter table private.rate_limits
  add constraint rate_limits_account_id_fkey
  foreign key (account_id) references public.accounts (id) on delete cascade;

-- ---------------------------------------------------------------------------
-- 2. ฟังก์ชันช่วยใน private
-- ---------------------------------------------------------------------------

-- รหัสบัญชีของผู้เรียกขณะนั้น — RLS policy เรียกเป็น (select private.current_account())
-- SECURITY DEFINER: อ่าน accounts โดยไม่วนกลับเข้า policy ของ accounts เอง
-- GRANT EXECUTE ให้ authenticated แต่ไม่ให้ USAGE บน private: policy ทำงานได้ ส่วนการเรียกตรงถูกปฏิเสธ (3.1 ข้อ 5)
create function private.current_account()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.id from public.accounts a where a.auth_user_id = auth.uid()
$$;
grant execute on function private.current_account() to authenticated;

-- ใช้ภายใน RPC ฝั่งครูเท่านั้น (ไม่ GRANT ให้ใคร): ครู หรือ admin ที่ส่ง p_admin_mode = true (L6)
create function private.require_teacher(p_admin_mode boolean default false)
returns public.accounts
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account public.accounts;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  if v_account.role = 'teacher' then
    return v_account;
  end if;
  if v_account.role = 'admin' then
    if coalesce(p_admin_mode, false) then
      return v_account;
    end if;
    raise exception using errcode = 'P0001', message = 'admin_mode_required';
  end if;
  raise exception using errcode = 'P0001', message = 'forbidden';
end
$$;

-- ใช้ภายใน RPC ของผู้ดูแลเท่านั้น (ไม่ GRANT ให้ใคร)
create function private.require_admin()
returns public.accounts
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account public.accounts;
begin
  select a.* into v_account from public.accounts a where a.auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = 'P0001', message = 'account_required';
  end if;
  if v_account.role <> 'admin' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return v_account;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. ensure_account(): หน้าเว็บเรียกหลังล็อกอินทุกครั้ง
-- ---------------------------------------------------------------------------
-- - ตัวตนมาจาก auth.identities (ข้อมูลจากผู้ให้บริการ) เท่านั้น ไม่อ่าน user_metadata / raw_user_meta_data
-- - provider 'google' เสมอ; provider 'email' เฉพาะเมื่อ private.settings มี allow_test_logins = on (kemi-dev)
-- - allowlist: provider_subject ก่อน แล้วค่อยอีเมลที่ยืนยันแล้ว (เฉพาะ Google) ซึ่งจะตรึง provider_subject ไว้
--   บัญชี 'email' เป็นครูได้ด้วย provider_subject เท่านั้น แม้เปิด allow_test_logins ผิดที่ก็อ้างอีเมลครูไม่ได้
-- - role 'admin' ตั้งโดยผู้พัฒนาในฐานข้อมูลเท่านั้น ฟังก์ชันนี้ไม่ตั้งและไม่ถอด
-- - หลังกู้ข้อมูล (auth_user_id = null) จับคู่ใหม่ด้วย provider_subject แล้วอัปเดต auth_user_id (3.1 ข้อ 7)
create function public.ensure_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_provider text;
  v_subject text;
  v_email text;
  v_account public.accounts;
  v_teacher_id uuid;
  v_role text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'not_authenticated';
  end if;

  select i.provider,
         i.provider_id,
         case when i.identity_data ->> 'email_verified' = 'true'
              then lower(nullif(btrim(i.identity_data ->> 'email'), '')) end
    into v_provider, v_subject, v_email
    from auth.identities i
   where i.user_id = v_uid
     and (i.provider = 'google'
          or (i.provider = 'email'
              and exists (select 1
                            from private.settings s
                           where s.key = 'allow_test_logins' and s.value = 'on')))
   order by (i.provider = 'google') desc, i.last_sign_in_at desc nulls last
   limit 1;

  if v_subject is null then
    raise exception using errcode = 'P0001', message = 'provider_not_allowed';
  end if;

  begin
    insert into public.accounts as a (auth_user_id, provider, provider_subject, email)
    values (v_uid, v_provider, v_subject, v_email)
    on conflict (provider_subject) do update
      set auth_user_id = excluded.auth_user_id,
          provider = excluded.provider,
          email = excluded.email,
          updated_at = clock_timestamp()
    returning a.* into v_account;
  exception
    when unique_violation then
      -- auth user เดียวกันผูกกับบัญชีของตัวตนอื่นอยู่แล้ว
      raise exception using errcode = 'P0001', message = 'account_conflict';
  end;

  if v_account.role = 'admin' then
    v_role := 'admin';
  else
    -- 1) provider_subject
    select t.teacher_id into v_teacher_id
      from private.teacher_allowlist t
     where t.provider_subject = v_subject and t.revoked_at is null;

    -- 2) อีเมลที่ Google ยืนยันแล้ว กับรายการที่ยังไม่ตรึง provider_subject แล้วตรึงไว้
    if v_teacher_id is null and v_provider = 'google' and v_email is not null then
      update private.teacher_allowlist t
         set provider_subject = v_subject
       where t.id = (select t2.id
                       from private.teacher_allowlist t2
                      where t2.provider_subject is null
                        and t2.email = v_email
                        and t2.revoked_at is null
                      limit 1
                        for update)
         and t.provider_subject is null
      returning t.teacher_id into v_teacher_id;

      -- 3) ล็อกอินพร้อมกันสองแท็บ: อีกคำขออาจตรึงไปก่อนแล้ว
      if v_teacher_id is null then
        select t.teacher_id into v_teacher_id
          from private.teacher_allowlist t
         where t.provider_subject = v_subject and t.revoked_at is null;
      end if;
    end if;

    v_role := case when v_teacher_id is null then 'student' else 'teacher' end;
  end if;

  update public.accounts a
     set role = v_role,
         teacher_id = v_teacher_id,
         updated_at = clock_timestamp()
   where a.id = v_account.id
     and (a.role, a.teacher_id) is distinct from (v_role, v_teacher_id);

  return jsonb_build_object(
    'account_id', v_account.id,
    'role', v_role,
    'email', v_email,
    'teacher_id', v_teacher_id
  );
end
$$;
grant execute on function public.ensure_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. สิทธิ์อ่าน: หน้าเว็บอ่านบัญชีของตัวเองได้แถวเดียว (เขียนผ่าน RPC เท่านั้น)
-- ---------------------------------------------------------------------------
grant select on public.accounts to authenticated;

create policy accounts_select_own
  on public.accounts
  for select
  to authenticated
  using (id = (select private.current_account()));
