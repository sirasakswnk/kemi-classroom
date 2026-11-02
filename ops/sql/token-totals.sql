/* ยอดโทเคนสำหรับเทียบตอนกู้คืนแบบตรงตัว (P7-01) — ops/backup.sh เขียนลง meta.json, ops/restore-test.sh เทียบ
   balance_digest = md5 ของยอดรายกระเป๋า (student_id:term_id:balance เรียงตามคีย์) จับยอดที่ย้ายไปผิดคนได้แม้ยอดรวมเท่าเดิม
   เป็นตัวเลขและ hash เท่านั้น ไม่มีชื่อหรือข้อมูลที่อ่านได้ · ใช้ comment แบบนี้เท่านั้น เพราะ backup.sh ส่งเป็นบรรทัดเดียว */
select jsonb_build_object(
         'wallets', count(*),
         'balance_sum', coalesce(sum(w.balance), 0),
         'balance_digest', md5(coalesce(string_agg(w.student_id::text || ':' || w.term_id::text || ':' || w.balance::text,
                                                   ',' order by w.student_id, w.term_id), '')))
  from public.wallets w;
