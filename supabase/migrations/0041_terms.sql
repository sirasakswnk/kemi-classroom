-- 0041_terms: เริ่มภาคเรียนใหม่ / จบภาคเรียนโดยไม่เปิดเทอมใหม่ (POST /terms/start, POST /terms/end)
-- อ้างอิง: TECHNICAL_DESIGN 7, 10; SYSTEM_SPEC J9, K5, I5, 1.2; TECHNICAL_BUILD_PLAN 4.2 แถว 10
-- หลัก:
--   - ล็อก term_control แบบ exclusive (FOR UPDATE): รอทุกคำสั่งที่ถือ share อยู่ (ตรวจงาน สุ่ม ปรับมือ ส่งงาน ความคิดเห็น)
--     ให้จบก่อน และคำสั่งที่มาทีหลังเห็นเทอม/สถานะใหม่ — ไม่มีอัปโหลดหรือเรียกบริการภายนอกระหว่างล็อก
--   - ยอดโทเคนแยกตาม (นักเรียน, เทอม) อยู่แล้ว: เปลี่ยน term_control.term_id = ยอดทุกห้องเป็น 0 พร้อมกัน (1.2)
--     แถว wallets ของเทอมเก่าเก็บไว้ ลบพร้อมข้อมูลรอบ 1 ปี; owned_charms/student_equipment ไม่แตะ (ผู้ใช้ตัดสิน 24 ต.ค. 2026)
--   - ส่งงาน/ความคิดเห็นของนักเรียน (K5) และการให้รางวัล (I5) ตัดสินจาก term_control ใน RPC เดิมอยู่แล้ว
--   - กันซ้ำ: request key เดิมคืนผลเดิม (receipt 24 ชม.); หน้าจอเก่าต้องส่ง term_id ที่เห็น ไม่ตรง = stale_revision
-- รหัสใหม่: term_name_taken (ชื่อซ้ำกับภาคเรียนที่มีอยู่ ไม่สนตัวพิมพ์เล็กใหญ่) — ต้องเพิ่มแถวในตาราง UX 7.1
-- รหัสเดิม: request_key_required, request_key_conflict, invalid_request, stale_revision, term_ended, no_term,
--           forbidden, admin_mode_required, account_required

-- ชื่อภาคเรียนไม่ซ้ำ (ผู้ใช้ตัดสิน 24 ต.ค. 2026) — RPC ตรวจก่อนเพื่อคืนรหัส term_name_taken
create unique index terms_name_key on public.terms (lower(btrim(name)));

-- สถานะภาคเรียนปัจจุบัน (ผลของทั้งสองคำสั่ง): { term_id, name, status, epoch, started_at, ended_at }
create function private.term_state()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'term_id', c.term_id,
    'name', t.name,
    'status', c.status,
    'epoch', c.epoch,
    'started_at', c.started_at,
    'ended_at', c.ended_at)
    from public.term_control c
    join public.terms t on t.id = c.term_id
   where c.singleton
$$;

-- ---------------------------------------------------------------------------
-- 1. เริ่มภาคเรียนใหม่ (POST /terms/start)
-- ---------------------------------------------------------------------------
-- เริ่มได้ทั้งจาก active (เทอมเดิม → superseded เริ่มนับอายุข้อมูล) และจาก ended (เทอมเดิมคง ended
-- นับอายุจาก ended_at ต่อไป ไม่เริ่มนับใหม่ — TECHNICAL_DESIGN 7)
-- p_name: 1–60 ตัวหลังตัดช่องว่างหัวท้าย · p_expected_term_id: ภาคเรียนที่หน้าจอเห็นตอนกด
-- ผล: term_state() + previous_term_id
create function public.terms_start(
  p_name text,
  p_expected_term_id uuid,
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
  v_name text := btrim(p_name);
  v_operation text;
  v_prior jsonb;
  v_control public.term_control;
  v_new_id uuid;
  v_now timestamptz;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if v_name is null or length(v_name) not between 1 and 60 or p_expected_term_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'terms_start:' || md5(jsonb_build_object(
    'name', v_name, 'expected_term_id', p_expected_term_id)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- exclusive: คำสั่งที่ถือ share อยู่ commit ก่อน แล้วคำสั่งใหม่รอจนเทอมใหม่ commit
  select c.* into v_control from public.term_control c where c.singleton for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'no_term';
  end if;
  if v_control.term_id <> p_expected_term_id then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  if exists (select 1 from public.terms t where lower(btrim(t.name)) = lower(v_name)) then
    raise exception using errcode = 'P0001', message = 'term_name_taken';
  end if;

  v_now := clock_timestamp();
  update public.terms t
     set status = 'superseded', superseded_at = v_now
   where t.id = v_control.term_id and t.status = 'active';
  insert into public.terms (name, status, started_at)
  values (v_name, 'active', v_now)
  returning id into v_new_id;
  update public.term_control c
     set term_id = v_new_id, epoch = c.epoch + 1, status = 'active',
         started_at = v_now, ended_at = null, updated_at = v_now
   where c.singleton;

  v_result := private.term_state() || jsonb_build_object('previous_term_id', v_control.term_id);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.terms_start(text, uuid, uuid, boolean) from public, anon;
grant execute on function public.terms_start(text, uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. จบภาคเรียนโดยไม่เปิดเทอมใหม่ (POST /terms/end, J9)
-- ---------------------------------------------------------------------------
-- ตั้ง ended_at = จุดเริ่มนับอายุข้อมูล (J9.2); ไม่ล้างยอดและไม่เปลี่ยน epoch (K5)
-- จบไปแล้วด้วยคำขอใหม่ = term_ended (หน้าเว็บโหลดสถานะใหม่ตาม UX 7.1)
-- ผล: term_state()
create function public.terms_end(
  p_expected_term_id uuid,
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
  v_operation text;
  v_prior jsonb;
  v_control public.term_control;
  v_now timestamptz;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  if p_expected_term_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'terms_end:' || p_expected_term_id::text;
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  select c.* into v_control from public.term_control c where c.singleton for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'no_term';
  end if;
  if v_control.term_id <> p_expected_term_id then
    raise exception using errcode = 'P0001', message = 'stale_revision';
  end if;
  if v_control.status <> 'active' then
    raise exception using errcode = 'P0001', message = 'term_ended';
  end if;

  v_now := clock_timestamp();
  update public.terms t
     set status = 'ended', ended_at = v_now
   where t.id = v_control.term_id;
  update public.term_control c
     set status = 'ended', ended_at = v_now, updated_at = v_now
   where c.singleton;

  v_result := private.term_state();
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.terms_end(uuid, uuid, boolean) from public, anon;
grant execute on function public.terms_end(uuid, uuid, boolean) to authenticated;
