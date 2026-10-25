-- 0051_admin_jobs: รายการงานเบื้องหลังที่ล้มเหลวใน D01 + ปุ่มลองใหม่ (P6-04c) — TECHNICAL_DESIGN 9.1, BUILD_PLAN 10 ระยะ 6
-- ผู้ดูแลเท่านั้น (private.is_admin) · ไม่ส่ง payload (มี key ไฟล์/รหัสนักเรียน/งาน) — แสดงแค่ชนิด เวลา จำนวนครั้ง และ error แบบย่อ
-- ลองใหม่ = เปลี่ยนงาน failed กลับเป็น pending (attempts 0, run_at ตอนนี้) ให้ process-jobs ดึงตามรอบปกติ:
--   - ล็อกแถวงาน (FOR UPDATE) แล้วจึงตัดสิน — กดซ้ำหรือกดพร้อมกัน รายที่สองเห็นว่างานไม่ใช่ failed แล้ว → ไม่ทำอะไร
--   - ไม่แตะงาน pending/running (ไม่มีทางทำให้งานเดียวกันถูกรันซ้อน)
--   - ตัวรันตรวจความเกี่ยวข้องเองตามเดิม (due_reminder_run ปิดงานที่เลยกำหนด/ปิดรับ/ส่งแล้วโดยไม่แจ้ง,
--     delete_asset_begin ตรวจธงสำรอง/ยังผูก/ไม่มีแล้ว) ฟังก์ชันนี้ไม่ข้ามขั้นใด
--   - storage_reconcile ที่มีงานเทียบอื่นค้างอยู่ (เช่นงานของวันใหม่) → ไม่ลองใหม่ (superseded) กันการเทียบสองงานพร้อมกัน

-- error ที่เก็บเป็นรหัสจากตัวทำงาน (เช่น b2_500, b2_network, due_reminder_P0001) — กรองเหลือตัวอักษรรหัสและตัดความยาว
create function private.job_error_brief(p_error text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p_error, ''), '[^A-Za-z0-9_:. -]', '', 'g'),
                                          '\s+', ' ', 'g')), 80), '')
$$;
revoke all on function private.job_error_brief(text) from public, anon, authenticated;

-- ผล: { failed_total, items: [{ id, kind, attempts, error, created_at, failed_at }] } ล่าสุดก่อน ไม่เกิน 50
create function public.admin_failed_jobs()
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
  return jsonb_build_object(
    'failed_total', (select count(*) from private.jobs j where j.status = 'failed'),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
                                 'id', x.id, 'kind', x.kind, 'attempts', x.attempts,
                                 'error', private.job_error_brief(x.last_error),
                                 'created_at', x.created_at, 'failed_at', x.updated_at)
                               order by x.updated_at desc, x.id desc)
                         from (select j.* from private.jobs j where j.status = 'failed'
                                order by j.updated_at desc, j.id desc limit 50) x), '[]'::jsonb));
end
$$;

-- ผล: { result: 'queued' | 'not_failed' | 'superseded', status } — not_failed = ไม่มีงานนี้หรือไม่ใช่ failed แล้ว
create function public.admin_retry_job(p_job_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
begin
  if not private.is_admin() then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select j.* into v_job from private.jobs j where j.id = p_job_id for update;
  if v_job.id is null or v_job.status <> 'failed' then
    return jsonb_build_object('result', 'not_failed', 'status', v_job.status);
  end if;
  if v_job.kind = 'storage_reconcile'
     and exists (select 1 from private.jobs j
                  where j.kind = 'storage_reconcile' and j.status in ('pending', 'running') and j.id <> v_job.id) then
    return jsonb_build_object('result', 'superseded', 'status', v_job.status);
  end if;
  update private.jobs
     set status = 'pending', attempts = 0, run_at = clock_timestamp(), locked_at = null,
         last_error = left('retry: ' || coalesce(v_job.last_error, ''), 500), updated_at = clock_timestamp()
   where id = p_job_id;
  return jsonb_build_object('result', 'queued', 'status', 'pending');
end
$$;

revoke all on function public.admin_failed_jobs(), public.admin_retry_job(bigint) from public, anon;
grant execute on function public.admin_failed_jobs(), public.admin_retry_job(bigint) to authenticated;
