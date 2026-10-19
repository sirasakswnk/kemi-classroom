-- 0034_rewards: กระเป๋าโทเคน ระดับ เครื่องราง ตู้สะสม การสวมใส่ — migration กลุ่ม rewards ส่วนแรก (P5-01)
-- TECHNICAL_DESIGN ส่วน 2 (wallets, rarities, charms, owned_charms, student_equipment), ส่วน 7 (เอฟเฟกต์ reward_effect_seen),
-- ส่วน 8 (สุ่มไม่ซ้ำ, รหัสเครื่องรางคงที่, ไม่มีคำสั่งลบของสะสม); TECHNICAL_BUILD_PLAN 4.1, 4.2 แถว 9; UX_DESIGN ส่วน 11
-- ส่วนนี้มีแค่ตาราง ตัวกัน และสิทธิ์อ่าน — ไม่มี RPC เขียน:
--   ให้รางวัลใน grade_submission (0035, P5-02), ปรับยอด/เอฟเฟกต์ (0036, P5-03), สุ่ม/สวมใส่ (0037, P5-04),
--   จัดการเครื่องรางและรูป (0038, P5-07)
-- ระดับ 4 ระดับและเครื่องราง 12 ชิ้นเริ่มต้นอยู่ใน seed.sql (BUILD_PLAN 4.2) ไม่ใช่ใน migration
--   - wallet: หนึ่งแถวต่อ (นักเรียน, เทอม) สร้างเมื่อได้โทเคนครั้งแรกของเทอม — ไม่มีแถว = ยอด 0;
--     เริ่มเทอมใหม่ไม่ต้องล้างแถวเก่า (ยอดของเทอมใหม่เริ่มที่ไม่มีแถว) ไม่มีบัญชีประวัติเพิ่ม–ลด (ส่วน 7)
--   - ระดับมี 4 ระดับคงที่ (id 1–4 = ทั่วไป · หายาก · พิเศษ · ตำนาน ใช้กำหนดสีรูปชั่วคราว) ครูแก้ชื่อและน้ำหนักได้
--     ผลรวมน้ำหนักต้องเป็น 100 ตรวจตอนจบ transaction (แก้ทีละแถวได้ระหว่างทาง)
--   - เพื่อนร่วมห้องเห็นเครื่องรางที่สวมผ่าน RPC แท็บสมาชิก (P5-06) ไม่ใช่ policy ของตาราง — ตู้และการสวมเป็นส่วนตัว

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------

-- ระดับและน้ำหนักการสุ่ม (อัตราตั้งต้น 60/25/10/5 — UX ส่วน 11)
create table public.rarities (
  id smallint primary key check (id between 1 and 4),
  name text not null check (name = btrim(name) and length(name) between 1 and 30),
  weight integer not null check (weight between 0 and 100),
  updated_at timestamptz not null default clock_timestamp()
);

-- เครื่องราง: รหัสคงที่ แก้ชื่อ/คำอธิบาย/ระดับได้โดยไม่กลายเป็นของใหม่ (ส่วน 8)
create table public.charms (
  id uuid primary key default gen_random_uuid(),
  rarity_id smallint not null references public.rarities (id),
  name text not null check (name = btrim(name) and length(name) between 1 and 60),
  -- นักเรียนเห็นตอนสุ่มได้และในตู้สะสม (UX ส่วน 11 [ข้อเสนอ] ไม่เกิน 120 ตัว)
  description text not null default '' check (description = btrim(description) and length(description) <= 120),
  -- สัญลักษณ์บนรูปชั่วคราว (เหรียญวาดด้วยโค้ด) จนกว่าครูอัปโหลดรูป (P5-07)
  symbol text not null check (symbol = btrim(symbol) and length(symbol) between 1 and 8),
  -- ลำดับแสดงใน T06/S05
  position integer not null check (position >= 1),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint charms_position_key unique (position) deferrable initially immediate
);
create index charms_rarity_id_idx on public.charms (rarity_id);

-- ยอดโทเคนของเทอม (term_id = เทอมกระเป๋า term_control.term_id ตอนเพิ่ม/ลด)
create table public.wallets (
  student_id uuid not null references public.students (id),
  term_id uuid not null references public.terms (id),
  balance integer not null default 0 check (balance >= 0),
  -- รุ่นยอด: ปรับมือส่งรุ่นที่เห็นมา (ส่วน 7) — เพิ่มทุกครั้งที่ยอดเปลี่ยน
  version integer not null default 1 check (version >= 1),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (student_id, term_id)
);
create index wallets_term_id_idx on public.wallets (term_id);

-- ของสะสม: หลักฐานการเป็นเจ้าของ กันของซ้ำ ไม่หายเมื่อเปลี่ยนเทอม
create table public.owned_charms (
  student_id uuid not null references public.students (id),
  charm_id uuid not null references public.charms (id),
  obtained_at timestamptz not null default clock_timestamp(),
  primary key (student_id, charm_id)
);
create index owned_charms_charm_id_idx on public.owned_charms (charm_id);

-- เครื่องรางที่แสดงข้างชื่อ (หนึ่งชิ้น ว่างได้) ต้องเป็นของที่คนนี้เป็นเจ้าของ
create table public.student_equipment (
  student_id uuid primary key references public.students (id),
  charm_id uuid,
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (student_id, charm_id) references public.owned_charms (student_id, charm_id)
);
create index student_equipment_student_id_charm_id_idx on public.student_equipment (student_id, charm_id);

-- เอฟเฟกต์ได้รับโทเคนแสดงครั้งเดียวเมื่อกลับมา (ส่วน 7) — ค้างอยู่ = reward_granted and not reward_effect_seen
alter table public.submissions
  add column reward_effect_seen boolean not null default false,
  add constraint submissions_effect_after_reward check (not reward_effect_seen or reward_granted);

alter table public.rarities enable row level security;
alter table public.charms enable row level security;
alter table public.wallets enable row level security;
alter table public.owned_charms enable row level security;
alter table public.student_equipment enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ตัวกัน — trigger ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------

-- เดิม (0020) + reward_effect_seen เปลี่ยนได้ทางเดียว false → true
create or replace function private.submissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.assignment_id <> old.assignment_id or new.student_id <> old.student_id
     or new.first_submitted_at <> old.first_submitted_at or new.first_after_solution <> old.first_after_solution
     or new.content_revision < old.content_revision or new.last_submitted_at < old.last_submitted_at
     or (old.reward_granted and not new.reward_granted)
     or (old.reward_effect_seen and not new.reward_effect_seen) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

-- ผลรวมน้ำหนักทุกระดับ = 100 ตอนจบ transaction (ตารางว่างผ่าน — ก่อน seed)
create function private.rarities_total_weight()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.rarities)
     and (select sum(r.weight) from public.rarities r) <> 100 then
    raise exception using errcode = 'P0001', message = 'rates_must_total_100';
  end if;
  return null;
end
$$;

create constraint trigger rarities_total_weight
  after insert or update or delete on public.rarities
  deferrable initially deferred
  for each row execute function private.rarities_total_weight();

create function private.charms_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.created_at <> old.created_at then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger charms_guard
  before update on public.charms
  for each row execute function private.charms_guard();

create function private.wallets_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.student_id <> old.student_id or new.term_id <> old.term_id or new.version < old.version then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger wallets_guard
  before update on public.wallets
  for each row execute function private.wallets_guard();

-- ของที่ได้แล้วแก้ไม่ได้ (ไม่มีคำสั่งลบของสะสม — ลบได้เฉพาะพร้อมข้อมูลตามอายุในระยะ 6)
create function private.owned_charms_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'P0001', message = 'immutable_field';
end
$$;

create trigger owned_charms_guard
  before update on public.owned_charms
  for each row execute function private.owned_charms_guard();

-- ---------------------------------------------------------------------------
-- 3. สิทธิ์อ่าน (เขียนผ่าน RPC เท่านั้น)
-- ---------------------------------------------------------------------------
grant select on public.rarities, public.charms, public.wallets, public.owned_charms, public.student_equipment
  to authenticated;

-- ชุดเครื่องรางและอัตราไม่ใช่ข้อมูลส่วนตัว (S04 แสดงอัตรา, S05 แสดงช่องที่ยังไม่มี)
create policy rarities_select_all on public.rarities for select to authenticated using (true);
create policy charms_select_all on public.charms for select to authenticated using (true);

-- ยอด ตู้ และการสวม: เจ้าของ หรือครู/ผู้ดูแล (แบบเดียวกับ students_select — 0003)
create policy wallets_select on public.wallets
  for select to authenticated
  using ((select private.is_teacher_or_admin()) or student_id = (select private.current_student()));

create policy owned_charms_select on public.owned_charms
  for select to authenticated
  using ((select private.is_teacher_or_admin()) or student_id = (select private.current_student()));

create policy student_equipment_select on public.student_equipment
  for select to authenticated
  using ((select private.is_teacher_or_admin()) or student_id = (select private.current_student()));
