// P7-04: ทดสอบข้ามคนผ่าน RPC/Edge จริง (TECHNICAL_BUILD_PLAN ส่วน 11 ข้อ 5) — รันในแท็บของเว็บที่ล็อกอินอยู่
// (Claude in Chrome javascript_tool: เนื้อไฟล์นี้ + `await crossPersonCheck({...})`)
// - ใช้ JWT ของผู้ที่ล็อกอินจาก localStorage ของหน้า ไม่พิมพ์ออก · ผลแสดงแค่สถานะ/รหัส/จำนวนแถว ไม่แสดงเนื้อข้อมูลของ B
// - mode 'student': นักเรียน A อ่าน/เขียนของนักเรียน B (ห้องเดียวกัน) + เรียกคำสั่งครู/ผู้ดูแล (บัญชีนอก allowlist)
// - mode 'admin': ผู้ดูแลนอกโหมดผู้ดูแลเรียกคำสั่งเขียนของครู
// - คำสั่งเขียนใช้ id ที่ไม่มีอยู่จริงเมื่อทำได้ — ถ้าการตรวจบทบาทหายไปจะล้มด้วยรหัสอื่นแทนที่จะแก้ข้อมูล
//   (ยกเว้น post_comment ในช่องของ B ที่ต้องใช้ id จริงจึงพิสูจน์ได้)
// - ทุกข้อคาดว่า “ถูกปฏิเสธ” หรือ “ได้ว่าง” — ok = true คือปลอดภัย
async function crossPersonCheck(cfg) {
  const { ref, key, mode, B } = cfg
  const SB = `https://${ref}.supabase.co`
  const session = JSON.parse(localStorage.getItem(`sb-${ref}-auth-token`) ?? 'null')
  if (!session?.access_token) return [{ name: 'session', ok: false, got: 'ไม่ได้ล็อกอิน' }]
  const h = {
    apikey: key,
    Authorization: `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  }
  const FAKE = '00000000-0000-4000-8000-00000000f00d'
  const key4 = () => crypto.randomUUID()
  const out = []
  const rec = (name, ok, got) => out.push({ name, ok, got })
  const json = async (r) => r.json().catch(() => null)
  const shape = (b) => (Array.isArray(b) ? `${b.length} แถว` : b === null ? 'null' : typeof b)

  const rest = async (path) => {
    const r = await fetch(`${SB}/rest/v1/${path}`, { headers: h })
    return [r.status, await json(r)]
  }
  const rpc = async (fn, args) => {
    const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: h, body: JSON.stringify(args) })
    return [r.status, await json(r)]
  }
  const edge = async (path, body) => {
    const r = await fetch(`${SB}/functions/v1/${path}`, { method: 'POST', headers: h, body: JSON.stringify(body) })
    return [r.status, await json(r)]
  }
  // ได้ว่าง (RLS กรอง) หรือถูกปฏิเสธทั้งตาราง (ไม่มี GRANT เช่น notifications — อ่านผ่าน RPC เท่านั้น) = ปลอดภัย
  const expectEmpty = async (name, path) => {
    const [s, b] = await rest(path)
    rec(name, (s === 200 && Array.isArray(b) && b.length === 0) || s === 401 || s === 403, `${s} ${shape(b)}`)
  }
  const expectError = async (name, call, codes) => {
    const [s, b] = await call
    const code = s >= 400 ? (b?.message ?? `http_${s}`) : null
    rec(name, code !== null && (!codes || codes.includes(code)), code ? `${s} ${code}` : `${s} สำเร็จ (${shape(b)})`)
  }

  if (mode === 'student') {
    // ตารางผ่าน PostgREST (RLS) — ของ B ต้องไม่เห็นเลย
    await expectEmpty('REST submissions ของ B', `submissions?student_id=eq.${B.student}&select=id`)
    await expectEmpty('REST grades ของ B', `grades?submission_id=eq.${B.submission}&select=submission_id`)
    await expectEmpty('REST comments ของ B', `comments?student_id=eq.${B.student}&select=id`)
    await expectEmpty('REST owned_charms ของ B', `owned_charms?student_id=eq.${B.student}&select=charm_id`)
    await expectEmpty('REST wallets ของ B', `wallets?student_id=eq.${B.student}&select=balance`)
    await expectEmpty('REST notifications ของ B', `notifications?recipient_student_id=eq.${B.student}&select=id`)
    const assets = `(${B.assets.join(',')})`
    await expectEmpty('REST assets ไฟล์งานของ B', `assets?id=in.${assets}&select=id`)
    await expectEmpty('REST attachments ไฟล์งานของ B', `attachments?asset_id=in.${assets}&select=id`)
    await expectEmpty('REST upload_batches ของ B', `upload_batches?id=in.(${B.batches.join(',')})&select=id`)
    // RPC
    await expectError('RPC comment_thread ช่องของ B', rpc('comment_thread', { p_assignment_id: B.assignment, p_student_id: B.student }))
    const [as, ab] = await rpc('authorize_files', { p_asset_ids: B.assets })
    rec('RPC authorize_files ไฟล์ของ B → ไม่ได้สักไฟล์', as === 200 && Array.isArray(ab) && ab.length === 0, `${as} ${shape(ab)}`)
    // ต้องใช้งานที่ยังเปิด (B.liveAssignment ในห้องของ A) — งานในภาคเรียนที่จบแล้วถูกปฏิเสธด้วย term_ended ก่อนตรวจเจ้าของช่อง
    await expectError('RPC post_comment ลงช่องของ B', rpc('post_comment', { p_assignment_id: B.liveAssignment ?? B.assignment, p_student_id: B.student, p_body: 'ทดสอบสิทธิ์ P7-04', p_request_key: key4(), p_admin_mode: false }), ['forbidden', 'not_member'])
    await expectError('RPC comment_thread งานที่เปิด ช่องของ B', rpc('comment_thread', { p_assignment_id: B.liveAssignment ?? B.assignment, p_student_id: B.student }), ['forbidden', 'not_member'])
    // คำสั่งครู/ผู้ดูแล (บัญชีนี้ไม่อยู่ใน allowlist ครู)
    await expectError('RPC teacher_grade_table', rpc('teacher_grade_table', { p_classroom_id: B.classroom }))
    await expectError('RPC teacher_submission_list', rpc('teacher_submission_list', { p_assignment_id: B.assignment }))
    await expectError('RPC roster_overview', rpc('roster_overview', { p_admin_mode: false }))
    await expectError('RPC term_overview', rpc('term_overview', { p_admin_mode: false }))
    await expectError('RPC rebind_preview', rpc('rebind_preview', { p_student_id: B.student, p_email: 'x@example.com', p_admin_mode: false }))
    await expectError('RPC admin_teachers', rpc('admin_teachers', {}))
    await expectError('RPC admin_failed_jobs', rpc('admin_failed_jobs', {}))
    await expectError('RPC wallet_adjust (id สมมติ)', rpc('wallet_adjust', { p_student_id: FAKE, p_delta: 5, p_expected_version: 0, p_request_key: key4(), p_admin_mode: false }), ['teacher_required', 'forbidden'])
    await expectError('RPC grade_submission (id สมมติ)', rpc('grade_submission', { p_submission_id: FAKE, p_raw: 1, p_pass: true, p_override_pct: null, p_reason: null, p_seen_revision: 1, p_expected_version: 0, p_request_key: key4(), p_admin_mode: false }), ['teacher_required', 'forbidden'])
    await expectError('RPC export_term_data', rpc('export_term_data', { p_term_id: FAKE, p_admin_mode: false }), ['teacher_required', 'forbidden'])
    // Edge Functions
    await expectError('EDGE files/sign ไฟล์งานของ B', edge('files/sign', { asset_ids: B.assets.slice(0, 3), mode: 'view' }), ['forbidden'])
    await expectError('EDGE uploads complete ชุดของ B', edge(`uploads/${B.batches[0]}/complete`, { item: 1 }), ['forbidden'])
    await expectError('EDGE files/exports', edge('files/exports', { term_id: FAKE }), ['teacher_required', 'forbidden'])
  }

  if (mode === 'admin') {
    const codes = ['admin_mode_required']
    await expectError('ADMIN wallet_adjust นอกโหมด (id สมมติ)', rpc('wallet_adjust', { p_student_id: FAKE, p_delta: 5, p_expected_version: 0, p_request_key: key4(), p_admin_mode: false }), codes)
    await expectError('ADMIN grade_submission นอกโหมด (id สมมติ)', rpc('grade_submission', { p_submission_id: FAKE, p_raw: 1, p_pass: true, p_override_pct: null, p_reason: null, p_seen_revision: 1, p_expected_version: 0, p_request_key: key4(), p_admin_mode: false }), codes)
    await expectError('ADMIN create_classroom นอกโหมด (ครูสมมติ)', rpc('create_classroom', { p_name: 'ทดสอบสิทธิ์', p_description: '', p_request_key: key4(), p_teacher_id: FAKE, p_admin_mode: false }), codes)
    await expectError('ADMIN save_charm นอกโหมด', rpc('save_charm', { p_charm: {}, p_expected_version: 0, p_request_key: key4(), p_admin_mode: false }), codes)
    await expectError('ADMIN post_comment นอกโหมด (ช่องของ B)', rpc('post_comment', { p_assignment_id: B.assignment, p_student_id: B.student, p_body: 'ทดสอบสิทธิ์ P7-04', p_request_key: key4(), p_admin_mode: false }), codes)
    await expectError('ADMIN export_term_data นอกโหมด', rpc('export_term_data', { p_term_id: FAKE, p_admin_mode: false }), codes)
    await expectError('ADMIN EDGE files/exports นอกโหมด', edge('files/exports', { term_id: FAKE }), codes)
  }
  return out
}
