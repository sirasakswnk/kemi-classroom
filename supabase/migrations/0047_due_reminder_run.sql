-- 0047_due_reminder_run: ตัวรันงานเตือน 24 ชม. ของ process-jobs (P6-02b) — TECHNICAL_DESIGN 9.1, 11
-- process-jobs ดึงงานด้วย jobs_claim (SKIP LOCKED) แล้วเรียก due_reminder_run ทีละงาน:
--   - ล็อกแถวงาน (private.jobs_running: FOR UPDATE + ต้องเป็น running) — ตัวทำงานที่ซ้อนกันรอแล้วเห็นว่างานปิดแล้ว → skip
--   - สร้างแจ้งเตือนด้วย private.send_due_reminders (0046) ซึ่งตรวจสถานะล่าสุดด้วยเวลาจริงของฐานข้อมูล:
--     ถึงคิวช้าจนเลยกำหนดส่ง (เช่น cron หยุดไป) / กำหนดเปลี่ยนแล้ว / ปิดรับ / ภาคเรียนจบ → ไม่สร้าง แล้วปิดงาน
--   - สร้างแจ้งเตือนและปิดงานในทรานแซกชันเดียว (ล้ม → ย้อนทั้งคู่ ตัวทำงานเรียก jobs_fail ลองใหม่ตามรอบ)
-- ผล: { action: 'done', sent } | { action: 'skip' } (งานไม่ได้อยู่ในมือผู้เรียกแล้ว)
create function public.due_reminder_run(p_job_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job private.jobs;
  v_sent integer;
begin
  v_job := private.jobs_running(p_job_id);
  if v_job.id is null or v_job.kind <> 'due_reminder' then
    return jsonb_build_object('action', 'skip');
  end if;
  v_sent := private.send_due_reminders((v_job.payload ->> 'assignment_id')::uuid,
                                       (v_job.payload ->> 'due_at')::timestamptz,
                                       clock_timestamp());
  perform public.jobs_complete(p_job_id, 'sent ' || v_sent);
  return jsonb_build_object('action', 'done', 'sent', v_sent);
end
$$;
revoke all on function public.due_reminder_run(bigint) from public, anon, authenticated;
grant execute on function public.due_reminder_run(bigint) to service_role;
