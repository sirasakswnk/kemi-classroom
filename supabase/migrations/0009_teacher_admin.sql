-- 0009_teacher_admin: D01 ส่วนบัญชีครู — ผู้ดูแลเพิ่ม/เอาออก allowlist (TECHNICAL_DESIGN 3, 3.1 ข้อ 3; UX 12 L6)
-- หลัก: เฉพาะ role admin (หน้า D01 ของผู้ดูแลเอง ไม่ใช่การทำแทนครู จึงไม่ใช้ p_admin_mode)
--       ต้องเหลือรายการที่ใช้งานอยู่อย่างน้อย 1 รายการ (ตรวจใน transaction หลังล็อกทุกแถวที่ใช้งาน)
--       เอาออกแล้วปรับ accounts.role ของบัญชีที่ได้สิทธิ์จากรายการนั้นเป็นนักเรียนทันที (ไม่รอ ensure_account)
--       อีเมลในผลลัพธ์ปิดบางส่วนเสมอ (private.mask_email จาก 0008)

-- รายการที่ใช้งานอยู่ + ครูทั้งหมด (สำหรับเลือกเจ้าของบัญชีตอนเพิ่ม) + บัญชีผู้ดูแลเอง
-- ผล: { admin_email, teachers: [{ id, display_name }],
--       allowlist: [{ id, teacher_id, teacher_name, email, signed_in, created_at }] }
create function public.admin_teachers()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin public.accounts;
begin
  v_admin := private.require_admin();
  return jsonb_build_object(
    'admin_email', private.mask_email(v_admin.email),
    'teachers', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'display_name', t.display_name) order by t.display_name)
        from public.teachers t), '[]'::jsonb),
    'allowlist', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.id,
               'teacher_id', l.teacher_id,
               'teacher_name', t.display_name,
               'email', private.mask_email(l.email),
               'signed_in', l.provider_subject is not null,
               'created_at', l.created_at
             ) order by t.display_name, l.created_at)
        from private.teacher_allowlist l
        join public.teachers t on t.id = l.teacher_id
       where l.revoked_at is null), '[]'::jsonb));
end
$$;
grant execute on function public.admin_teachers() to authenticated;

-- เพิ่มบัญชีครูด้วยอีเมล Google: ผูกกับครูที่มีอยู่ (p_teacher_id) หรือสร้างครูคนใหม่ (p_new_teacher_name)
-- บัญชีนั้นได้บทบาทครูตอน ensure_account ครั้งถัดไป (เปิดเว็บ/โหลดหน้าใหม่) ซึ่งตรึง provider_subject ให้
create function public.admin_add_teacher(
  p_email text,
  p_teacher_id uuid default null,
  p_new_teacher_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name text := btrim(coalesce(p_new_teacher_name, ''));
  v_teacher public.teachers;
  v_id uuid;
begin
  perform private.require_admin();
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception using errcode = 'P0001', message = 'email_invalid';
  end if;
  if p_teacher_id is not null then
    select t.* into v_teacher from public.teachers t where t.id = p_teacher_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'teacher_required';
    end if;
  elsif v_name <> '' then
    if length(v_name) > 60 then
      raise exception using errcode = 'P0001', message = 'teacher_name_invalid';
    end if;
  else
    raise exception using errcode = 'P0001', message = 'teacher_required';
  end if;
  if exists (select 1 from private.teacher_allowlist l where l.email = v_email and l.revoked_at is null) then
    raise exception using errcode = 'P0001', message = 'teacher_email_exists';
  end if;

  if v_teacher.id is null then
    insert into public.teachers (display_name) values (v_name) returning * into v_teacher;
  end if;
  begin
    insert into private.teacher_allowlist (teacher_id, email)
    values (v_teacher.id, v_email)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'teacher_email_exists';
  end;
  return jsonb_build_object('id', v_id, 'teacher_id', v_teacher.id, 'teacher_name', v_teacher.display_name,
                            'email', private.mask_email(v_email), 'signed_in', false);
end
$$;
grant execute on function public.admin_add_teacher(text, uuid, text) to authenticated;

-- เอาออก: ล็อกทุกแถวที่ใช้งาน (สองคำขอพร้อมกันจะไม่ทำให้เหลือ 0) → ต้องเหลืออย่างน้อย 1 → revoked_at
-- → บัญชีครูที่ได้สิทธิ์จากแถวนี้และไม่ตรงแถวอื่นที่ใช้งานอยู่ กลายเป็นนักเรียนทันที (require_teacher/RLS อ่านสด)
-- เรียกซ้ำ/แถวที่ไม่มีหรือเอาออกแล้ว → removed = false
create function public.admin_remove_teacher(p_allowlist_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.teacher_allowlist;
  v_demoted integer;
begin
  perform private.require_admin();
  perform 1 from private.teacher_allowlist l where l.revoked_at is null for update;
  select l.* into v_row from private.teacher_allowlist l where l.id = p_allowlist_id;
  if not found or v_row.revoked_at is not null then
    return jsonb_build_object('id', p_allowlist_id, 'removed', false, 'demoted_accounts', 0);
  end if;
  if (select count(*) from private.teacher_allowlist l where l.revoked_at is null) <= 1 then
    raise exception using errcode = 'P0001', message = 'last_teacher';
  end if;

  update private.teacher_allowlist l set revoked_at = clock_timestamp() where l.id = v_row.id;

  update public.accounts a
     set role = 'student', teacher_id = null, updated_at = clock_timestamp()
   where a.role = 'teacher'
     and ((v_row.provider_subject is not null and a.provider_subject = v_row.provider_subject)
          or (v_row.email is not null and a.email = v_row.email))
     and not exists (
       select 1 from private.teacher_allowlist l
        where l.revoked_at is null
          and (l.provider_subject = a.provider_subject
               or (l.provider_subject is null and a.provider = 'google' and l.email = a.email)));
  get diagnostics v_demoted = row_count;

  return jsonb_build_object('id', v_row.id, 'removed', true, 'demoted_accounts', v_demoted);
end
$$;
grant execute on function public.admin_remove_teacher(uuid) to authenticated;
