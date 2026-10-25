-- 0052_admin_b2_usage_class_c: ตัวนับ B2 ใน D01 แสดงคำขอ Class C ของการเทียบยอดพื้นที่ (P6-04c, ค้างจาก P6-04a)
-- เพิ่ม class_c_requests ในแต่ละแหล่ง และงบ Class C ต่อวัน/ต่อรอบของการเทียบ (0049) — ส่วนอื่นเหมือน 0023 เดิม
create or replace function public.admin_b2_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_day date := (clock_timestamp() at time zone 'UTC')::date;
  v_settings public.storage_settings;
begin
  if not private.is_admin() then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  select s.* into v_settings from public.storage_settings s where s.singleton;
  return jsonb_build_object(
    'day', v_day,
    'sources', coalesce((select jsonb_object_agg(u.source, jsonb_build_object(
                                 'class_b_requests', u.class_b_requests, 'class_c_requests', u.class_c_requests,
                                 'download_bytes', u.download_bytes, 'copy_bytes', u.copy_bytes))
                           from public.b2_daily_usage u where u.day = v_day), '{}'::jsonb),
    'view_budget_requests', v_settings.daily_view_budget_requests,
    'view_budget_bytes', v_settings.daily_view_budget_bytes,
    'reconcile_budget_requests', v_settings.reconcile_daily_budget_requests,
    'reconcile_run_max_requests', v_settings.reconcile_run_max_requests,
    'jobs', (select jsonb_build_object(
                'pending', count(*) filter (where j.status = 'pending'),
                'running', count(*) filter (where j.status = 'running'),
                'failed', count(*) filter (where j.status = 'failed'))
               from private.jobs j));
end
$$;
