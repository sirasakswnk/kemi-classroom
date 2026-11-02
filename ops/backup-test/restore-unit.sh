#!/usr/bin/env bash
# unit test ของฟังก์ชันล้วนใน ops/restore-test.sh — รันได้ทั้ง Git Bash และ Linux: bash ops/backup-test/restore-unit.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export RESTORE_LIB_ONLY=1
# shellcheck source=ops/restore-test.sh
. "$here/../restore-test.sh"
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
# ฐานข้อมูล: ในเครื่องเท่านั้น
ok 'runner ผ่าน' restore_db_allowed 127.0.0.1 supabase_admin
ok 'container ทดสอบผ่าน' restore_db_allowed host.docker.internal supabase_admin
ok 'pooler ของ prod ไม่ผ่าน' not restore_db_allowed "$POOL" postgres.fcwbomasayvlubijsssh
ok 'pooler + ผู้ใช้ supabase_admin ไม่ผ่าน' not restore_db_allowed "$POOL" supabase_admin
ok 'ในเครื่อง + ผู้ใช้ของ prod ไม่ผ่าน' not restore_db_allowed 127.0.0.1 postgres.fcwbomasayvlubijsssh
ok 'ชื่อ host คล้าย localhost ไม่ผ่าน' not restore_db_allowed localhost.evil.example supabase_admin

# Drive: ชุดต้องตรงเป้าหมาย · โฟลเดอร์ในเครื่องได้เฉพาะ dev ตอนทดสอบ
ok 'gcrypt ของ prod กับเป้าหมาย prod' restore_remote_ok gdrive:kemi-backup-prod prod ''
ok 'gcrypt ของ dev กับเป้าหมาย prod ไม่ผ่าน' not restore_remote_ok gdrive:kemi-backup prod ''
ok 'gcrypt ของ prod กับเป้าหมาย dev ไม่ผ่าน' not restore_remote_ok gdrive:kemi-backup-prod dev ''
ok 'โฟลเดอร์ในเครื่องไม่เปิดธงไม่ผ่าน' not restore_remote_ok gdrive:/drive/x dev ''
ok 'โฟลเดอร์ในเครื่องเปิดธงผ่าน (dev)' restore_remote_ok gdrive:/drive/x dev 1
ok 'โฟลเดอร์ในเครื่องเปิดธงกับ prod ไม่ผ่าน' not restore_remote_ok gdrive:/drive/x prod 1

# key ทดสอบ
ok 'ปลายทางอยู่ใต้ prefix' eq "$(test_key 123 files/a.pdf)" restore-test/123/files/a.pdf
ok 'ลบใต้ prefix ได้' sweep_key_ok restore-test/123/files/a.pdf
ok 'ลบ files/ ไม่ได้' not sweep_key_ok files/a.pdf
ok 'ลบ staging/ ไม่ได้' not sweep_key_ok staging/a.pdf
ok 'prefix คล้ายกันไม่ได้' not sweep_key_ok restore-test-x/a.pdf
ok 'มี .. ไม่ได้' not sweep_key_ok restore-test/../files/a.pdf
ok 'run tag ปกติ' run_tag_ok 18734561234
ok 'run tag มี / ไม่ได้' not run_tag_ok a/b
ok 'run tag ว่างไม่ได้' not run_tag_ok ''

# เพดาน B2
tmp=$(mktemp -d)
for i in 1 2 3 4 5 6; do echo "files/$i.pdf,v$i,40,sum$i"; done >"$tmp/list.csv"
ok 'เลือกไม่เกินจำนวน' eq "$(pick_files "$tmp/list.csv" 2 1000 | wc -l)" 2
ok 'เลือกไม่เกินขนาดรวม' eq "$(pick_files "$tmp/list.csv" 50 100 | wc -l)" 2
ok 'รายการว่างได้ 0' eq "$(pick_files /dev/null 50 100 | wc -l)" 0
printf 'files/big.pdf,v,500,s\nfiles/small.pdf,v,10,s\n' >"$tmp/big.csv"
ok 'ข้ามไฟล์ใหญ่เกินแล้วเลือกไฟล์ถัดไป' eq "$(pick_files "$tmp/big.csv" 50 100 | cut -d, -f1)" files/small.pdf
ok 'ค่าเริ่มต้น sample อยู่ใต้โควตาคำขอ' eq "$((SAMPLE_FILES <= 50))" 1
ok 'เพดาน all ไม่เกิน 500 คำขอ' eq "$((ALL_FILES <= 500))" 1
ok 'เพดาน all ต่ำกว่าพื้นที่ที่กันไว้ 0.5 GB' eq "$((ALL_BYTES < 500000000))" 1
ok 'ในเพดาน' within_budget 500 300000000 "$ALL_FILES" "$ALL_BYTES"
ok 'จำนวนเกิน' not within_budget 501 1 "$ALL_FILES" "$ALL_BYTES"
ok 'ขนาดเกิน' not within_budget 1 300000001 "$ALL_FILES" "$ALL_BYTES"

# ไฟล์ตรง manifest
printf 'hello' >"$tmp/f"
ok 'ขนาด + MD5 ตรง' file_matches_manifest "$tmp/f" 5 5d41402abc4b2a76b9719d911017c592
ok 'MD5 ตัวใหญ่ตรง' file_matches_manifest "$tmp/f" 5 5D41402ABC4B2A76B9719D911017C592
ok 'MD5 ไม่ตรง' not file_matches_manifest "$tmp/f" 5 00000000000000000000000000000000
ok 'ขนาดไม่ตรง' not file_matches_manifest "$tmp/f" 6 5d41402abc4b2a76b9719d911017c592
ok 'checksum แบบอื่นตรวจแค่ขนาด' file_matches_manifest "$tmp/f" 5 abc-2
ok 'ไม่มีไฟล์' not file_matches_manifest "$tmp/none" 5 abc

# ข้อความผิดพลาดต้องไม่มีค่าจากแถว
cat >"$tmp/err" <<'EOF'
pg_restore: error: COPY failed for table "students": ERROR:  invalid input syntax for type uuid: "ชื่อนักเรียนจริง"
CONTEXT:  COPY students, line 1: "ชื่อนักเรียนจริง	อื่น ๆ"
pg_restore: error: could not execute query: ERROR:  value 'ความลับ' is bad
EOF
safe=$(safe_restore_errors "$tmp/err")
ok 'ตัดค่าในเครื่องหมายคำพูด' eq "$(printf '%s' "$safe" | grep -c -E 'ชื่อนักเรียน|ความลับ')" 0
ok 'ไม่เอาบรรทัด CONTEXT' eq "$(printf '%s' "$safe" | grep -c CONTEXT)" 0
ok 'ยังบอกชนิดความผิดพลาด' eq "$(printf '%s' "$safe" | grep -c 'pg_restore: error')" 2
ok 'ไม่มี error = ว่าง' eq "$(safe_restore_errors /dev/null | wc -c)" 0
rm -rf "$tmp"

echo "restore-unit: ผ่าน $pass ล้ม $fail"
[ "$fail" = 0 ]
