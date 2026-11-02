#!/usr/bin/env bash
# job guard ของ backup.yml — TECHNICAL_BUILD_PLAN ส่วน 8 “งาน guard” (P7-01)
#
# ตรวจว่า private.settings ของ kemi-prod ไม่มี allow_test_logins = on (เปิดได้เฉพาะ kemi-dev — 0002_accounts)
# อ่านอย่างเดียวใน transaction READ ONLY · ล้ม = job นี้ล้ม (GitHub ส่งอีเมล) โดยงานสำรองที่เป็น job แยกยังทำต่อ
#
# ตัวแปรที่ต้องมี
#   PGHOST PGUSER PGPASSWORD     Session pooler ของ kemi-prod เท่านั้น (prod_db_allowed ใน ops/backup.sh)
# ไม่บังคับ
#   GUARD_ALLOW_LOCAL=1          ยอมฐานข้อมูลในเครื่อง (ผู้ใช้ postgres) — สำหรับ ops/backup-test เท่านั้น
set -Eeuo pipefail
umask 077

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# prod_db_allowed log die
export BACKUP_LIB_ONLY=1
# shellcheck source=ops/backup.sh
. "$here/backup.sh"
unset BACKUP_LIB_ONLY

STEP=guard
: "${PGHOST:?}" "${PGUSER:?}" "${PGPASSWORD:?}"
prod_db_allowed "$PGHOST" "$PGUSER" "${GUARD_ALLOW_LOCAL:-}" || die 'db_not_allowed: guard ตรวจได้เฉพาะ kemi-prod ผ่าน Session pooler'
export PGPORT=${PGPORT:-5432} PGDATABASE=${PGDATABASE:-postgres} PGCLIENTENCODING=UTF8
export PGAPPNAME=kemi-backup-guard PGCONNECT_TIMEOUT=20

err=$(mktemp)
trap 'rm -f "$err"' EXIT
if ! found=$(psql -X -q -A -t -v ON_ERROR_STOP=1 2>"$err" <<'SQL'
begin read only;
select coalesce(string_agg(s.key || '=' || s.value, ',' order by s.key), '')
  from private.settings s where s.key = 'allow_test_logins' and s.value = 'on';
commit;
SQL
); then
  log "psql: $(head -c 300 "$err")"
  die 'อ่าน private.settings ไม่สำเร็จ'
fi
if [ -n "$found" ]; then
  echo "::error title=guard: prod เปิดล็อกอินทดสอบ::private.settings มี $found — ปิดทันที (allow_test_logins ใช้ได้เฉพาะ kemi-dev)"
  die "allow_test_logins_on: $found"
fi
log 'ผ่าน: private.settings ไม่มี allow_test_logins = on'
