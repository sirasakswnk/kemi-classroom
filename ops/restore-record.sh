#!/usr/bin/env bash
# บันทึกผลทดสอบกู้คืนหนึ่งแถวลง backup_runs ของ kemi-prod — TECHNICAL_BUILD_PLAN ส่วน 8 ข้อ 6 (ทาง A ตัดสิน 2 พ.ย. 2026)
#
# ขั้นเดียวใน restore-test.yml ที่ได้รหัสผ่านฐานข้อมูล prod: เรียก private.backup_record_restore_test อย่างเดียว
# ไม่กู้ข้อมูลใดเข้า prod · รันเฉพาะรอบเป้าหมาย prod หลัง ops/restore-test.sh จบ (ผ่านหรือไม่ผ่าน)
#
# ตัวแปรที่ต้องมี
#   PGHOST PGUSER PGPASSWORD     Session pooler ของ kemi-prod เท่านั้น (ดู record_db_allowed)
#   RESTORE_RESULT_FILE          ไฟล์ผลที่ ops/restore-test.sh เขียน (succeeded/point/files/detail — จำนวนเท่านั้น)
# ไม่บังคับ
#   RESTORE_RECORD_ALLOW_LOCAL=1 ยอมฐานข้อมูลในเครื่อง (ผู้ใช้ postgres) — สำหรับ ops/backup-test เท่านั้น
set -Eeuo pipefail
umask 077

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# target_value stamp_ok log die
export BACKUP_LIB_ONLY=1
# shellcheck source=ops/backup.sh
. "$here/backup.sh"
unset BACKUP_LIB_ONLY

readonly RECORD_HOST=aws-0-ap-southeast-1.pooler.supabase.com

# pooler + ผู้ใช้ postgres.<ref ของ prod> เท่านั้น — dev หรือโปรเจกต์อื่นไม่ผ่าน
record_db_allowed() { # $1 PGHOST $2 PGUSER $3 allow_local
  [ "$1" = "$RECORD_HOST" ] && [ "$2" = "postgres.$(target_value prod ref)" ] && return 0
  [ "${3:-}" = 1 ] && [[ "$1" =~ ^(localhost|127\.0\.0\.1|host\.docker\.internal)$ ]] && [ "$2" = postgres ]
}

result_value() { sed -n "s/^$2=//p" "$1" | head -n 1; } # $1 ไฟล์ผล $2 ชื่อ

# ค่าที่จะบันทึกต้องเป็นรูปแบบที่ restore-test.sh เขียนเท่านั้น
result_ok() { # $1 succeeded $2 point $3 files $4 detail
  [[ "$1" =~ ^(true|false)$ ]] || return 1
  [ -z "$2" ] || stamp_ok "$2" || return 1
  [[ "$3" =~ ^[0-9]{1,9}$ ]] || return 1
  [ "${#4}" -le 500 ]
}

if [ "${RECORD_LIB_ONLY:-}" = 1 ]; then
  # shellcheck disable=SC2317 # ใช้เมื่อ source เป็นไลบรารี (unit test)
  return 0 2>/dev/null || exit 0
fi

STEP=guard
: "${PGHOST:?}" "${PGUSER:?}" "${PGPASSWORD:?}" "${RESTORE_RESULT_FILE:?}"
record_db_allowed "$PGHOST" "$PGUSER" "${RESTORE_RECORD_ALLOW_LOCAL:-}" ||
  die 'db_not_allowed: บันทึกผลได้เฉพาะ kemi-prod ผ่าน Session pooler'
[ -s "$RESTORE_RESULT_FILE" ] || die 'ไม่มีไฟล์ผลของ ops/restore-test.sh'
succeeded=$(result_value "$RESTORE_RESULT_FILE" succeeded)
point=$(result_value "$RESTORE_RESULT_FILE" point)
files=$(result_value "$RESTORE_RESULT_FILE" files)
detail=$(result_value "$RESTORE_RESULT_FILE" detail)
result_ok "$succeeded" "$point" "$files" "$detail" || die 'invalid_result: ไฟล์ผลรูปแบบไม่ถูกต้อง'
export PGPORT=${PGPORT:-5432} PGDATABASE=${PGDATABASE:-postgres} PGCLIENTENCODING=UTF8
export PGAPPNAME=kemi-restore-record PGCONNECT_TIMEOUT=20

STEP=record
err=$(mktemp)
trap 'rm -f "$err"' EXIT
if ! id=$(psql -X -q -A -t -v ON_ERROR_STOP=1 -v ok="$succeeded" -v point="$point" -v files="$files" \
  -v detail="$detail" 2>"$err" <<'SQL'
select private.backup_record_restore_test(:'ok'::boolean, nullif(:'point', ''), :'files'::integer, nullif(:'detail', ''))
SQL
); then
  log "psql: $(head -c 300 "$err")"
  die 'บันทึกผลลง backup_runs ไม่สำเร็จ'
fi
[[ "$id" =~ ^[0-9a-f-]{36}$ ]] || die 'backup_record_restore_test คืนค่าไม่ถูกต้อง'
log "บันทึกผลทดสอบกู้คืน ($([ "$succeeded" = true ] && echo ผ่าน || echo ไม่ผ่าน)) ลง backup_runs แล้ว: $id"
