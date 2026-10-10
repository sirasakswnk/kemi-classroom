#!/usr/bin/env bash
# ทดสอบ ops/backup.sh ครบรอบ — รันใน container postgres:17 ผ่าน ops/backup-test/run.sh
# ฐานข้อมูล: Supabase ในเครื่อง (npm run db:start) ที่ host.docker.internal:54322 — ข้อมูลสมมติเท่านั้น
# B2 = aws ปลอมอ่านจากโฟลเดอร์, Drive = rclone crypt ครอบโฟลเดอร์ในเครื่อง, Healthchecks/Data API = fake-server.py
# ไม่แตะ B2, Drive, Healthchecks หรือ kemi-dev จริง
set -uo pipefail
RCLONE_VERSION=v1.75.1
RCLONE_DEB_SHA256=09c9f7606ed9e31eecc1eec26a89992cf2931a8d2d1a5f0ae2bb1c11630ffb15

echo '== ติดตั้ง jq curl python3 rclone'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq jq curl python3 ca-certificates >/dev/null || exit 1
curl -fsSLo /tmp/rclone.deb "https://downloads.rclone.org/$RCLONE_VERSION/rclone-$RCLONE_VERSION-linux-amd64.deb" || exit 1
echo "$RCLONE_DEB_SHA256  /tmp/rclone.deb" | sha256sum -c - >/dev/null || exit 1
dpkg -i /tmp/rclone.deb >/dev/null || exit 1
install -m 755 /repo/ops/backup-test/fake-aws /usr/local/bin/aws

export PGHOST=host.docker.internal PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
export BACKUP_ALLOW_LOCAL=1 B2_BUCKET=kemi-dev-files B2_S3_ENDPOINT=https://s3.fake.example B2_REGION=eu-central-003
export HC_PING_URL=http://127.0.0.1:8787/hc HC_STATE_FILE=/tmp/hc-state
export SUPABASE_URL=http://127.0.0.1:8787 SUPABASE_PING_KEY=test-ping-key
export FAKE_B2_DIR=/fakeb2 FAKE_B2_LOG=/tmp/b2.log
HC_LOG=/tmp/hc.log
DRIVE=/drive/kemi-backup
mkdir -p "$DRIVE" "$FAKE_B2_DIR/kemi-dev-files/files/e2e"
: >"$FAKE_B2_LOG"
: >"$HC_LOG"
python3 /repo/ops/backup-test/fake-server.py 8787 "$HC_LOG" &

RCLONE_CONFIG_CONTENT="[gdrive]
type = local

[gcrypt]
type = crypt
remote = gdrive:$DRIVE
password = $(rclone obscure 'e2e-crypt-password')
password2 = $(rclone obscure 'e2e-crypt-salt')

[b2ro]
type = b2
account = fake-key-id
key = fake-application-key"
export RCLONE_CONFIG_CONTENT
printf '%s\n' "$RCLONE_CONFIG_CONTENT" >/tmp/rclone.conf
rc() { rclone --config /tmp/rclone.conf "$@"; }

q() { psql -X -A -t -q -v ON_ERROR_STOP=1 -c "$1"; }

pass=0
fail=0
ok() {
  local name=$1
  shift
  if "$@"; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    echo "  FAIL: $name"
  fi
}
eq() { [ "$1" = "$2" ] || {
  echo "    ได้ '$1' ต้องการ '$2'"
  return 1
}; }

run_backup() { # $1 ชื่อรอบ → ตั้ง RC
  echo "== $1"
  rm -f "$HC_STATE_FILE"
  bash /repo/ops/backup.sh >"/tmp/run-$1.log" 2>&1
  RC=$?
  sed 's/^/    /' "/tmp/run-$1.log" | tail -n 4
}
last_run() { q "select status || '|' || coalesce(new_file_count::text, '-') || '|' || coalesce(file_count::text, '-') || '|' || coalesce(detail, '') from public.backup_runs where kind = 'backup' order by started_at desc limit 1"; }
lock_count() { q "select count(*) from private.maintenance_locks where name = 'backup'"; }
b2_reads() { wc -l <"$FAKE_B2_LOG"; }
hc_last() { grep '/hc' "$HC_LOG" | tail -n 1 | cut -d' ' -f2; }

# ไฟล์สมมติ: เนื้อสุ่ม, checksum = MD5 แบบ ETag ของ B2, เวอร์ชันสมมติ
make_asset() { # $1 ชื่อ $2 ขนาด [$3 เนื้อในฐานข้อมูลไม่ตรง]
  local f="$FAKE_B2_DIR/kemi-dev-files/files/e2e/$1@v-$1" md5
  head -c "$2" /dev/urandom >"$f"
  md5=$(md5sum "$f" | cut -d' ' -f1)
  [ -n "${3:-}" ] && head -c "$2" /dev/urandom >"$f" # B2 มีเนื้อคนละชุดกับที่บันทึก
  # เดินสถานะ copying → ready แบบเดียวกับ complete (trigger กันการใส่ ready ตรง ๆ)
  q "insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
     values ('e2e00000-0000-4000-8000-000000000001', 'post', 'staging/e2e/$1', 'sv', 'files/e2e/$1', 'application/pdf', $2, 'สมมติ.pdf');
     update public.assets set status = 'ready', version_id = 'v-$1', checksum = '$md5', ready_at = clock_timestamp()
      where final_key = 'files/e2e/$1'"
}

echo '== เตรียมข้อมูลสมมติ'
q "delete from private.backup_run_files; delete from private.backup_manifests; delete from public.backup_runs;
   delete from private.maintenance_locks where name = 'backup'; delete from public.b2_daily_usage where source = 'backup';
   delete from public.assets where final_key like 'files/e2e/%';
   delete from public.accounts where id = 'e2e00000-0000-4000-8000-000000000001';
   insert into public.accounts (id, provider, provider_subject, email, role)
   values ('e2e00000-0000-4000-8000-000000000001', 'google', 'e2e-backup', 'e2e-backup@example.com', 'admin')"
make_asset a1.pdf 2048
make_asset a2.pdf 70000
make_asset a3.pdf 1

run_backup 'รอบแรก: ไฟล์ใหม่ 3'
ok 'สำเร็จ' eq "$RC" 0
ok 'backup_runs succeeded ใหม่ 3 ทั้งหมด 3' eq "$(last_run | cut -d'|' -f1-3)" 'succeeded|3|3'
ok 'อ่าน B2 3 คำขอ (ไฟล์ละครั้ง)' eq "$(b2_reads)" 3
ok 'manifest ในฐานข้อมูล 3 แถว' eq "$(q 'select count(*) from private.backup_manifests')" 3
ok 'รายการชั่วคราวถูกล้าง' eq "$(q 'select count(*) from private.backup_run_files')" 0
ok 'ปลดธงแล้ว' eq "$(lock_count)" 0
ok 'งบ B2 แหล่ง backup = 3 คำขอ 72049 ไบต์' eq "$(q "select class_b_requests || '/' || download_bytes from public.b2_daily_usage where source = 'backup'")" '3/72049'
ok 'ping start ไม่ได้ส่งจากสคริปต์ (workflow ส่ง) + success 1 ครั้ง' eq "$(grep -c '^POST /hc ' "$HC_LOG")" 1
ok 'ping() ผ่าน Data API ด้วย key' grep -q '^POST /rest/v1/rpc/ping' "$HC_LOG"
ok 'HC_STATE_FILE = success' eq "$(cat "$HC_STATE_FILE")" success
ok 'ชื่อไฟล์ใน Drive ถูกเข้ารหัส' eq "$(find "$DRIVE" | grep -c -E 'a1|e2e|files|runs|manifest|dump')" 0
ok 'ถอดรหัสแล้วเนื้อตรงต้นฉบับ' eq "$(rc cat gcrypt:files/e2e/a2.pdf | md5sum | cut -d' ' -f1)" "$(md5sum "$FAKE_B2_DIR/kemi-dev-files/files/e2e/a2.pdf@v-a2.pdf" | cut -d' ' -f1)"
stamp1=$(rc lsf --dirs-only gcrypt:runs | tr -d '/')
ok 'จุดกู้คืน 1 จุด' eq "$(printf '%s\n' "$stamp1" | wc -l)" 1
ok 'ชื่อจุดกู้คืน = dump_name' eq "$(q "select dump_name from public.backup_runs where status = 'succeeded'")" "$stamp1"
mkdir -p /tmp/restore && rc copy "gcrypt:runs/$stamp1" /tmp/restore
ok 'มี schema/data dump + manifest + meta' eq "$(find /tmp/restore -type f -printf '%f\n' | sort | tr '\n' ' ')" 'data.dump manifest.csv meta.json schema.dump '
ok 'manifest.csv 3 ไฟล์ + หัว' eq "$(wc -l </tmp/restore/manifest.csv)" 4
ok 'data dump มีข้อมูล assets' bash -c "pg_restore -l /tmp/restore/data.dump | grep -q 'TABLE DATA public assets'"
ok 'data dump ไม่มีข้อมูลตาราง manifest 2 ตาราง' bash -c "! pg_restore -l /tmp/restore/data.dump | grep -E 'TABLE DATA private (backup_manifests|backup_run_files)'"
ok 'schema dump มีตาราง private.backup_manifests' bash -c "pg_restore -l /tmp/restore/schema.dump | grep -q 'TABLE private backup_manifests'"
ok 'schema dump ไม่มีข้อมูล' bash -c "! pg_restore -l /tmp/restore/schema.dump | grep -q 'TABLE DATA'"

run_backup 'รอบสอง: ไม่มีไฟล์ใหม่'
ok 'สำเร็จ' eq "$RC" 0
ok 'ใหม่ 0 ทั้งหมด 3' eq "$(last_run | cut -d'|' -f1-3)" 'succeeded|0|3'
ok 'ไม่อ่าน B2 ซ้ำ (ยัง 3)' eq "$(b2_reads)" 3
ok 'จุดกู้คืน 2 จุด' eq "$(rc lsf --dirs-only gcrypt:runs | wc -l)" 2

rc deletefile gcrypt:files/e2e/a2.pdf
run_backup 'รอบสาม: ไฟล์เดิมหายจาก Drive → ดึงตาม version_id'
ok 'สำเร็จ' eq "$RC" 0
ok 'detail บอกดึงซ่อม 1' bash -c "[[ '$(last_run)' == *'ดึงซ่อม 1'* ]]"
ok 'อ่าน B2 เพิ่ม 1 (a2 ระบุ versionId)' eq "$(tail -n 1 "$FAKE_B2_LOG")" 'GET kemi-dev-files/files/e2e/a2.pdf?versionId=v-a2.pdf'
ok 'a2 กลับมาใน Drive' eq "$(rc cat gcrypt:files/e2e/a2.pdf | wc -c)" 70000

make_asset a4.pdf 5000 corrupt
run_backup 'รอบสี่: เนื้อใน B2 ไม่ตรง manifest → ล้มเหลว'
ok 'ล้มเหลว' eq "$([ "$RC" != 0 ] && echo y)" y
ok 'backup_runs failed ที่ขั้น copy_new' eq "$(last_run | cut -d'|' -f1,4)" 'failed|ล้มที่ขั้น copy_new'
ok 'ปลดธงแม้ล้ม' eq "$(lock_count)" 0
ok 'ping fail พร้อมขั้น' bash -c "grep '^POST /hc/fail ' '$HC_LOG' | tail -n 1 | grep -q 'copy_new'"
ok 'HC_STATE_FILE = fail' eq "$(cat "$HC_STATE_FILE")" fail
ok 'งบ B2 บันทึกแม้ล้ม (รวม 5 คำขอ)' eq "$(q "select class_b_requests from public.b2_daily_usage where source = 'backup'")" 5
ok 'ไม่มีจุดกู้คืนของรอบที่ล้ม (ยัง 3)' eq "$(rc lsf --dirs-only gcrypt:runs | wc -l)" 3
ok 'manifest ไม่รวม a4' eq "$(q "select count(*) from private.backup_manifests where final_key = 'files/e2e/a4.pdf'")" 0
q "update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where final_key = 'files/e2e/a4.pdf'"

SIMULATE_FAILURE=true run_backup 'รอบห้า: ล้มโดยตั้งใจ'
ok 'ล้มเหลว' eq "$([ "$RC" != 0 ] && echo y)" y
ok 'detail = simulate' eq "$(last_run | cut -d'|' -f1,4)" 'failed|ล้มที่ขั้น simulate'
ok 'ปลดธง' eq "$(lock_count)" 0
ok 'ping fail' eq "$(hc_last)" /hc/fail

q 'select private.backup_start()' >/dev/null
run_backup 'รอบหก: มีรอบอื่นถือธงอยู่ → backup_in_progress'
ok 'ล้มเหลว' eq "$([ "$RC" != 0 ] && echo y)" y
ok 'ไม่ปลดธงของรอบอื่น' eq "$(lock_count)" 1
ok 'log บอก backup_in_progress' grep -q backup_in_progress /tmp/run-รอบหก*.log
q "select private.backup_finish((select id from public.backup_runs where status = 'running'), false, null, null, null, null, 'e2e'); select private.backup_release_lock()" >/dev/null

PGHOST=aws-0-ap-southeast-1.pooler.supabase.com PGUSER=postgres.abcdefghijklmnopqrst run_backup 'รอบเจ็ด: project อื่น → ตัวกัน'
ok 'ล้มเหลวก่อนต่อฐานข้อมูล' bash -c "grep -q target_not_allowed /tmp/run-รอบเจ็ด*.log"
ok 'ไม่สร้างรอบใหม่' eq "$(q "select count(*) from public.backup_runs where status = 'running'")" 0

# ล้าง: a1 ออกจากระบบหลักแล้วมีรอบสำเร็จใหม่ → ย้อนเวลารอบเก่า 10 วัน → รอบถัดไปลบ a1 + จุดกู้คืนเก่าจาก Drive
q "update public.assets set status = 'deleting', delete_requested_at = clock_timestamp() where final_key = 'files/e2e/a1.pdf'"
run_backup 'รอบแปด: a1 ไม่อยู่ในรอบนี้'
ok 'สำเร็จ ทั้งหมด 2' eq "$(last_run | cut -d'|' -f1,3)" 'succeeded|2'
q "update public.backup_runs set started_at = started_at - interval '10 days'
    where id <> (select id from public.backup_runs where status = 'succeeded' order by started_at desc limit 1)"
run_backup 'รอบเก้า: ล้างของพ้นอายุ'
ok 'สำเร็จ' eq "$RC" 0
ok 'a1 ถูกลบจาก Drive' bash -c "! rclone --config /tmp/rclone.conf lsf gcrypt:files/e2e | grep -qx a1.pdf"
ok 'แถว manifest ของ a1 ถูกลบ (ยืนยันหลังลบจาก Drive)' eq "$(q "select count(*) from private.backup_manifests where final_key = 'files/e2e/a1.pdf'")" 0
ok 'a2/a3 ยังอยู่' eq "$(rc lsf gcrypt:files/e2e | tr '\n' ' ')" 'a2.pdf a3.pdf '
ok 'จุดกู้คืนเหลือ 2 (รอบแปด + รอบเก้า)' eq "$(rc lsf --dirs-only gcrypt:runs | wc -l)" 2
ok 'log บอกยืนยันล้าง 1' grep -q 'ขอ 1 ยืนยัน 1' /tmp/run-รอบเก้า*.log

# รอบล้มหลังคัดลอก: a5 ขึ้น Drive แล้ว แต่ a3 หายทั้งใน Drive และ B2 → ล้มที่ขั้น repair
make_asset a5.pdf 3000
mv "$FAKE_B2_DIR/kemi-dev-files/files/e2e/a3.pdf@v-a3.pdf" /tmp/a3.hold
rc deletefile gcrypt:files/e2e/a3.pdf
run_backup 'รอบสิบ: ล้มหลังคัดลอกไฟล์ใหม่'
ok 'ล้มที่ขั้น repair' eq "$(last_run | cut -d'|' -f1,4)" 'failed|ล้มที่ขั้น repair'
ok 'a5 อยู่ใน Drive แล้ว' eq "$(rc cat gcrypt:files/e2e/a5.pdf | wc -c)" 3000
mv /tmp/a3.hold "$FAKE_B2_DIR/kemi-dev-files/files/e2e/a3.pdf@v-a3.pdf"
reads_before=$(b2_reads)
run_backup 'รอบสิบเอ็ด: ไฟล์ใหม่ที่มีใน Drive แล้ว → ไม่อ่าน B2'
ok 'สำเร็จ ใหม่ 1' eq "$(last_run | cut -d'|' -f1,2)" 'succeeded|1'
ok 'ไม่มี GET ของ a5' bash -c "! tail -n +$((reads_before + 1)) '$FAKE_B2_LOG' | grep -q a5.pdf"
ok 'GET เฉพาะ a3 ที่ดึงซ่อม' eq "$(tail -n +$((reads_before + 1)) "$FAKE_B2_LOG" | tr '
' ' ')" 'GET kemi-dev-files/files/e2e/a3.pdf?versionId=v-a3.pdf '
ok 'detail บอกมีใน Drive แล้ว 1' bash -c "[[ '$(last_run)' == *'มีใน Drive แล้ว 1'* ]]"

echo "e2e: ผ่าน $pass ไม่ผ่าน $fail"
[ "$fail" = 0 ]
