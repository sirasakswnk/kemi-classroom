-- 0038_collection: ตู้สะสมส่วนตัว (S05, GET /collection) และเครื่องรางที่แสดงข้างชื่อในแท็บสมาชิก (S02)
-- TECHNICAL_DESIGN ส่วน 8: เลือกแสดงได้หนึ่งชิ้น สมาชิกห้องเห็นเฉพาะชิ้นนี้ ตู้ทั้งหมดเป็นส่วนตัว
-- RLS ของ student_equipment/owned_charms เปิดเฉพาะเจ้าของและครู — เพื่อนเห็นชิ้นที่แสดงผ่าน classroom_view เท่านั้น

-- ---------------------------------------------------------------------------
-- 1. GET /collection — ทุกช่องตามลำดับ position
-- ---------------------------------------------------------------------------
-- ช่องที่ยังไม่ได้รับส่งแค่ระดับ (ไม่ส่งรหัส ชื่อ สัญลักษณ์ คำอธิบาย — แบบ v2 แสดง “?” + “ยังไม่ได้รับ” + ระดับ)
-- ผล: { total, owned, equipped_charm_id, items: [{ position, rarity_id, rarity_name, owned,
--        (เมื่อได้รับแล้ว) charm_id, name, description, symbol, obtained_at }] }
create function public.my_collection()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  v_student_id := private.require_current_student();
  return (
    select jsonb_build_object(
             'total', count(*)::integer,
             'owned', count(o.charm_id)::integer,
             'equipped_charm_id', (select e.charm_id from public.student_equipment e where e.student_id = v_student_id),
             'items', coalesce(jsonb_agg(
               case when o.charm_id is null then
                 jsonb_build_object('position', c.position, 'rarity_id', c.rarity_id, 'rarity_name', r.name,
                                    'owned', false)
               else
                 jsonb_build_object('position', c.position, 'rarity_id', c.rarity_id, 'rarity_name', r.name,
                                    'owned', true, 'charm_id', c.id, 'name', c.name, 'description', c.description,
                                    'symbol', c.symbol, 'obtained_at', o.obtained_at)
               end order by c.position), '[]'::jsonb))
      from public.charms c
      join public.rarities r on r.id = c.rarity_id
      left join public.owned_charms o on o.charm_id = c.id and o.student_id = v_student_id
  );
end
$$;
revoke all on function public.my_collection() from public, anon;
grant execute on function public.my_collection() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. classroom_view (0007) + เครื่องรางที่สมาชิกแต่ละคนเลือกแสดงข้างชื่อ
-- ---------------------------------------------------------------------------
-- members[].charm = { name, symbol, rarity_id } หรือ null (ไม่ได้เลือกแสดง) — ไม่ส่งรหัส/คำอธิบาย/ของอื่นในตู้
create or replace function public.classroom_view(p_classroom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
begin
  perform private.require_student_account();
  v_student_id := private.require_member(p_classroom_id);
  return (
    select jsonb_build_object(
             'id', c.id,
             'name', c.name,
             'description', c.description,
             'teacher_name', t.display_name,
             'term_name', tm.name,
             'member_count', (select count(*) from public.memberships x where x.classroom_id = c.id),
             'members', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'display_name', s.display_name,
                        'roll_number', e.roll_number,
                        'is_me', s.id = v_student_id,
                        'charm', case when ch.id is null then null
                                      else jsonb_build_object('name', ch.name, 'symbol', ch.symbol,
                                                              'rarity_id', ch.rarity_id) end
                      ) order by e.roll_number nulls last, s.display_name)
                 from public.memberships m
                 join public.students s on s.id = m.student_id
                 left join public.roster_entries e on e.student_id = s.id and e.term_id = c.term_id
                 left join public.student_equipment eq on eq.student_id = s.id
                 left join public.charms ch on ch.id = eq.charm_id
                where m.classroom_id = c.id
             ), '[]'::jsonb))
      from public.classrooms c
      join public.teachers t on t.id = c.teacher_id
      join public.terms tm on tm.id = c.term_id
     where c.id = p_classroom_id
  );
end
$$;
