#!/usr/bin/env bash
# unit test ของฟังก์ชันล้วนใน ops/restore-record.sh และ prod_db_allowed (ops/backup.sh — ใช้กับ restore-record/guard) — รันได้ทั้ง Git Bash และ Linux: bash ops/backup-test/record-unit.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export RECORD_LIB_ONLY=1
# shellcheck source=ops/restore-record.sh
. "$here/../restore-record.sh"
set +eE

pass=0
fail=0
ok() { # $1 ชื่อ, ที่เหลือคือคำสั่งที่ต้องสำเร็จ
  local name=$1
  shift
  if "$@"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "FAIL: $name"
  fi
}
not() { ! "$@"; }
eq() { [ "$1" = "$2" ]; }

POOL=aws-0-ap-southeast-1.pooler.supabase.com
ok 'pooler ของ prod ผ่าน' prod_db_allowed "$POOL" postgres.fcwbomasayvlubijsssh ''
ok 'pooler ของ dev ไม่ผ่าน' not prod_db_allowed "$POOL" postgres.igchlnmxbghsigyziomk ''
ok 'โปรเจกต์อื่นไม่ผ่าน' not prod_db_allowed "$POOL" postgres.abcdefghijklmnopqrst ''
ok 'host อื่นกับผู้ใช้ prod ไม่ผ่าน' not prod_db_allowed db.fcwbomasayvlubijsssh.supabase.co postgres.fcwbomasayvlubijsssh ''
ok 'ฐานชั่วคราวของ runner ไม่ผ่าน' not prod_db_allowed 127.0.0.1 supabase_admin ''
ok 'ในเครื่องไม่เปิดธงไม่ผ่าน' not prod_db_allowed 127.0.0.1 postgres ''
ok 'ในเครื่องเปิดธงผ่าน' prod_db_allowed host.docker.internal postgres 1
ok 'เปิดธงแต่ host จริงกับผู้ใช้ postgres ไม่ผ่าน' not prod_db_allowed "$POOL" postgres 1

ok 'ผลผ่าน' result_ok true 20261102T055055Z 50 'target=prod files=sample'
ok 'ผลไม่ผ่านก่อนรู้จุดกู้คืน' result_ok false '' 0 'ล้มที่ขั้น guard (exit 1)'
ok 'succeeded อื่นไม่ได้' not result_ok yes 20261102T055055Z 1 ''
ok 'จุดกู้คืนรูปแบบอื่นไม่ได้' not result_ok true "x'); drop table y; --" 1 ''
ok 'จำนวนไม่ใช่ตัวเลขไม่ได้' not result_ok true 20261102T055055Z -1 ''
ok 'detail ยาวเกินไม่ได้' not result_ok true '' 1 "$(printf 'a%.0s' $(seq 1 501))"

tmp=$(mktemp)
printf 'succeeded=true\npoint=20261102T055055Z\nfiles=6\ndetail=a=b c\n' >"$tmp"
ok 'อ่านค่าจากไฟล์ผล' eq "$(result_value "$tmp" detail)" 'a=b c'
ok 'ไม่มีชื่อ = ว่าง' eq "$(result_value "$tmp" none)" ''
rm -f "$tmp"

echo "record-unit: ผ่าน $pass ล้ม $fail"
[ "$fail" = 0 ]
