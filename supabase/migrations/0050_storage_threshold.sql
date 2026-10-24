-- 0050_storage_threshold: แจ้งครูเมื่อพื้นที่ถึงเกณฑ์ครู (90%) และเมื่อเต็ม ครั้งเดียวต่อระดับ (P6-04b) — J10.1, J10.3;
--   TECHNICAL_DESIGN นโยบายโควตา + 11 · 80% (admin_warn_pct) แจ้งผู้ดูแลในหน้า D01 เท่านั้น ไม่มีกระดิ่งผู้ดูแล (J10.1)
-- เปอร์เซ็นต์คิดจากเพดานที่ใช้ได้จริง (quota_bytes − hard_stop_margin_bytes) ด้วย private.storage_used_bytes()
--   ซึ่งรวมค่าชดเชยจากการเทียบ B2 (0049) แล้ว = ยอดที่มากกว่าระหว่างฐานข้อมูลกับผลเทียบ
-- cron ทุก 5 นาทีเรียก private.storage_threshold_check():
--   ระดับตอนนี้ (0 / 90 / 100) เทียบกับระดับที่แจ้งไปแล้ว (storage_settings.notified_level)
--   - ลดลงต่ำกว่าระดับที่แจ้งแล้ว (ครูลบไฟล์เทอมเก่า) → ลดระดับที่แจ้งแล้วลงตาม → ขึ้นใหม่ภายหลังแจ้งได้อีกครั้ง
--   - สูงขึ้นกว่าที่แจ้งแล้ว → แจ้งครูทุกคนที่ระดับนั้น (กระโดดจากต่ำกว่า 90 ไปเต็มเลย = แจ้งเฉพาะ “เต็ม”)
--   แจ้งซ้ำใช้แถวเดิม (dedupe ต่อระดับต่อครู) เลื่อนเวลาและกลับเป็นยังไม่อ่าน

alter table public.storage_settings
  add column notified_level integer not null default 0 check (notified_level in (0, 90, 100));

-- ระดับของครูตอนนี้: 100 = เต็ม (อัปโหลดใหม่ไม่ได้) · 90 = ถึง teacher_warn_pct · 0 = ยังไม่ถึง
create function private.storage_teacher_level(p_settings public.storage_settings)
returns integer
language sql
volatile
set search_path = ''
as $$
  select case when u.used >= u.lim then 100
              when u.used * 100.0 / u.lim >= p_settings.teacher_warn_pct then 90
              else 0 end
    from (select private.storage_used_bytes() as used,
                 p_settings.quota_bytes - p_settings.hard_stop_margin_bytes as lim) u
$$;

-- เรียกจาก cron (postgres) — ล็อกแถวตั้งค่าก่อนนับ (เหมือน reserve_storage) จึงไม่แจ้งซ้อนกันเมื่อรอบชนกัน
-- ผล: { level, notified_before, notified_after, sent }
create function private.storage_threshold_check()
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_settings public.storage_settings;
  v_level integer;
  v_after integer;
  v_sent integer := 0;
  v_now timestamptz := clock_timestamp();
begin
  select s.* into v_settings from public.storage_settings s where s.singleton for update;
  v_level := private.storage_teacher_level(v_settings);
  v_after := least(v_settings.notified_level, v_level);
  if v_level > v_after then
    insert into public.notifications as n
           (recipient_teacher_id, kind, level, dedupe_key, created_at, updated_at)
    select t.id, 'storage_threshold', v_level, 'storage_threshold:' || v_level || ':' || t.id, v_now, v_now
      from public.teachers t
    on conflict (dedupe_key) do update set updated_at = excluded.updated_at, read_at = null;
    get diagnostics v_sent = row_count;
    v_after := v_level;
  end if;
  if v_after <> v_settings.notified_level then
    update public.storage_settings set notified_level = v_after, updated_at = v_now where singleton;
  end if;
  return jsonb_build_object('level', v_level, 'notified_before', v_settings.notified_level,
                            'notified_after', v_after, 'sent', v_sent);
end
$$;
revoke all on function private.storage_teacher_level(public.storage_settings), private.storage_threshold_check()
  from public, anon, authenticated;

select cron.schedule('kemi-storage-threshold', '*/5 * * * *', 'select private.storage_threshold_check()');

-- ---------------------------------------------------------------------------
-- D01: ผลเทียบยอดพื้นที่ล่าสุด (0049) — แถบธงยอดต่างเกินเกณฑ์ · ประวัติเต็มทำใน P6-04c
-- ---------------------------------------------------------------------------
create function public.admin_storage_reconcile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return (select jsonb_build_object(
                   'finished_at', r.finished_at, 'b2_bytes', r.b2_bytes, 'db_bytes', r.db_assets_bytes + r.db_reserved_bytes,
                   'diff_bytes', r.diff_bytes, 'offset_bytes', r.offset_after_bytes,
                   'exceeds_threshold', r.exceeds_threshold)
            from public.storage_reconciliations r
           order by r.finished_at desc, r.id desc
           limit 1);
end
$$;
revoke all on function public.admin_storage_reconcile() from public, anon;
grant execute on function public.admin_storage_reconcile() to authenticated;
