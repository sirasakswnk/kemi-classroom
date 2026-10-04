-- 0004_identity: นักเรียนค้นชื่อตัวเองและยืนยันตัวตน (L3) — TECHNICAL_DESIGN ส่วน 4, UX_DESIGN ส่วน 4 (A02)
-- หลัก: ค้นได้เฉพาะเลขประจำตัวเต็มหรือชื่อ-นามสกุลเต็ม (ไม่ค้นบางส่วน) คืนชื่อปิดบางส่วน + ห้อง + เลขที่
--       + รหัสอ้างอิงอายุสั้น ไม่คืนเลขประจำตัว ไม่เผยข้อมูลบัญชีที่ผูกแล้ว และจำกัดจำนวนครั้งต่อบัญชี
-- การเลือกชื่อเป็นการอ้างตัวตน ไม่ใช่การพิสูจน์ (UX ส่วน 4) — ผูกแล้วเปลี่ยนได้ทางครูเท่านั้น (P2-08)

-- ---------------------------------------------------------------------------
-- 1. ทำชื่อให้เป็นรูปเดียวกันก่อนเทียบ [ข้อเสนอหลังเห็นไฟล์จริง]
-- ---------------------------------------------------------------------------

-- NFKC (สระอำแบบประกอบ/แยกเป็นแบบเดียวกัน) แล้วลบช่องว่างทุกชนิด รวม NBSP และ zero-width
create function private.name_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(normalize(coalesce(p_name, ''), NFKC), '[[:space:] ​‌‍﻿]', '', 'g')
$$;

-- ตัดคำนำหน้าที่ขึ้นต้น (ใช้กับคำค้นที่ผ่าน name_key แล้ว) — ชื่อในระบบเก็บคำนำหน้าแยกช่องอยู่แล้ว
create function private.strip_name_prefix(p_key text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(p_key, '^(นางสาว|เด็กชาย|เด็กหญิง|ด\.ช\.|ด\.ญ\.|นาย|นาง)', '')
$$;

-- ชื่อปิดบางส่วน: แต่ละคำแสดง 2 กลุ่มตัวอักษรแรก + • 2–4 ตัว (ตามแบบ v2 maskName)
-- กลุ่มตัวอักษร = พยัญชนะ/สระหน้า + สระบน/ล่าง วรรณยุกต์ และสระอำที่ติดกัน (ใกล้เคียง Intl.Segmenter)
create function private.mask_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_word text;
  v_char text;
  v_clusters text[];
  v_out text[] := '{}';
begin
  foreach v_word in array regexp_split_to_array(btrim(coalesce(p_name, '')), '\s+') loop
    continue when v_word = '';
    v_clusters := '{}';
    foreach v_char in array regexp_split_to_array(v_word, '') loop
      if cardinality(v_clusters) > 0 and v_char ~ '[ัำ-ฺ็-๎]' then
        v_clusters[cardinality(v_clusters)] := v_clusters[cardinality(v_clusters)] || v_char;
      else
        v_clusters := v_clusters || v_char;
      end if;
    end loop;
    v_out := v_out || (array_to_string(v_clusters[1:2], '')
                       || repeat('•', least(4, greatest(2, cardinality(v_clusters) - 2))));
  end loop;
  return array_to_string(v_out, ' ');
end
$$;

-- ---------------------------------------------------------------------------
-- 2. จำกัดจำนวนครั้งต่อบัญชี (private.rate_limits จาก 0001) — ช่องละ 1 นาที รวมย้อนหลังตามช่วงเวลา
-- ---------------------------------------------------------------------------
-- คืนจำนวนครั้งที่เหลือหลังครั้งนี้; ถึงเพดานแล้ว raise rate_limited (ครั้งที่ถูกปฏิเสธไม่นับ)
create function private.rate_limit_hit(p_account uuid, p_action text, p_limit integer, p_window interval)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_used integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('rate:' || p_account || ':' || p_action, 0));
  delete from private.rate_limits r
   where r.account_id = p_account and r.action = p_action and r.window_start <= v_now - p_window - interval '1 minute';
  select coalesce(sum(r.hits), 0)::integer into v_used
    from private.rate_limits r
   where r.account_id = p_account and r.action = p_action and r.window_start > v_now - p_window;
  if v_used >= p_limit then
    raise exception using errcode = 'P0001', message = 'rate_limited';
  end if;
  insert into private.rate_limits as r (account_id, action, window_start, hits)
  values (p_account, p_action, date_bin('1 minute', v_now, timestamptz '2000-01-01 00:00:00+00'), 1)
  on conflict (account_id, action, window_start) do update set hits = r.hits + 1;
  return p_limit - v_used - 1;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. รหัสอ้างอิงจากผลค้น (อายุ 10 นาที ใช้ได้กับบัญชีที่ค้นเท่านั้น) — ยืนยันตัวตนต้องผ่านการค้นก่อนเสมอ
-- ---------------------------------------------------------------------------
create table private.roster_claim_refs (
  ref uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  expires_at timestamptz not null default clock_timestamp() + interval '10 minutes'
);
create index roster_claim_refs_account_id_idx on private.roster_claim_refs (account_id);
create index roster_claim_refs_student_id_idx on private.roster_claim_refs (student_id);
alter table private.roster_claim_refs enable row level security;

-- บัญชีนักเรียนของผู้เรียก (ครู/ผู้ดูแลค้นหรือผูกชื่อตัวเองไม่ได้ — ครูใช้การแก้ผูกใน T05)
create function private.require_student_account()
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
  if v_account.role <> 'student' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return v_account;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. search_roster: ค้นแบบตรงทั้งค่า (GET /roster/search)
-- ---------------------------------------------------------------------------
-- ผล: { matches: [{ ref, masked_name, group_name, roll_number }], bound: boolean, remaining: integer }
--   matches = รายชื่อในภาคเรียนปัจจุบันที่ยังไม่ผูก (ไม่เกิน 5) — ไม่มีเลขประจำตัวหรือชื่อเต็ม
--   bound   = มีรายชื่อที่ตรงแต่ผูกกับบัญชีอื่นแล้ว (ไม่บอกว่าบัญชีไหน)
create function public.search_roster(p_query text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_remaining integer;
  v_key text;
  v_term_id uuid;
  v_matches jsonb;
  v_bound boolean;
begin
  v_account := private.require_student_account();
  if exists (select 1 from public.students s where s.account_id = v_account.id) then
    raise exception using errcode = 'P0001', message = 'already_bound';
  end if;
  v_remaining := private.rate_limit_hit(v_account.id, 'search_roster', 10, interval '10 minutes');

  -- ผลค้นครั้งก่อนของบัญชีนี้ใช้ไม่ได้อีก และเก็บกวาดรหัสที่หมดอายุของทุกบัญชี
  delete from private.roster_claim_refs r
   where r.account_id = v_account.id or r.expires_at <= clock_timestamp();

  -- เลขไทยในคำค้นนับเป็นเลขอารบิก (แป้นพิมพ์ไทยบนแท็บเล็ต)
  v_key := translate(private.name_key(left(p_query, 200)), '๐๑๒๓๔๕๖๗๘๙', '0123456789');
  select c.term_id into v_term_id from public.term_control c where c.singleton;
  if v_key = '' or length(v_key) > 100 or v_term_id is null then
    return jsonb_build_object('matches', '[]'::jsonb, 'bound', false, 'remaining', v_remaining);
  end if;

  with hits as materialized (
    select s.id as student_id, s.display_name, e.group_name, e.roll_number,
           s.account_id is not null as bound
      from public.students s
      join public.roster_entries e on e.student_id = s.id and e.term_id = v_term_id
     where case when v_key ~ '^[0-9]+$'
                then s.student_code = v_key
                else private.name_key(s.display_name) in (v_key, private.strip_name_prefix(v_key)) end
  ), picked as (
    select h.* from hits h where not h.bound
     order by h.group_name, h.roll_number limit 5
  ), refs as (
    insert into private.roster_claim_refs (account_id, student_id)
    select v_account.id, p.student_id from picked p
    returning ref, student_id
  )
  select coalesce((select jsonb_agg(jsonb_build_object(
                     'ref', r.ref,
                     'masked_name', private.mask_name(p.display_name),
                     'group_name', p.group_name,
                     'roll_number', p.roll_number
                   ) order by p.group_name, p.roll_number)
                     from picked p join refs r on r.student_id = p.student_id), '[]'::jsonb),
         exists (select 1 from hits h where h.bound)
    into v_matches, v_bound;

  return jsonb_build_object('matches', v_matches, 'bound', v_bound, 'remaining', v_remaining);
end
$$;
grant execute on function public.search_roster(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. claim_identity: ยืนยันว่าเป็นฉัน (POST /identity/claim)
-- ---------------------------------------------------------------------------
-- ผลที่คาดได้คืนเป็น status (ไม่ raise) เพื่อให้ครั้งที่พยายามนับในเพดาน 5 ครั้ง/ชม.:
--   claimed    → { status, display_name (ชื่อเต็มหลังผูกสำเร็จเท่านั้น), group_name, roll_number }
--   name_taken → รายชื่อนี้ผูกกับบัญชีอื่นแล้ว (ไม่บอกว่าบัญชีไหน)
--   expired    → รหัสอ้างอิงหมดอายุ/ไม่ใช่ของบัญชีนี้ ให้ค้นใหม่
-- ชิงชื่อเดียวกันพร้อมกัน: ล็อกแถว students ก่อนตรวจ จึงสำเร็จได้บัญชีเดียว; unique(account_id) กันบัญชีเดียวผูกสองชื่อ
-- กดซ้ำ/ส่งซ้ำด้วยรหัสเดิมหลังผูกสำเร็จ คืน claimed เดิม (เก็บรหัสที่ใช้ผูกไว้จนหมดอายุ)
create function private.claimed_result(p_student_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('status', 'claimed', 'display_name', s.display_name,
                            'group_name', e.group_name, 'roll_number', e.roll_number)
    from public.students s
    left join (public.roster_entries e join public.term_control c on c.term_id = e.term_id and c.singleton)
      on e.student_id = s.id
   where s.id = p_student_id
$$;

create function public.claim_identity(p_ref uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_ref private.roster_claim_refs;
  v_student public.students;
begin
  v_account := private.require_student_account();
  -- คำขอของบัญชีเดียวกันทำทีละคำขอ (หลายแท็บ/กดซ้ำ) — คำสั่งถัดจากนี้เห็นผลของคำขอก่อนหน้าแล้ว
  perform pg_advisory_xact_lock(hashtextextended('claim:' || v_account.id, 0));

  -- ผูกแล้ว: ส่งซ้ำด้วยรหัสเดิมคืนผลเดิม นอกนั้นถูกปฏิเสธ
  select s.* into v_student from public.students s where s.account_id = v_account.id;
  if found then
    if exists (select 1 from private.roster_claim_refs r
                where r.ref = p_ref and r.account_id = v_account.id and r.student_id = v_student.id) then
      return private.claimed_result(v_student.id);
    end if;
    raise exception using errcode = 'P0001', message = 'already_bound';
  end if;

  perform private.rate_limit_hit(v_account.id, 'claim_identity', 5, interval '1 hour');

  select r.* into v_ref from private.roster_claim_refs r
   where r.ref = p_ref and r.account_id = v_account.id and r.expires_at > clock_timestamp();
  if not found then
    return jsonb_build_object('status', 'expired');
  end if;

  select s.* into v_student from public.students s where s.id = v_ref.student_id for update;
  if v_student.account_id is not null then
    return jsonb_build_object('status', 'name_taken');
  end if;

  update public.students s
     set account_id = v_account.id, updated_at = clock_timestamp()
   where s.id = v_student.id;
  delete from private.roster_claim_refs r where r.account_id = v_account.id and r.ref <> p_ref;

  return private.claimed_result(v_student.id);
end
$$;
grant execute on function public.claim_identity(uuid) to authenticated;
