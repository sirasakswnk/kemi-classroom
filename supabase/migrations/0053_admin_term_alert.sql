-- 0053_admin_term_alert: เตือนผู้ดูแลเมื่อภาคเรียนเปิดค้างเกิน 6 เดือน (P6-04d) — SYSTEM_SPEC J9.2 เสริม, TECHNICAL_DESIGN 12
-- คำนวณตอนอ่าน D01 (ไม่มีงานรายวัน — ผลเท่ากันเพราะเตือนแค่ในหน้าผู้ดูแล) จาก term_control ที่ยัง active:
--   เกิน 6 เดือน = เวลาตอนนี้ > เวลาเริ่ม + 6 เดือนตามปฏิทินไทย (Asia/Bangkok)
-- อ่านอย่างเดียว: ไม่ลบ ไม่เปลี่ยนสถานะ ไม่แจ้งครู
-- ผล: null (ไม่ต้องเตือน) | { term_id, name, started_at, due_at (ครบ 6 เดือน), days_open }
create function public.admin_term_alert()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_control public.term_control;
  v_due timestamptz;
begin
  if not private.is_admin() then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select c.* into v_control from public.term_control c where c.singleton;
  if v_control.singleton is null or v_control.status <> 'active' then
    return null;
  end if;
  v_due := ((v_control.started_at at time zone 'Asia/Bangkok') + interval '6 months') at time zone 'Asia/Bangkok';
  if v_now <= v_due then
    return null;
  end if;
  return (select jsonb_build_object(
                   'term_id', t.id, 'name', t.name, 'started_at', v_control.started_at, 'due_at', v_due,
                   'days_open', floor(extract(epoch from v_now - v_control.started_at) / 86400)::integer)
            from public.terms t where t.id = v_control.term_id);
end
$$;
revoke all on function public.admin_term_alert() from public, anon;
grant execute on function public.admin_term_alert() to authenticated;
