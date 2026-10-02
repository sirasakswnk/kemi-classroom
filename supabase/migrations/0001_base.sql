-- 0001_base: schema private, สิทธิ์เริ่มต้น, ตารางกลางที่ทุกระยะใช้ และ ping()
-- อ้างอิง: TECHNICAL_BUILD_PLAN 4.1–4.2, TECHNICAL_DESIGN 2, 3.1, 9.1
-- ผลตรวจ kemi-dev (P1-06b): automatic RLS ทำเฉพาะ schema public และตารางใหม่ยังให้
-- anon/authenticated ได้ TRUNCATE/REFERENCES/TRIGGER แม้ปิด auto-expose — จึงถอนสิทธิ์เองทั้งหมด

-- ---------------------------------------------------------------------------
-- 1. ส่วนขยาย (pgtap ไม่ติดตั้งที่นี่: ไฟล์ทดสอบติดตั้งใน transaction แล้ว rollback)
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 2. schema private: ไม่เปิดผ่าน Data API และห้าม anon/authenticated ใช้
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. default privileges ของ role ที่รัน migration (postgres)
--    ระดับทั้งระบบ: Postgres ให้ PUBLIC execute ทุกฟังก์ชันใหม่ ต้องถอนแบบไม่ระบุ schema
--    รายschema: ถอนสิ่งที่ Supabase ให้ anon/authenticated ไว้ แล้ว GRANT รายตัวเองใน migration
-- ---------------------------------------------------------------------------
alter default privileges for role postgres revoke execute on functions from public;

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;

alter default privileges for role postgres in schema private revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema private revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema private revoke all on functions from anon, authenticated;

-- ฟังก์ชันของ automatic RLS (มีเฉพาะบน Supabase cloud) ไม่ต้องให้ใครเรียกตรง
-- event trigger ยังทำงานตามปกติ เพราะ DDL รันในนามเจ้าของฟังก์ชัน (postgres)
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. ตารางกลางใน private (หน้าเว็บเข้าถึงผ่าน RPC เท่านั้น)
--    automatic RLS ไม่ครอบคลุม private จึงเปิด RLS เองทุกตาราง ไม่มี policy
-- ---------------------------------------------------------------------------

-- ค่าตั้งของระบบ เช่น allow_test_logins = on (เฉพาะ kemi-dev; งาน guard ตรวจว่า prod ไม่มี)
create table private.settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  value text not null,
  updated_at timestamptz not null default clock_timestamp()
);

-- กันคำขอซ้ำ: คำขอเดิม (บัญชีเดียวกัน + p_request_key เดิม) คืนผลเดิมภายใน 24 ชม.
-- account_id ผูก foreign key ไป accounts ใน 0002
create table private.operation_receipts (
  account_id uuid not null,
  request_key uuid not null,
  operation text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp() + interval '24 hours',
  primary key (account_id, request_key)
);
create index operation_receipts_expires_at_idx on private.operation_receipts (expires_at);

-- ตัวนับต่อบัญชี/ชนิดการกระทำ/ช่วงเวลา ไม่เก็บคำที่ค้น (L3)
create table private.rate_limits (
  account_id uuid not null,
  action text not null,
  window_start timestamptz not null,
  hits integer not null default 0 check (hits >= 0),
  primary key (account_id, action, window_start)
);
create index rate_limits_window_start_idx on private.rate_limits (window_start);

-- คิวงานเบื้องหลัง (TECHNICAL_DESIGN 9.1): ดึงด้วย FOR UPDATE SKIP LOCKED, idempotent ด้วย dedupe_key
create table private.jobs (
  id bigint generated always as identity primary key,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'done', 'failed')),
  run_at timestamptz not null default clock_timestamp(),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (kind, dedupe_key)
);
create index jobs_pending_run_at_idx on private.jobs (run_at) where status = 'pending';

-- ธงหยุดงานลบไฟล์ใน B2 ระหว่างสำรอง มีเวลาหมดอายุกันธงค้าง
create table private.maintenance_locks (
  name text primary key,
  reason text,
  acquired_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (expires_at > acquired_at)
);

alter table private.settings enable row level security;
alter table private.operation_receipts enable row level security;
alter table private.rate_limits enable row level security;
alter table private.jobs enable row level security;
alter table private.maintenance_locks enable row level security;

-- ย้ำอีกชั้น แม้ default privileges ถอนไว้แล้ว
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. ping(): workflow สำรองเรียกผ่าน Data API ด้วย service role ทุกรอบ (กันโปรเจกต์หลับ)
-- ---------------------------------------------------------------------------
create function public.ping()
returns text
language sql
stable
set search_path = ''
as $$
  select 'pong'::text
$$;

revoke execute on function public.ping() from public, anon, authenticated;
grant execute on function public.ping() to service_role;
