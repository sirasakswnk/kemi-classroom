-- ตั้งบัญชีผู้ดูแลแรกบน kemi-prod (P7-06; ops/prod-setup.md ข้อ 5.5) — ผู้ใช้รันเองใน Dashboard → SQL Editor ของ kemi-prod
-- เหตุ: ensure_account() ไม่ตั้ง role 'admin' ให้ใคร (0002_accounts: ตั้งโดยผู้พัฒนาในฐานข้อมูลเท่านั้น)
-- ก่อนรัน: ล็อกอินบัญชีผู้ดูแลที่ https://kemi-classroom.pages.dev หนึ่งครั้ง (ได้บทบาทนักเรียนก่อนตามแบบ)
-- วิธีใช้: คัดลอกทั้งไฟล์ไปวางใน SQL Editor → แก้ 'ใส่อีเมลผู้ดูแลที่นี่' เป็นอีเมล Google ของผู้ดูแลในหน้า SQL Editor
--         เท่านั้น (ห้ามแก้ไฟล์นี้ใน repo ห้ามส่งอีเมลในแชต) → Run → ต้องได้ตาราง role/จำนวนที่มี admin 1
-- ปลอดภัยต่อการรันซ้ำ: ถ้าเป็น admin อยู่แล้วจะแจ้งว่าไม่มีอะไรเปลี่ยน · เปลี่ยนได้ครั้งละ 1 บัญชีเท่านั้น
do $$
declare
  v_email text := lower(btrim('ใส่อีเมลผู้ดูแลที่นี่'));
  v_found integer;
  v_changed integer;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'ยังไม่ได้ใส่อีเมลผู้ดูแล (แก้ข้อความในบรรทัด v_email ก่อนกด Run)';
  end if;
  select count(*) into v_found from public.accounts a where a.email = v_email and a.provider = 'google';
  if v_found = 0 then
    raise exception 'ไม่พบบัญชีนี้ — ล็อกอินที่ https://kemi-classroom.pages.dev ด้วยบัญชีนี้หนึ่งครั้งก่อน แล้วรันใหม่';
  elsif v_found > 1 then
    raise exception 'พบบัญชีที่ใช้อีเมลนี้ % บัญชี — หยุดแล้วบอก Claude (ไม่เปลี่ยนอะไร)', v_found;
  end if;
  update public.accounts a
     set role = 'admin', teacher_id = null, updated_at = clock_timestamp()
   where a.email = v_email and a.provider = 'google' and a.role <> 'admin';
  get diagnostics v_changed = row_count;
  raise notice '%', case when v_changed = 1 then 'ตั้งเป็นผู้ดูแลแล้ว — โหลดหน้าเว็บใหม่จะไปหน้า /admin'
                         else 'บัญชีนี้เป็นผู้ดูแลอยู่แล้ว ไม่มีอะไรเปลี่ยน' end;
end
$$;

-- ผล: จำนวนบัญชีแยกตามบทบาท (ไม่แสดงอีเมล) — ต้องมี admin 1
select role, count(*) as accounts from public.accounts group by role order by role;
