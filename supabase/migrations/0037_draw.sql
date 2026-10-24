-- 0037_draw: อัตราสุ่มจริง + สุ่มไม่ซ้ำ + เลือกเครื่องรางที่แสดงข้างชื่อ (P5-04)
-- TECHNICAL_DESIGN ส่วน 8 (K6), ส่วน 7 (ลำดับล็อก term_control → wallet; จบภาคเรียนแล้วยังสุ่มได้ K5),
-- ส่วน 10 GET /draw/options, POST /draw, PUT /equipment · UX_DESIGN ส่วน 11
--   - ชุดรายการ/น้ำหนักอ่านในคำสั่งเดียว (private.draw_pool) จึงมาจากรุ่นเดียวกันตลอดการสุ่ม
--   - P(ระดับ) = น้ำหนัก / ผลรวมน้ำหนักของระดับที่ยังมีของเหลือ; ในระดับเดียวกันของที่ยังไม่มีโอกาสเท่ากัน
--   - สถานะ: completed (ครบทุกชิ้น) → unavailable (ของที่เหลือน้ำหนัก 0 ทั้งหมด) → insufficient (ยอด < 1) → ok
--     สองสถานะแรกปิดสุ่มและไม่หักยอด (รหัสใหม่ draw_completed / draw_unavailable)
--   - rates_key = ลายนิ้วมือของชุดที่ใช้คำนวณอัตรา (ระดับ น้ำหนัก ของที่เหลือ) — draw_charm รับค่าที่หน้าจอแสดงไป
--     ถ้าไม่ตรงชุดล่าสุด (ครูแก้อัตรา/รายการ หรือแท็บอื่นสุ่มไปก่อน) → stale_revision ให้หน้าเว็บโหลดอัตราใหม่
--     จึงไม่มีการสุ่มด้วยอัตราที่นักเรียนไม่เห็น (K6)
--   - แหล่งสุ่ม extensions.gen_random_bytes (pgcrypto) แบบไม่เอียง (ตัดค่าที่เกินพหุคูณทิ้ง)

-- ---------------------------------------------------------------------------
-- 1. ฟังก์ชันช่วย (ไม่ให้ authenticated เรียกตรง)
-- ---------------------------------------------------------------------------
-- จำนวนเต็มสุ่มใน [0, n) จาก 4 ไบต์ของ gen_random_bytes — ค่า ≥ พหุคูณสูงสุดของ n ที่ไม่เกิน 2^32 สุ่มใหม่
create function private.random_below(p_n integer)
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_limit bigint;
  v_value bigint;
begin
  if p_n is null or p_n < 1 then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  v_limit := 4294967296 - (4294967296 % p_n);
  loop
    v_value := ('x' || lpad(encode(extensions.gen_random_bytes(4), 'hex'), 16, '0'))::bit(64)::bigint;
    exit when v_value < v_limit;
  end loop;
  return (v_value % p_n)::integer;
end
$$;

-- ชุดสุ่มของนักเรียนในคำสั่งเดียว: [{ rarity_id, name, weight, total, remaining_ids }] เรียงตามระดับ
-- remaining_ids = เครื่องรางที่ยังไม่มี เรียงตามตำแหน่ง
create function private.draw_pool(p_student_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(l) order by l.rarity_id), '[]'::jsonb)
    from (
      select r.id as rarity_id, r.name, r.weight,
             count(c.id)::integer as total,
             coalesce(jsonb_agg(c.id order by c.position) filter (where c.id is not null and o.charm_id is null),
                      '[]'::jsonb) as remaining_ids
        from public.rarities r
        left join public.charms c on c.rarity_id = r.id
        left join public.owned_charms o on o.charm_id = c.id and o.student_id = p_student_id
       group by r.id
    ) l
$$;

-- สรุปสถานะและอัตราจริงจากชุดสุ่ม (ผลของ GET /draw/options)
-- { status, balance, owned, total, rates_key, levels: [{ rarity_id, name, weight, total, owned, remaining, pct, pct_each }] }
-- pct = โอกาสออกระดับนี้ (%), pct_each = โอกาสต่อชิ้นที่ยังไม่มี (%) — ปัดทศนิยม 2 ตำแหน่งเพื่อแสดงเท่านั้น
create function private.draw_summary(p_pool jsonb, p_balance integer)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_total integer;
  v_remaining integer;
  v_weight_sum integer;
  v_status text;
  v_levels jsonb;
begin
  select coalesce(sum((l ->> 'total')::integer), 0),
         coalesce(sum(jsonb_array_length(l -> 'remaining_ids')), 0),
         coalesce(sum((l ->> 'weight')::integer) filter (where jsonb_array_length(l -> 'remaining_ids') > 0), 0)
    into v_total, v_remaining, v_weight_sum
    from jsonb_array_elements(p_pool) l;

  v_status := case
    when v_total > 0 and v_remaining = 0 then 'completed'
    when v_weight_sum = 0 then 'unavailable'
    when p_balance < 1 then 'insufficient'
    else 'ok' end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rarity_id', x.rarity_id, 'name', x.name, 'weight', x.weight,
           'total', x.total, 'owned', x.total - x.remaining, 'remaining', x.remaining,
           'pct', x.pct, 'pct_each', case when x.remaining > 0 then round(x.raw / x.remaining, 2) else 0 end)
           order by x.rarity_id), '[]'::jsonb)
    into v_levels
    from (
      select (l ->> 'rarity_id')::integer as rarity_id, l ->> 'name' as name, (l ->> 'weight')::integer as weight,
             (l ->> 'total')::integer as total, jsonb_array_length(l -> 'remaining_ids') as remaining,
             r.raw, round(r.raw, 2) as pct
        from jsonb_array_elements(p_pool) l
        cross join lateral (
          select case when v_weight_sum > 0 and jsonb_array_length(l -> 'remaining_ids') > 0
                      then (l ->> 'weight')::numeric * 100 / v_weight_sum else 0 end as raw
        ) r
    ) x;

  return jsonb_build_object(
    'status', v_status,
    'balance', p_balance,
    'owned', v_total - v_remaining,
    'total', v_total,
    'rates_key', md5(p_pool::text),
    'levels', v_levels);
end
$$;

-- เลือกหนึ่งชิ้นจากชุดสุ่ม: สุ่มระดับตามน้ำหนักของระดับที่ยังมีของเหลือ แล้วสุ่มชิ้นในระดับนั้นแบบเท่ากัน
-- null = ไม่มีอะไรให้สุ่ม (ครบแล้วหรือของที่เหลือน้ำหนัก 0 ทั้งหมด)
create function private.draw_pick(p_pool jsonb)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_weight_sum integer;
  v_roll integer;
  v_level jsonb;
  v_ids jsonb;
begin
  select coalesce(sum((l ->> 'weight')::integer), 0) into v_weight_sum
    from jsonb_array_elements(p_pool) l
   where jsonb_array_length(l -> 'remaining_ids') > 0;
  if v_weight_sum = 0 then
    return null;
  end if;

  v_roll := private.random_below(v_weight_sum);
  for v_level in
    select l from jsonb_array_elements(p_pool) l
     where jsonb_array_length(l -> 'remaining_ids') > 0 and (l ->> 'weight')::integer > 0
     order by (l ->> 'rarity_id')::integer
  loop
    if v_roll < (v_level ->> 'weight')::integer then
      v_ids := v_level -> 'remaining_ids';
      return (v_ids ->> private.random_below(jsonb_array_length(v_ids)))::uuid;
    end if;
    v_roll := v_roll - (v_level ->> 'weight')::integer;
  end loop;
  return null;  -- ไปไม่ถึง: ผลรวมน้ำหนักคำนวณจากชุดเดียวกัน
end
$$;

-- นักเรียนที่ผูกกับบัญชีผู้เรียก — บัญชีนักเรียนที่ยังไม่เลือกชื่อ = identity_required
create function private.require_current_student()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  perform private.require_student_account();
  v_student_id := private.current_student();
  if v_student_id is null then
    raise exception using errcode = 'P0001', message = 'identity_required';
  end if;
  return v_student_id;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. GET /draw/options — อัตราจริงของนักเรียนคนนี้ (K6) และสถานะปุ่มสุ่ม
-- ---------------------------------------------------------------------------
create function public.get_draw_options()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_balance integer;
begin
  v_student_id := private.require_current_student();
  select coalesce((select w.balance from public.wallets w
                    where w.student_id = v_student_id and w.term_id = tc.term_id), 0)
    into v_balance
    from public.term_control tc where tc.singleton;
  return private.draw_summary(private.draw_pool(v_student_id), coalesce(v_balance, 0));
end
$$;
revoke all on function public.get_draw_options() from public, anon;
grant execute on function public.get_draw_options() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. POST /draw — สุ่ม 1 ชิ้น หัก 1 โทเคน ใน transaction เดียว
-- ---------------------------------------------------------------------------
-- p_rates_key: rates_key จาก get_draw_options ที่หน้าจอแสดงอยู่
-- ผล: { charm: { id, name, description, symbol, rarity_id, rarity_name, position }, obtained_at, balance, version }
create function public.draw_charm(p_rates_key text, p_request_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_student_id uuid;
  v_operation text;
  v_prior jsonb;
  v_term_id uuid;
  v_wallet public.wallets;
  v_pool jsonb;
  v_summary jsonb;
  v_charm_id uuid;
  v_now timestamptz;
  v_result jsonb;
begin
  v_account := private.require_student_account();
  v_student_id := private.require_current_student();
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_rates_key is null or p_rates_key !~ '^[0-9a-f]{32}$' then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'draw_charm:' || p_rates_key;
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก (ส่วน 7): term_control (share) → wallets — การสุ่มของนักเรียนคนเดียวกันเรียงกันที่แถวกระเป๋า
  -- (ยอด < 1 ไม่ต้องมีแถว: ปฏิเสธได้เลย) จึงอ่านของที่มีอยู่หลังล็อกแล้วไม่ชนกัน
  select c.term_id into v_term_id from public.term_control c where c.singleton for share;
  select w.* into v_wallet from public.wallets w
   where w.student_id = v_student_id and w.term_id = v_term_id for update;

  v_pool := private.draw_pool(v_student_id);
  v_summary := private.draw_summary(v_pool, coalesce(v_wallet.balance, 0));
  case v_summary ->> 'status'
    when 'completed' then raise exception using errcode = 'P0001', message = 'draw_completed';
    when 'unavailable' then raise exception using errcode = 'P0001', message = 'draw_unavailable';
    when 'insufficient' then raise exception using errcode = 'P0001', message = 'insufficient_balance';
    else null;
  end case;
  if v_summary ->> 'rates_key' <> p_rates_key then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;

  v_charm_id := private.draw_pick(v_pool);
  v_now := clock_timestamp();
  insert into public.owned_charms (student_id, charm_id, obtained_at) values (v_student_id, v_charm_id, v_now);
  update public.wallets w
     set balance = w.balance - 1, version = w.version + 1, updated_at = v_now
   where w.student_id = v_student_id and w.term_id = v_term_id
  returning w.* into v_wallet;

  select jsonb_build_object(
           'charm', jsonb_build_object(
             'id', c.id, 'name', c.name, 'description', c.description, 'symbol', c.symbol,
             'rarity_id', c.rarity_id, 'rarity_name', r.name, 'position', c.position),
           'obtained_at', v_now,
           'balance', v_wallet.balance,
           'version', v_wallet.version)
    into v_result
    from public.charms c join public.rarities r on r.id = c.rarity_id
   where c.id = v_charm_id;
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.draw_charm(text, uuid) from public, anon;
grant execute on function public.draw_charm(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. PUT /equipment — เลือกเครื่องรางที่แสดงข้างชื่อ (null = ไม่แสดง)
-- ---------------------------------------------------------------------------
-- ตั้งค่าซ้ำได้ผลเดิม จึงไม่ใช้ request key; ของที่ไม่ใช่ของตน = invalid_request (หน้าเว็บเสนอเฉพาะชิ้นที่มี
-- และไม่มีคำสั่งลบของสะสม จึงไม่เกิดจากการใช้งานปกติ) · ผล: { charm_id }
create function public.set_equipment(p_charm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  v_student_id := private.require_current_student();
  if p_charm_id is not null and not exists (
    select 1 from public.owned_charms o where o.student_id = v_student_id and o.charm_id = p_charm_id
  ) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;
  insert into public.student_equipment as e (student_id, charm_id, updated_at)
  values (v_student_id, p_charm_id, clock_timestamp())
  on conflict (student_id) do update set charm_id = excluded.charm_id, updated_at = excluded.updated_at;
  return jsonb_build_object('charm_id', p_charm_id);
end
$$;
revoke all on function public.set_equipment(uuid) from public, anon;
grant execute on function public.set_equipment(uuid) to authenticated;
