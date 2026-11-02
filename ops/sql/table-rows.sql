/* จำนวนแถวทุกตารางใน public/private เป็น JSON บรรทัดเดียว — ops/backup.sh เขียนลง meta.json ณ snapshot เดียวกับ dump
   และ ops/restore-test.sh เทียบกับฐานข้อมูลที่กู้แบบตรงตัว (ใช้ไฟล์เดียวกันเพื่อไม่ให้สองที่นับต่างกัน)
   ไม่นับตารางที่ไม่สำรองข้อมูล · ไม่มีข้อมูลนักเรียน · ใช้ comment แบบนี้เท่านั้น เพราะ backup.sh ส่งเป็นบรรทัดเดียว */
select coalesce(jsonb_object_agg(t.name, t.n order by t.name), '{}')
  from (select n.nspname || '.' || c.relname as name,
               (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname),
                                                    false, true, '')))[1]::text::bigint as n
          from pg_catalog.pg_class c
          join pg_catalog.pg_namespace n on n.oid = c.relnamespace
         where n.nspname in ('public', 'private') and c.relkind in ('r', 'p')
           and n.nspname || '.' || c.relname not in ('private.backup_manifests', 'private.backup_run_files')) t;
