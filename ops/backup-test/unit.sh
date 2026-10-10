#!/usr/bin/env bash
# unit test ของฟังก์ชันล้วนใน ops/backup.sh — รันได้ทั้ง Git Bash และ Linux: bash ops/backup-test/unit.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export BACKUP_LIB_ONLY=1
# shellcheck source=ops/backup.sh
. "$here/../backup.sh"

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

# ตัวกัน: kemi-dev เท่านั้น, ในเครื่องต้องเปิด BACKUP_ALLOW_LOCAL
ok 'pooler ของ kemi-dev ผ่าน' target_allowed postgres.igchlnmxbghsigyziomk aws-0-ap-southeast-1.pooler.supabase.com kemi-dev-files ''
ok 'project อื่นไม่ผ่าน' not target_allowed postgres.abcdefghijklmnopqrst aws-0-ap-southeast-1.pooler.supabase.com kemi-dev-files ''
ok 'bucket kemi-files ไม่ผ่าน' not target_allowed postgres.igchlnmxbghsigyziomk aws-0-ap-southeast-1.pooler.supabase.com kemi-files ''
ok 'ผู้ใช้ postgres เฉย ๆ บน pooler ไม่ผ่าน' not target_allowed postgres aws-0-ap-southeast-1.pooler.supabase.com kemi-dev-files 1
ok 'ในเครื่องไม่เปิดธงไม่ผ่าน' not target_allowed postgres 127.0.0.1 kemi-dev-files ''
ok 'ในเครื่องเปิดธงผ่าน' target_allowed postgres host.docker.internal kemi-dev-files 1
ok 'ชื่อ host คล้าย localhost ไม่ผ่าน' not target_allowed postgres localhost.evil.example kemi-dev-files 1

# key ที่ส่งให้ rclone/aws
ok 'key ปกติ' key_ok files/0b8e2c1a-1f7e-4c4a-9a51-6e0f6b8f0d11.pdf
ok 'key ซ้อนโฟลเดอร์' key_ok files/t11/a1.jpg
ok 'ไม่ใช่ files/' not key_ok staging/x.pdf
ok 'มี ..' not key_ok files/../x
ok 'มี ,' not key_ok 'files/a,b.pdf'
ok 'มีช่องว่าง' not key_ok 'files/a b.pdf'
ok 'ขึ้นบรรทัดใหม่' not key_ok $'files/a\nb.pdf'
ok 'โฟลเดอร์ว่าง' not key_ok files//a.pdf

ok 'ETag MD5' md5_comparable 0123456789abcdef0123456789ABCDEF
ok 'ETag multipart ไม่ใช่ MD5' not md5_comparable 0123456789abcdef0123456789abcdef-2
ok 'ชื่อรอบ' stamp_ok 20261007T193000Z
ok 'ชื่อโฟลเดอร์อื่นไม่แตะ' not stamp_ok manual-copy

# เทียบ manifest กับ Drive: หาย / ขนาดไม่ตรง / Drive ว่าง
tmp=$(mktemp -d)
printf 'final_key,version_id,size_bytes,checksum\nfiles/a.pdf,v1,10,x\nfiles/b.jpg,v2,20,y\nfiles/c.png,v3,30,z\n' >"$tmp/m.csv"
printf 'files/a.pdf\t10\nfiles/b.jpg\t21\nfiles/z.pdf\t5\n' >"$tmp/d.tsv"
ok 'หาย + ขนาดไม่ตรง' test "$(missing_or_mismatch "$tmp/m.csv" "$tmp/d.tsv" | tr '\n' ' ')" = 'files/b.jpg files/c.png '
: >"$tmp/empty.tsv"
ok 'Drive ว่าง = ขาดทุกไฟล์' test "$(missing_or_mismatch "$tmp/m.csv" "$tmp/empty.tsv" | wc -l)" = 3
printf 'files/a.pdf\t10\nfiles/b.jpg\t20\nfiles/c.png\t30\n' >"$tmp/full.tsv"
ok 'ครบ = ไม่มีรายการ' test -z "$(missing_or_mismatch "$tmp/m.csv" "$tmp/full.tsv")"
printf 'final_key,version_id,size_bytes,checksum\n' >"$tmp/m0.csv"
ok 'manifest ว่าง' test -z "$(missing_or_mismatch "$tmp/m0.csv" "$tmp/empty.tsv")"
tail -n +2 "$tmp/m.csv" >"$tmp/new.csv"
ok 'ไฟล์ใหม่ที่มีใน Drive ขนาดตรงถูกข้าม' test "$(not_in_drive "$tmp/new.csv" "$tmp/d.tsv" | cut -d, -f1 | tr '
' ' ')" = 'files/b.jpg files/c.png '
ok 'ไฟล์ใหม่ส่งต่อทั้งแถว' test "$(not_in_drive "$tmp/new.csv" "$tmp/empty.tsv" | sed -n 1p)" = 'files/a.pdf,v1,10,x'
rm -rf "$tmp"

echo "unit: ผ่าน $pass ไม่ผ่าน $fail"
[ "$fail" = 0 ]
