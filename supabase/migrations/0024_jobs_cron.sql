-- 0024_jobs_cron: รอบเรียกงานเบื้องหลังทุก 2 นาทีด้วย pg_cron + pg_net (P3-10, BUILD_PLAN 4.2 แถว 7a, TECHNICAL_DESIGN 9.1 ข้อ 1)
-- พิสูจน์ข้อ 13-2 (6 ต.ค. 2026): kemi-dev มี pg_cron 1.6.4 และ pg_net 0.20.4 ให้เปิด — ไม่ต้องใช้ GitHub Actions แทน
-- ทุกรอบ: งานประจำที่เป็น SQL ล้วน (jobs_maintenance) ทำในฐานข้อมูลเลย แล้ว **ปลุก Edge Function เฉพาะเมื่อมีงาน**
--   (งานถึงเวลา/ค้าง หรือแถว copying ค้าง) — ไม่เรียกฟังก์ชันทุก 2 นาทีโดยเปล่าประโยชน์
-- URL และรหัสลับอยู่ใน Supabase Vault (ชื่อ process_jobs_url, process_jobs_secret) ใส่ด้วย ops/jobs/set-secret.mjs ไม่อยู่ใน migration;
--   ไม่มีค่า (เช่น DB ในเครื่อง) = ทำเฉพาะงานประจำ ไม่เรียกฟังก์ชัน

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- cron เรียกในนาม postgres (ไม่ GRANT ใคร)
create function private.jobs_tick()
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_maintenance jsonb;
  v_url text;
  v_secret text;
  v_request bigint;
begin
  v_maintenance := public.jobs_maintenance();
  if not private.jobs_has_work() then
    return jsonb_build_object('maintenance', v_maintenance, 'called', false);
  end if;
  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'process_jobs_url';
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'process_jobs_secret';
  if v_url is null or v_secret is null then
    return jsonb_build_object('maintenance', v_maintenance, 'called', false, 'reason', 'not_configured');
  end if;
  -- pg_net ส่งแบบไม่รอผล (คิวของ pg_net) — ฟังก์ชันทำงานต่อจนเสร็จแม้ pg_net เลิกรอ
  v_request := net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-jobs-secret', v_secret),
    timeout_milliseconds := 30000);
  return jsonb_build_object('maintenance', v_maintenance, 'called', true, 'request_id', v_request);
end
$$;
revoke all on function private.jobs_tick() from public, anon, authenticated, service_role;

-- ทุก 2 นาที (เวลาใน pg_cron เป็น UTC — รอบถี่เท่ากันทั้งวัน) — ตั้งชื่อเดิมซ้ำ = อัปเดตตารางเวลาเดิม
select cron.schedule('kemi-process-jobs', '*/2 * * * *', 'select private.jobs_tick()');
