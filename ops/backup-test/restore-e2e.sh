#!/usr/bin/env bash
# ทดสอบ ops/restore-test.sh ครบรอบ — รันใน container postgres:17 ผ่าน ops/backup-test/run.sh
# สร้างจุดกู้คืนจริงด้วย ops/backup.sh แล้วกู้กลับลง Supabase ในเครื่อง ซึ่ง**ล้าง public/private ทิ้ง** → จบแล้วต้อง npm run db:reset
# B2 = aws ปลอม (จำลองกุญแจจำกัด prefix), Drive = rclone crypt ครอบโฟลเดอร์ในเครื่อง — ไม่แตะบริการจริง
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

export PGHOST=host.docker.internal PGPORT=54322 PGDATABASE=postgres PGPASSWORD=postgres
export B2_S3_ENDPOINT=https://s3.fake.example B2_REGION=eu-central-003
export FAKE_B2_DIR=/fakeb2 FAKE_B2_LOG=/tmp/b2.log
HC_LOG=/tmp/hc.log
DRIVE=/drive/kemi-backup
mkdir -p "$DRIVE" "$FAKE_B2_DIR/kemi-dev-files/files/e2e" "$FAKE_B2_DIR/kemi-files"
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

q() { PGUSER=postgres psql -X -A -t -q -v ON_ERROR_STOP=1 -c "$1"; }

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
not() { ! "$@"; }
not_in_log() { # $1 ข้อความ $2 ไฟล์ log
  ! grep -qF -- "$1" "$2"
}
test_files() { find "$FAKE_B2_DIR/kemi-dev-files/restore-test" -type f 2>/dev/null | wc -l; }

# ข้อมูลสมมติที่ log ต้องไม่มี (ชื่อไฟล์ final_key อีเมล ความลับ)
SECRET_NAME='ชื่อไฟล์ลับสมมติ.pdf'
make_asset() { # $1 ชื่อ $2 ขนาด
  local f="$FAKE_B2_DIR/kemi-dev-files/files/e2e/$1@v-$1" md5
  head -c "$2" /dev/urandom >"$f"
  md5=$(md5sum "$f" | cut -d' ' -f1)
  q "insert into public.assets (owner_account_id, purpose, staging_key, staging_version_id, final_key, content_type, size_bytes, file_name)
     values ('e2e00000-0000-4000-8000-000000000001', 'post', 'staging/e2e/$1', 'sv', 'files/e2e/$1', 'application/pdf', $2, '$SECRET_NAME');
     update public.assets set status = 'ready', version_id = 'v-$1', checksum = '$md5', ready_at = clock_timestamp()
      where final_key = 'files/e2e/$1'"
}

echo '== เตรียมข้อมูลสมมติ'
# ล้าง assets ทั้งตารางของฐานข้อมูลในเครื่อง: ของค้างจาก e2e.sh ไม่มีเนื้อไฟล์ใน B2 ปลอมของ container นี้ (ปิด trigger เฉพาะ transaction นี้)
q "set local session_replication_role = replica;
   delete from public.attachments; delete from public.assets;
   delete from private.backup_run_files; delete from private.backup_manifests; delete from public.backup_runs;
   delete from private.maintenance_locks where name = 'backup';
   delete from public.accounts where id = 'e2e00000-0000-4000-8000-000000000001';
   delete from auth.users where id = 'e2e00000-0000-4000-8000-0000000000aa';
   insert into auth.users (id, email) values ('e2e00000-0000-4000-8000-0000000000aa', 'e2e-restore@example.com');
   insert into public.accounts (id, provider, provider_subject, email, role, auth_user_id)
   values ('e2e00000-0000-4000-8000-000000000001', 'google', 'e2e-restore', 'e2e-restore@example.com', 'admin', 'e2e00000-0000-4000-8000-0000000000aa')"
for i in 1 2 3 4 5 6; do make_asset "a$i.pdf" $((i * 1000)); done

echo '== สร้างจุดกู้คืนด้วย ops/backup.sh'
PGUSER=postgres BACKUP_ALLOW_LOCAL=1 B2_BUCKET=kemi-dev-files bash /repo/ops/backup.sh >/tmp/backup.log 2>&1 || {
  tail -n 5 /tmp/backup.log
  exit 1
}
STAMP=$(rc lsf --dirs-only gcrypt:runs | tr -d '/' | sort | tail -n 1)
ok 'มีจุดกู้คืน' eq "$(rc lsf --dirs-only gcrypt:runs | wc -l)" 1

export PGUSER=supabase_admin RESTORE_ALLOW_LOCAL_REMOTE=1 RESTORE_TARGET=dev
export RESTORE_B2_KEY_ID=FAKE_RESTORE_KEY RESTORE_B2_APP_KEY=FAKE-RESTORE-APP-KEY-SECRET
export RESTORE_RUN_TAG=e2e HC_PING_URL=http://127.0.0.1:8787/hc HC_STATE_FILE=/tmp/hc-state GITHUB_STEP_SUMMARY=/tmp/summary.md

run_restore() { # $1 ชื่อรอบ → ตั้ง RC และ LOG (ตัวแปรอื่นส่งผ่าน env ของผู้เรียก)
  echo "== $1"
  LOG="/tmp/restore-$1.log"
  rm -f "$HC_STATE_FILE"
  bash /repo/ops/restore-test.sh >"$LOG" 2>&1
  RC=$?
  sed 's/^/    /' "$LOG" | tail -n 3
}
assert_private_log() { # $1 ไฟล์ log — ข้อมูลที่ต้องไม่อยู่ใน log
  ok 'log ไม่มี final_key' not_in_log 'files/e2e' "$1"
  ok 'log ไม่มีชื่อไฟล์ในข้อมูล' not_in_log "$SECRET_NAME" "$1"
  ok 'log ไม่มีชื่อไฟล์ a1' not_in_log 'a1.pdf' "$1"
  ok 'log ไม่มีอีเมล' not_in_log 'e2e-restore@example.com' "$1"
  ok 'log ไม่มีกุญแจ B2' not_in_log 'FAKE-RESTORE-APP-KEY-SECRET' "$1"
  ok 'log ไม่มี rclone config' not_in_log 'password2' "$1"
  ok 'log ไม่มี URL ping' not_in_log '8787' "$1"
}
assert_clean() { # หลังจบทุกรอบ ไม่ว่าผ่านหรือล้ม
  ok 'ไม่เหลือไฟล์ใต้ prefix ทดสอบ' eq "$(test_files)" 0
  ok 'ไม่แตะ kemi-files' eq "$(find "$FAKE_B2_DIR/kemi-files" -type f | wc -l)" 0
  ok 'ไม่มีคำขอไป kemi-files' eq "$(grep -c 'kemi-files' "$FAKE_B2_LOG")" 0
  ok 'กุญแจไม่เคยถูกปฏิเสธ' eq "$(grep -c '^DENY' "$FAKE_B2_LOG")" 0
  ok 'ไฟล์ files/ เดิมใน bucket ทดสอบยังอยู่' eq "$(find "$FAKE_B2_DIR/kemi-dev-files/files" -type f | wc -l)" 6
}

: >"$FAKE_B2_LOG"
RESTORE_FILES=sample run_restore pass-sample
ok 'สำเร็จ' eq "$RC" 0
ok 'มีผลในสรุป' grep -q 'ผ่าน' "$GITHUB_STEP_SUMMARY"
ok 'ping สำเร็จ' eq "$(cat "$HC_STATE_FILE")" success
ok 'ping ไม่มีชื่อไฟล์' not_in_log 'a1.pdf' "$HC_LOG"
ok 'ตัดการเชื่อม auth_user_id' eq "$(q 'select count(*) from public.accounts where auth_user_id is not null')" 0
ok 'version_id ในฐานข้อมูลเป็นค่าใหม่ทุกไฟล์' eq "$(q "select count(*) from public.assets where status = 'ready' and version_id like 'v-a%'")" 0
ok 'อัปโหลดอยู่ใต้ prefix ทดสอบ' eq "$(grep '^PUT' "$FAKE_B2_LOG" | grep -vc '^PUT kemi-dev-files/restore-test/e2e/files/e2e/')" 0
ok 'อัปโหลด 6 ไฟล์' eq "$(grep -c '^PUT' "$FAKE_B2_LOG")" 6
ok 'อ่านกลับ 6 ไฟล์ ไฟล์ละครั้ง' eq "$(grep -c '^GET' "$FAKE_B2_LOG")" 6
ok 'ลบ 6 เวอร์ชัน ระบุ version_id' eq "$(grep -c '^DELETE .*versionId=v-' "$FAKE_B2_LOG")" 6
ok 'ตาราง manifest ไม่มีข้อมูล (ไม่ได้สำรอง)' eq "$(q 'select count(*) from private.backup_run_files')" 0
assert_private_log "$LOG"
assert_clean

: >"$FAKE_B2_LOG"
RESTORE_FILES=all RESTORE_POINT="$STAMP" run_restore pass-all-stamp
ok 'all + ระบุจุดกู้คืน สำเร็จ' eq "$RC" 0
ok 'all อัปโหลดครบ' eq "$(grep -c '^PUT' "$FAKE_B2_LOG")" 6
assert_private_log "$LOG"
assert_clean

# ตัวควบคุม: ถ้าตรวจไม่จับ รอบเหล่านี้จะผ่านทั้งที่ข้อมูลผิด
tamper_meta() { # $1 jq filter → แก้ meta.json ใน Drive
  rc copyto "gcrypt:runs/$STAMP/meta.json" /tmp/meta.json
  cp /tmp/meta.json /tmp/meta.orig.json
  jq -c "$1" /tmp/meta.orig.json >/tmp/meta.json
  rc copyto /tmp/meta.json "gcrypt:runs/$STAMP/meta.json"
}
restore_meta() { rc copyto /tmp/meta.orig.json "gcrypt:runs/$STAMP/meta.json"; }
failed_with() { # $1 รหัสที่ต้องพบใน log
  grep -q -- "$1" "$LOG" || {
    echo "    ไม่พบ '$1'"
    return 1
  }
}

tamper_meta '.table_rows["public.assets"] += 1'
run_restore tampered-rows
ok 'จำนวนแถวไม่ตรง = ล้ม' not eq "$RC" 0
ok 'บอก table_rows_mismatch' failed_with table_rows_mismatch
ok 'บอกชื่อตารางที่ไม่ตรง' failed_with 'public.assets meta='
ok 'ping fail' eq "$(cat "$HC_STATE_FILE")" fail
assert_private_log "$LOG"
assert_clean
restore_meta

tamper_meta 'del(.table_rows)'
run_restore no-table-rows
ok 'ไม่มี table_rows = ล้ม' not eq "$RC" 0
ok 'บอก meta_no_table_rows' failed_with meta_no_table_rows
restore_meta

tamper_meta '.target = "prod"'
run_restore wrong-target
ok 'จุดกู้คืนคนละเป้าหมาย = ล้ม' not eq "$RC" 0
ok 'บอก meta_target_mismatch' failed_with meta_target_mismatch
restore_meta

# ไฟล์ใน Drive ถูกแทน: ต้องจับได้ก่อนอัปโหลด
rc copyto gcrypt:files/e2e/a2.pdf /tmp/a2.orig
head -c 2000 /dev/urandom >/tmp/a2.bad
rc copyto /tmp/a2.bad gcrypt:files/e2e/a2.pdf
RESTORE_FILES=all run_restore bad-drive-file
ok 'เนื้อไฟล์ไม่ตรง = ล้ม' not eq "$RC" 0
ok 'บอก drive_mismatch' failed_with drive_mismatch
assert_private_log "$LOG"
assert_clean
rc copyto /tmp/a2.orig gcrypt:files/e2e/a2.pdf

# manifest ไม่ตรงฐานข้อมูลที่กู้ (จำนวนและขนาดรวมยังเท่าเดิม จึงผ่านด่าน meta ได้)
rc copyto "gcrypt:runs/$STAMP/manifest.csv" /tmp/manifest.orig
sed '2s/v-a[0-9]*\.pdf/v-tampered/' /tmp/manifest.orig >/tmp/manifest.bad
rc copyto /tmp/manifest.bad "gcrypt:runs/$STAMP/manifest.csv"
run_restore bad-manifest
ok 'manifest ไม่ตรงฐานข้อมูล = ล้ม' not eq "$RC" 0
ok 'บอก manifest_mismatch' failed_with manifest_mismatch
assert_private_log "$LOG"
assert_clean
rc copyto /tmp/manifest.orig "gcrypt:runs/$STAMP/manifest.csv"

# อ่านกลับจาก bucket ทดสอบแล้วเนื้อไม่ตรง: ต้องล้มและยังลบไฟล์ครบ
FAKE_B2_CORRUPT_GET=1 run_restore bad-read-back
ok 'อ่านกลับไม่ตรง = ล้ม' not eq "$RC" 0
ok 'บอก read_back_mismatch' failed_with read_back_mismatch
ok 'ping fail เมื่ออ่านกลับไม่ตรง' eq "$(cat "$HC_STATE_FILE")" fail
assert_private_log "$LOG"
assert_clean

# ลบไฟล์ทดสอบไม่สำเร็จ: ตรวจผ่านหมดก็ต้องไม่รายงานว่าผ่าน
FAKE_B2_FAIL_DELETE=1 run_restore delete-fails
ok 'ลบไม่สำเร็จ = ล้ม' not eq "$RC" 0
ok 'ไม่ส่ง ping สำเร็จ' eq "$(cat "$HC_STATE_FILE")" fail
ok 'ไฟล์ยังเหลือจริง (ตัวควบคุม)' not eq "$(test_files)" 0
ok 'log บอกว่าเหลือไฟล์' failed_with 'ลบไฟล์ทดสอบไม่ครบ'
assert_private_log "$LOG"
RESTORE_SWEEP_ONLY=1 run_restore delete-fails-sweep
ok 'ขั้นสำรองลบของที่เหลือได้' eq "$RC" 0
assert_clean

# ของค้างจากรอบที่ถูกยกเลิก: ถูกลบก่อนเริ่ม และโหมดลบอย่างเดียวลบได้
mkdir -p "$FAKE_B2_DIR/kemi-dev-files/restore-test/old/files"
head -c 10 /dev/urandom >"$FAKE_B2_DIR/kemi-dev-files/restore-test/old/files/x.pdf@v-old"
RESTORE_SWEEP_ONLY=1 run_restore sweep-only
ok 'โหมดลบอย่างเดียวสำเร็จ' eq "$RC" 0
ok 'ของค้างถูกลบ' eq "$(test_files)" 0
ok 'โหมดลบอย่างเดียวไม่ ping' not test -s "$HC_STATE_FILE"
head -c 10 /dev/urandom >"$FAKE_B2_DIR/kemi-dev-files/restore-test/old/files/x.pdf@v-old"
run_restore preflight-sweep
ok 'รอบปกติลบของค้างแล้วผ่าน' eq "$RC" 0
assert_clean

# ตัวกัน: ต้องหยุดก่อนแตะข้อมูล
: >"$FAKE_B2_LOG"
PGHOST=aws-0-ap-southeast-1.pooler.supabase.com PGUSER=postgres.fcwbomasayvlubijsssh run_restore guard-real-db
ok 'ฐานข้อมูลจริง = ล้ม' not eq "$RC" 0
ok 'บอก db_not_allowed' failed_with db_not_allowed
RESTORE_TARGET=prod run_restore guard-config-mismatch
ok 'เป้าหมาย prod + config ของ dev = ล้ม' not eq "$RC" 0
ok 'บอก target_not_allowed' failed_with target_not_allowed
RESTORE_TARGET=staging run_restore guard-target
ok 'เป้าหมายอื่น = ล้ม' not eq "$RC" 0
RESTORE_FILES='all; rm -rf /' run_restore guard-files
ok 'files ไม่ถูกต้อง = ล้ม' not eq "$RC" 0
ok 'บอก files_not_allowed' failed_with files_not_allowed
RESTORE_POINT='../../x' run_restore guard-point
ok 'จุดกู้คืนไม่ถูกต้อง = ล้ม' not eq "$RC" 0
ok 'บอก restore_point_not_allowed' failed_with restore_point_not_allowed
RESTORE_POINT=20200101T000000Z run_restore guard-missing-point
ok 'จุดกู้คืนไม่มีจริง = ล้ม' not eq "$RC" 0
ok 'ตัวกันไม่อัปโหลดอะไร' eq "$(grep -c '^PUT' "$FAKE_B2_LOG")" 0

echo "restore-e2e: ผ่าน $pass ล้ม $fail"
[ "$fail" = 0 ]
