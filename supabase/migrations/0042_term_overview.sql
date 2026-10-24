-- 0042_term_overview: ข้อมูลหน้า T07 ภาคเรียนและข้อมูลเก่า (อ่านอย่างเดียว)
-- อ้างอิง: UX_DESIGN T07 + แบบ v2 tTerm; TECHNICAL_DESIGN 7, 12; SYSTEM_SPEC J9.2
-- ตัวเลขรวมทุกห้องของภาคเรียนปัจจุบัน (ภาคเรียนใช้ร่วมกันทุกห้อง 1.2) — ครู หรือผู้ดูแลในโหมดผู้ดูแล
-- จุดเริ่มนับอายุข้อมูล = ended_at (กดจบ) หรือ superseded_at (เริ่มเทอมใหม่ทับ) — ผู้ใช้ตัดสิน 24 ต.ค. 2026
-- ไฟล์ครบอายุ +60 วัน คะแนน/เวลาส่ง/ความคิดเห็น +1 ปี (J9.2) — ดาวน์โหลด/ยืนยันลบมากับระยะ 6

-- ผล: { term: { term_id, name, status, epoch, started_at, ended_at },
--       classrooms, students, tokens, waiting,
--       old_terms: [{ id, name, how ('end' | 'start'), retention_from, files_due, data_due }] (ใหม่ → เก่า) }
-- ภาคเรียนปัจจุบันที่กดจบแล้วอยู่ใน old_terms ด้วย (UX T07: ขึ้นใน “ข้อมูลภาคเรียนเก่า” พร้อม “กดจบ …”)
create function public.term_overview(p_admin_mode boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_term_id uuid;
begin
  perform private.require_teacher(p_admin_mode);
  select c.term_id into v_term_id from public.term_control c where c.singleton;
  if v_term_id is null then
    raise exception using errcode = 'P0001', message = 'no_term';
  end if;

  return jsonb_build_object(
    'term', private.term_state(),
    'classrooms', (select count(*)::integer from public.classrooms c where c.term_id = v_term_id),
    'students', (select count(distinct m.student_id)::integer
                   from public.memberships m join public.classrooms c on c.id = m.classroom_id
                  where c.term_id = v_term_id),
    'tokens', (select coalesce(sum(w.balance), 0)::integer from public.wallets w where w.term_id = v_term_id),
    'waiting', (select count(*)::integer
                  from public.submissions s
                  join public.posts p on p.id = s.assignment_id
                  join public.classrooms c on c.id = p.classroom_id
                 where c.term_id = v_term_id and not private.submission_latest_graded(s.id)),
    'old_terms', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id,
               'name', t.name,
               'how', case when t.ended_at is not null then 'end' else 'start' end,
               'retention_from', r.from_at,
               'files_due', r.from_at + interval '60 days',
               'data_due', r.from_at + interval '1 year') order by r.from_at desc, t.id)
        from public.terms t
        cross join lateral (select coalesce(t.ended_at, t.superseded_at) as from_at) r
       where r.from_at is not null), '[]'::jsonb));
end
$$;
revoke all on function public.term_overview(boolean) from public, anon;
grant execute on function public.term_overview(boolean) to authenticated;
