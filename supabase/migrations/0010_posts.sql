-- 0010_posts: โพสต์ (การบ้าน/ประกาศ) งาน และเฉลย — migration กลุ่ม posts_files ส่วนแรก (P3-01a)
-- TECHNICAL_DESIGN ส่วน 2, 5, 10; SYSTEM_SPEC K1, J1, J2/L4/K2, I4, N1, N2, N4, K4
-- หลัก: เขียนผ่าน RPC เท่านั้น (RPC สร้าง/แก้มากับ T02 ใน P3-02/P3-02b) — authenticated ได้แค่ SELECT ตาม RLS
--       อ่านได้เฉพาะครูเจ้าของห้อง/ผู้ดูแล และสมาชิกห้อง "ขณะนี้" (อ่านแถว membership สดทุกคำขอ แบบเดียวกับ
--       private.require_member: ถูกเอาออกแล้วอ่านไม่ได้ทันที); เฉลยที่ยังไม่เผยแพร่เห็นเฉพาะฝั่งครู
--       ช่องที่ล็อกตามกติกากันด้วย trigger ระดับตาราง ไม่ว่า RPC ตัวไหนเขียน (N2)
--       ไฟล์โจทย์/เฉลยอยู่ใน attachments (P3-01b)

-- ---------------------------------------------------------------------------
-- 1. ตาราง
-- ---------------------------------------------------------------------------
-- ไม่มีงานร่าง (SYSTEM_SPEC ส่วน 3): published_at = เวลาที่ครูโพสต์
-- classroom_id ไม่ cascade: ห้องเรียนไม่มีคำสั่งลบ และไม่ควรลบงานทั้งห้องโดยไม่ตั้งใจ
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references public.classrooms (id),
  kind text not null check (kind in ('homework', 'announcement')),
  -- ยาวไม่เกิน 120 ตามแบบ v2 (T02)
  title text not null check (title = btrim(title) and length(title) between 1 and 120),
  -- ไม่บังคับ (N); ตัวห้อย/ตัวยกเป็นอักขระ Unicode ในข้อความ
  body text check (body is null or length(body) <= 10000),
  published_at timestamptz not null default clock_timestamp(),
  -- N1: เวลาที่ครูแก้โจทย์ล่าสุด (ชื่อ/รายละเอียด/ไฟล์) แสดงแก่นักเรียน ไม่มีแจ้งเตือน; null = ยังไม่เคยแก้
  content_updated_at timestamptz,
  -- revision ของคำสั่งแก้ (คำสั่งที่ส่ง version เก่ามาตอบ conflict — TECHNICAL_DESIGN ส่วน 9)
  version integer not null default 1 check (version >= 1)
);
create index posts_classroom_id_published_at_idx on public.posts (classroom_id, published_at desc);

-- งาน 1:1 กับโพสต์ชนิด homework (ตรวจใน trigger ตอนเพิ่ม) — ลบโพสต์แล้วลบตาม (N4)
create table public.assignments (
  post_id uuid primary key references public.posts (id) on delete cascade,
  -- K1: จำนวนเต็มตั้งแต่ 1 ไม่มีเพดานธุรกิจที่ 100; เพดาน 1,000,000 เป็นตัวกันค่าผิดพลาด/ค่าล้นในสูตรคะแนนเท่านั้น
  full_score integer not null check (full_score between 1 and 1000000),
  -- J1: 0–100 ค่าเริ่มต้น 50 (0 = ไม่หัก)
  late_penalty_pct integer not null default 50 check (late_penalty_pct between 0 and 100),
  -- J2/L4/K2: ตั้งเมื่อบันทึกคะแนนที่ทำได้ครั้งแรกของงาน (กลุ่ม grading) แล้วคะแนนเต็มและ % หักแก้ไม่ได้
  full_score_locked_at timestamptz,
  -- โทเคนเมื่อส่งทันและงานครบถ้วน ค่าเริ่มต้น 1 (ส่วน 7); เพดาน 1,000 เป็นตัวกันค่าผิดพลาด
  reward_tokens integer not null default 1 check (reward_tokens between 0 and 1000),
  -- I4: ตั้งเมื่อมีการส่งครั้งแรกของงาน (กลุ่ม submissions) แล้วจำนวนรางวัลแก้ไม่ได้ถาวร
  reward_locked_at timestamptz,
  -- นาทีเต็มของเวลาไทยเก็บเป็น UTC (ส่วน 5): กำหนด 23:59 น. รับถึง 23:59:00 น.
  due_at timestamptz not null check (mod(extract(epoch from due_at), 60) = 0),
  -- วันปิดรับไม่บังคับ: null = รับงานสายจนกว่าครูปิด (ส่วน 5)
  close_at timestamptz,
  -- N2: ตั้งตอนสร้างงาน (T02) แก้ได้จนเผยแพร่เฉลย — เก็บที่งานเพราะตอนสร้างงานยังไม่มีแถวเฉลย
  accept_after_solution boolean not null default false
);

-- เฉลย: มีได้เฉพาะงาน (ไม่มีในประกาศ); บันทึกไว้ก่อนได้ เผยแพร่ครั้งแรกหลังปิดรับ (กลุ่ม grading)
create table public.solutions (
  assignment_id uuid primary key references public.assignments (post_id) on delete cascade,
  body text check (body is null or length(body) <= 10000),
  -- K4: เวลาเผยแพร่ครั้งแรก ตั้งแล้วไม่เปลี่ยน (แก้หลังเผยแพร่ได้โดยเลื่อน updated_at); null = ยังไม่เผยแพร่
  published_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  -- แสดง "แก้ไขล่าสุด …" เมื่อ updated_at > published_at
  updated_at timestamptz not null default clock_timestamp(),
  version integer not null default 1 check (version >= 1)
);

alter table public.posts enable row level security;
alter table public.assignments enable row level security;
alter table public.solutions enable row level security;

-- ---------------------------------------------------------------------------
-- 2. ตัวกันช่องที่ล็อก (N2, I4, J2/L4/K2, K4) — trigger ไม่ GRANT ใคร
-- ---------------------------------------------------------------------------
-- immutable_field = ช่องที่ไม่มีคำสั่งใดแก้ได้ (หน้าเว็บไม่มีทางทำให้เกิด)
-- reward_locked / full_score_locked / after_solution_locked = ช่องที่ล็อกตามเหตุการณ์ (RPC แก้งานตอบรหัสนี้ให้หน้าเว็บ)
create function private.posts_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- N2: เปลี่ยนการบ้านเป็นประกาศหรือกลับกันไม่ได้; ย้ายห้อง/เปลี่ยนเวลาโพสต์ไม่ได้
  if new.id <> old.id or new.classroom_id <> old.classroom_id or new.kind <> old.kind
     or new.published_at <> old.published_at then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger posts_guard
  before update on public.posts
  for each row execute function private.posts_guard();

create function private.assignments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.posts p where p.id = new.post_id and p.kind = 'homework') then
      raise exception using errcode = 'P0001', message = 'post_not_homework';
    end if;
    return new;
  end if;

  -- ล็อกแล้วปลดหรือเลื่อนเวลาล็อกไม่ได้ ("ไม่ปลดล็อกเพราะเปลี่ยนผลตรวจ" — I4)
  if new.post_id <> old.post_id
     or (old.reward_locked_at is not null and new.reward_locked_at is distinct from old.reward_locked_at)
     or (old.full_score_locked_at is not null
         and new.full_score_locked_at is distinct from old.full_score_locked_at) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  -- I4: จำนวนรางวัลแก้ได้จนมีการส่งครั้งแรก
  if old.reward_locked_at is not null and new.reward_tokens <> old.reward_tokens then
    raise exception using errcode = 'P0001', message = 'reward_locked';
  end if;
  -- J2/L4/K2: คะแนนเต็มและ % หักล็อกพร้อมกันเมื่อบันทึกคะแนนแรก
  if old.full_score_locked_at is not null
     and (new.full_score <> old.full_score or new.late_penalty_pct <> old.late_penalty_pct) then
    raise exception using errcode = 'P0001', message = 'full_score_locked';
  end if;
  -- N2: "รับงานหลังเผยแพร่เฉลย" แก้ได้จนเผยแพร่เฉลย
  -- (คำสั่งเผยแพร่เฉลยต้องล็อกแถวงานนี้ FOR UPDATE ก่อน จึงไม่ชนกับการแก้งานพร้อมกัน)
  if new.accept_after_solution <> old.accept_after_solution
     and exists (select 1 from public.solutions s
                  where s.assignment_id = old.post_id and s.published_at is not null) then
    raise exception using errcode = 'P0001', message = 'after_solution_locked';
  end if;
  return new;
end
$$;

create trigger assignments_guard
  before insert or update on public.assignments
  for each row execute function private.assignments_guard();

create function private.solutions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- K4: คงเวลาเผยแพร่ครั้งแรก และยกเลิกการเผยแพร่ไม่ได้
  if new.assignment_id <> old.assignment_id
     or (old.published_at is not null and new.published_at is distinct from old.published_at) then
    raise exception using errcode = 'P0001', message = 'immutable_field';
  end if;
  return new;
end
$$;

create trigger solutions_guard
  before update on public.solutions
  for each row execute function private.solutions_guard();

-- ---------------------------------------------------------------------------
-- 3. RLS อ่าน (ฟังก์ชันช่วยอยู่ใน private: EXECUTE ให้ authenticated ไม่ให้ USAGE — 3.1 ข้อ 5)
-- ---------------------------------------------------------------------------
-- สิทธิ์อ่านโพสต์นี้ของผู้เรียก: 'teacher' (ครูเจ้าของห้องหรือผู้ดูแล) · 'member' (สมาชิกขณะนี้) · null
-- ใช้กับตารางลูก (assignments, solutions) ที่ไม่มี classroom_id ในแถว
create function private.post_access(p_post_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when private.can_teach_classroom(p.classroom_id) then 'teacher'
           when private.is_member(p.classroom_id) then 'member'
         end
    from public.posts p
   where p.id = p_post_id
$$;
grant execute on function private.post_access(uuid) to authenticated;

grant select on public.posts, public.assignments, public.solutions to authenticated;

create policy posts_select on public.posts
  for select to authenticated
  using (private.can_teach_classroom(classroom_id) or private.is_member(classroom_id));

create policy assignments_select on public.assignments
  for select to authenticated
  using (private.post_access(post_id) is not null);

-- สมาชิกเห็นเฉลยเมื่อเผยแพร่แล้วเท่านั้น
create policy solutions_select on public.solutions
  for select to authenticated
  using (case private.post_access(assignment_id)
           when 'teacher' then true
           when 'member' then published_at is not null
           else false
         end);
