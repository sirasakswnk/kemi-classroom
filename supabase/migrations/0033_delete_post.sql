-- 0033_delete_post: ลบการบ้าน/ประกาศแบบ cascade (N4) — P4-09
-- SYSTEM_SPEC N4; TECHNICAL_DESIGN ส่วน 10 (DELETE /posts/:id), 9 (ลบไฟล์แบบระบุ version_id ผ่านคิว), 9.1 (ธง maintenance_locks);
-- UX_DESIGN ส่วน 9 (หน้าต่างลบงานสีแดง: จำนวนที่จะถูกลบ + ติ๊กยืนยัน + ดาวน์โหลด CSV ก่อนลบ)
--
-- post_delete_preview(post)   อ่านอย่างเดียว: ยอดที่จะถูกลบ (ครูเจ้าของห้อง/ผู้ดูแล ไม่ต้องโหมดผู้ดูแล)
--   ผล: { post_id, classroom_id, kind, title, submissions, grades, comments, files }
--     submissions = งานส่ง (ต่อนักเรียน) · grades = ผลตรวจ · comments = ความคิดเห็นที่ยังไม่ถูกยกเลิก
--     files = ไฟล์ที่ผูกอยู่ทั้งหมดของโพสต์ (ไฟล์โจทย์ + ไฟล์เฉลย + ไฟล์ของงานส่งชุดปัจจุบันของทุกคน)
-- delete_post(post, expected jsonb, request_key, admin_mode)   ครู หรือผู้ดูแลในโหมดผู้ดูแลเท่านั้น
--   expected = { submissions, grades, comments, files } ที่หน้าจอแสดงให้ครูเห็น — ตรวจซ้ำกับข้อมูลปัจจุบัน "หลังล็อกแถว"
--   ใน transaction เดียวกับที่ลบ ไม่ตรง → preview_changed (หน้าต่างโหลดยอดใหม่ ครูดูแล้วยืนยันอีกครั้ง)
--   ลบใน transaction เดียว: ผลตรวจ, สิทธิ์แก้, ความคิดเห็น, ไฟล์ที่ผูก, งานส่ง, เฉลย, การบ้าน/โพสต์ (cascade ที่เหลือ เช่น batch ของโพสต์)
--   ไฟล์ทุกตัวที่เคยผูก (+ ไฟล์พร้อมใช้ที่ยังไม่ผูกใน batch ของโพสต์นี้) → เลิกผูก → deleting → private.enqueue_delete_asset
--   (งาน delete_asset ลบ B2 แบบระบุ version_id ภายหลัง; ฟังก์ชันนี้ไม่เรียก B2 และงานลบรอเมื่อมีธง maintenance_locks ตาม
--   delete_asset_begin 0023) — ยอดพื้นที่ลดเมื่องานลบเสร็จ (assets แถวหายตอน delete_asset_finish)
--   ไม่แตะกระเป๋า/รางวัล/ของสะสม: โทเคนที่ได้ไปแล้วไม่ถูกเรียกคืน (N4) — ระยะ 5 ต้องไม่ผูก FK ที่ทำให้ลบโพสต์ไม่ได้
--   จุดเชื่อมระยะ 6: ทำให้ notifications ที่อ้างถึงโพสต์นี้หมดความเกี่ยวข้องใน transaction นี้ (ตาราง notifications ยังไม่มี)
--   ทำได้ทุกสถานะ (แม้มีงานส่ง/ตรวจแล้ว/เผยแพร่เฉลยแล้ว/จบภาคเรียน — N4); คำขอซ้ำด้วย request key เดิมได้ผลเดิม
-- ลำดับล็อก: term_control (share) → ห้อง → โพสต์ → งาน → (แถวย่อยที่ลบ) — เดียวกับ update_post/grade_submission
-- รหัสที่หน้าเว็บอาจเจอ: preview_changed, forbidden, admin_mode_required — รหัสภายใน: invalid_request, request_key_required,
--   request_key_conflict
-- ผล delete_post: { post_id, classroom_id, kind, title, deleted: { submissions, grades, comments, revision_permissions, files },
--                   queued_files }

create function public.post_delete_preview(p_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.posts;
begin
  select p.* into v_post from public.posts p where p.id = p_post_id;
  if v_post.id is null or not private.can_teach_classroom(v_post.classroom_id) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return jsonb_build_object(
    'post_id', v_post.id,
    'classroom_id', v_post.classroom_id,
    'kind', v_post.kind,
    'title', v_post.title) || private.post_delete_counts(p_post_id);
end
$$;
revoke all on function public.post_delete_preview(uuid) from public, anon;
grant execute on function public.post_delete_preview(uuid) to authenticated;

-- ยอดที่ใช้ทั้งหน้าต่างและตรวจซ้ำตอนลบ (ไม่ GRANT ใคร)
create function private.post_delete_counts(p_post_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'submissions', (select count(*) from public.submissions s where s.assignment_id = p_post_id),
    'grades', (select count(*) from public.grades g
                 join public.submissions s on s.id = g.submission_id where s.assignment_id = p_post_id),
    'comments', (select count(*) from public.comments c where c.assignment_id = p_post_id and c.retracted_at is null),
    'files', (select count(*) from public.attachments t
               where t.post_id = p_post_id or t.solution_id = p_post_id
                  or t.submission_id in (select s.id from public.submissions s where s.assignment_id = p_post_id)))
$$;

create function public.delete_post(
  p_post_id uuid,
  p_expected jsonb,
  p_request_key uuid,
  p_admin_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_operation text;
  v_prior jsonb;
  v_classroom_id uuid;
  v_post public.posts;
  v_counts jsonb;
  v_now timestamptz := clock_timestamp();
  v_submission_ids uuid[];
  v_asset_ids uuid[];
  v_asset public.assets;
  v_queued integer := 0;
  v_grades integer;
  v_comments integer;
  v_perms integer;
  v_files integer;
  v_subs integer;
  v_result jsonb;
begin
  v_account := private.require_teacher(p_admin_mode);
  if p_request_key is null then
    raise exception using errcode = 'P0001', message = 'request_key_required';
  end if;
  -- รูปแบบยอดที่คาดไว้: ต้องมีครบสี่ค่าเป็นจำนวนเต็มไม่ติดลบ (หน้าเว็บส่งถูกเสมอ ผิดได้จากบั๊กเท่านั้น)
  if jsonb_typeof(p_expected) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_expected) k
                 where k <> all (array['submissions', 'grades', 'comments', 'files']))
     or exists (select 1 from unnest(array['submissions', 'grades', 'comments', 'files']) k
                 where private.jsonb_int(p_expected -> k) is null or private.jsonb_int(p_expected -> k) < 0) then
    raise exception using errcode = 'P0001', message = 'invalid_request';
  end if;

  v_operation := 'delete_post:' || md5(jsonb_build_object('post_id', p_post_id, 'expected', p_expected)::text);
  perform pg_advisory_xact_lock(hashtextextended('receipt:' || v_account.id || ':' || p_request_key, 0));
  v_prior := private.receipt_lookup(v_account.id, p_request_key, v_operation);
  if v_prior is not null then
    return v_prior;
  end if;

  -- ลำดับล็อก: term_control (share) → ห้อง (ครูเจ้าของห้อง/ผู้ดูแลในโหมดผู้ดูแล) → โพสต์ → งาน
  perform 1 from public.term_control c where c.singleton for share;
  select p.classroom_id into v_classroom_id from public.posts p where p.id = p_post_id;
  if v_classroom_id is null then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform private.require_classroom_teacher(v_classroom_id, p_admin_mode);
  select p.* into v_post from public.posts p where p.id = p_post_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  perform 1 from public.assignments a where a.post_id = p_post_id for update;

  -- ตรวจยอดที่หน้าจอแสดงกับข้อมูลปัจจุบันหลังล็อก: งานที่ส่ง/ตรวจ/ความคิดเห็นเพิ่มระหว่างเปิดหน้าต่าง → ให้ดูยอดใหม่ก่อนยืนยัน
  v_counts := private.post_delete_counts(p_post_id);
  if (v_counts -> 'submissions') is distinct from (p_expected -> 'submissions')
     or (v_counts -> 'grades') is distinct from (p_expected -> 'grades')
     or (v_counts -> 'comments') is distinct from (p_expected -> 'comments')
     or (v_counts -> 'files') is distinct from (p_expected -> 'files') then
    raise exception using errcode = 'P0001', message = 'preview_changed';
  end if;

  -- ไฟล์ทั้งหมดที่ผูกกับโพสต์นี้ (โจทย์ เฉลย งานส่งของทุกคน) + ไฟล์พร้อมใช้ที่ยังไม่ผูกใน batch ของโพสต์นี้ (อัปโหลดค้าง)
  select coalesce(array_agg(s.id), '{}') into v_submission_ids from public.submissions s where s.assignment_id = p_post_id;
  select coalesce(array_agg(x.asset_id), '{}') into v_asset_ids
    from (select t.asset_id from public.attachments t
           where t.post_id = p_post_id or t.solution_id = p_post_id or t.submission_id = any(v_submission_ids)
          union
          select a.id from public.assets a
            join public.upload_batches b on b.id = a.upload_batch_id
           where b.post_id = p_post_id and a.status = 'ready'
             and not exists (select 1 from public.attachments t where t.asset_id = a.id)) x;
  -- ล็อกแถวไฟล์ตามลำดับ id (ผู้ผูก/sweeper ล็อกแถวเดียวกัน)
  perform 1 from public.assets a where a.id = any(v_asset_ids) order by a.id for update;

  -- ลบทุกอย่างของโพสต์ใน transaction เดียว (ผลตรวจก่อนความคิดเห็น เพราะ grades อ้างความคิดเห็นเหตุผลการหัก)
  delete from public.grades g where g.submission_id = any(v_submission_ids);
  get diagnostics v_grades = row_count;
  delete from public.revision_permissions r where r.submission_id = any(v_submission_ids);
  get diagnostics v_perms = row_count;
  delete from public.comments c where c.assignment_id = p_post_id;
  get diagnostics v_comments = row_count;
  delete from public.attachments t
   where t.post_id = p_post_id or t.solution_id = p_post_id or t.submission_id = any(v_submission_ids);
  get diagnostics v_files = row_count;
  delete from public.submissions s where s.assignment_id = p_post_id;
  get diagnostics v_subs = row_count;
  delete from public.solutions s where s.assignment_id = p_post_id;
  -- ที่เหลือ (assignments, upload_batches ของโพสต์) ตาม on delete cascade
  delete from public.posts p where p.id = p_post_id;

  -- ไฟล์: เลิกผูกแล้ว → deleting → งานลบ B2 แบบระบุ version_id (ไม่เรียกบริการภายนอกที่นี่)
  for v_asset in
    update public.assets set status = 'deleting', delete_requested_at = v_now
     where id = any(v_asset_ids) and status = 'ready'
    returning *
  loop
    perform private.enqueue_delete_asset(v_asset, 'post_deleted');
    v_queued := v_queued + 1;
  end loop;

  v_result := jsonb_build_object(
    'post_id', p_post_id,
    'classroom_id', v_post.classroom_id,
    'kind', v_post.kind,
    'title', v_post.title,
    'deleted', jsonb_build_object('submissions', v_subs, 'grades', v_grades, 'comments', v_comments,
                                  'revision_permissions', v_perms, 'files', v_files),
    'queued_files', v_queued);
  perform private.receipt_store(v_account.id, p_request_key, v_operation, v_result);
  return v_result;
end
$$;
revoke all on function public.delete_post(uuid, jsonb, uuid, boolean) from public, anon;
grant execute on function public.delete_post(uuid, jsonb, uuid, boolean) to authenticated;
