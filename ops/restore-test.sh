#!/usr/bin/env bash
# ทดสอบกู้คืนหนึ่งรอบ — TECHNICAL_BUILD_PLAN ส่วน 8 (ขั้นตอน restore-test.yml) และ 13 ข้อ 16, TECHNICAL_DESIGN ส่วน 12
#
# รันจาก .github/workflows/restore-test.yml (เปิด Supabase ชั่วคราวและติดตั้ง psql/pg_restore/rclone อยู่ใน workflow)
# ทดสอบในเครื่องด้วย ops/backup-test/ (Postgres ในเครื่อง + remote ปลอม ไม่แตะ B2/Drive จริง)
#
# ขอบเขต: อ่านจุดกู้คืนจาก Drive → กู้ลงฐานข้อมูลในเครื่องของ runner → วางไฟล์ตัวอย่างใต้ prefix ทดสอบใน kemi-dev-files
#   → ตรวจ → ลบไฟล์ในรอบเดียวกัน · ไม่ต่อฐานข้อมูลของ kemi-dev/kemi-prod และไม่แตะ kemi-files (ไม่มีทั้งรหัสผ่านและกุญแจ)
#
# ตัวแปรที่ต้องมี
#   RESTORE_TARGET               dev | prod — ชุดจุดกู้คืนที่อ่าน (ต้องตรงกับโฟลเดอร์ Drive ใน rclone config)
#   PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE   ฐานข้อมูลชั่วคราวในเครื่องเท่านั้น (ดู restore_db_allowed)
#   RCLONE_CONFIG_CONTENT        rclone.conf ของเป้าหมาย (ใช้แค่ remote gcrypt; b2ro ถูกลบออกจากสำเนาชั่วคราวก่อนใช้)
#   RESTORE_B2_KEY_ID RESTORE_B2_APP_KEY   กุญแจ B2 จำกัด bucket kemi-dev-files + prefix restore-test/ (ops/backup-setup.md)
#   B2_S3_ENDPOINT B2_REGION
# ไม่บังคับ
#   RESTORE_POINT                latest (ค่าเริ่มต้น) | ชื่อรอบ เช่น 20261025T053012Z
#   RESTORE_FILES                sample (ค่าเริ่มต้น) | all
#   RESTORE_RUN_TAG              ชื่อโฟลเดอร์ย่อยใต้ prefix ทดสอบ (workflow ใช้ run id)
#   RESTORE_SWEEP_ONLY=1         ลบของค้างใต้ prefix ทดสอบแล้วจบ (ขั้นสำรองของ workflow เมื่อรอบถูกยกเลิก)
#   RESTORE_ALLOW_LOCAL_REMOTE=1 ยอม gcrypt ที่ครอบโฟลเดอร์ในเครื่อง เฉพาะเป้าหมาย dev — สำหรับ ops/backup-test เท่านั้น
#   HC_PING_URL HC_STATE_FILE    Healthchecks kemi-restore-test (workflow ส่งเฉพาะเป้าหมาย prod)
#   RESTORE_RESULT_FILE          เขียนผล (succeeded/point/files/detail) ให้ ops/restore-record.sh บันทึกลง prod
#
# log ต้องไม่มีชื่อนักเรียน ชื่อไฟล์ final_key เนื้อความคิดเห็น หรือความลับ (prod เป็นข้อมูลจริง):
#   ผลของ psql/pg_restore/rclone/aws เก็บลงไฟล์ใน $WORK ซึ่งลบตอนจบ · พิมพ์เฉพาะจำนวน ชื่อตาราง และชื่อขั้น · ไม่ใช้ set -x
set -Eeuo pipefail
umask 077

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# target_value crypt_remote_ok key_ok md5_comparable stamp_ok log die
export BACKUP_LIB_ONLY=1
# shellcheck source=ops/backup.sh
. "$here/backup.sh"
unset BACKUP_LIB_ONLY

# ---------------------------------------------------------------------------
# ปลายทางเขียนตาย (ไม่รับจาก env): กุญแจก็จำกัดไว้ที่เดียวกัน จึงเขียน kemi-files ไม่ได้ทั้งสองชั้น
# เพดาน: โควตา B2 เป็นของทั้งบัญชี (Class B 2,500 คำขอ/วัน · ดาวน์โหลด 1 GB/วัน · bucket ทดสอบกันไว้ 0.5 GB — BUILD_PLAN 3)
#   ไฟล์ละ GET 1 ครั้งตอนอ่านกลับ จึงใช้ไม่เกิน 500 คำขอ และ 300 MB ต่อรอบ เหลือให้นักเรียนและรอบสำรองในวันเดียวกัน
# ---------------------------------------------------------------------------
readonly TEST_BUCKET=kemi-dev-files
readonly TEST_PREFIX=restore-test
readonly SAMPLE_FILES=50
readonly SAMPLE_BYTES=100000000
readonly ALL_FILES=500
readonly ALL_BYTES=300000000

# ---------------------------------------------------------------------------
# ฟังก์ชันล้วน (ops/backup-test/restore-unit.sh)
# ---------------------------------------------------------------------------
# ฐานข้อมูลชั่วคราวในเครื่องเท่านั้น: pooler/โปรเจกต์จริงใช้ผู้ใช้ postgres.<ref> และ host อื่น จึงไม่ผ่าน
restore_db_allowed() { # $1 PGHOST $2 PGUSER
  [[ "$1" =~ ^(localhost|127\.0\.0\.1|host\.docker\.internal)$ ]] && [ "$2" = supabase_admin ]
}

# gcrypt ต้องครอบโฟลเดอร์ Drive ของเป้าหมาย — ยอมโฟลเดอร์ในเครื่องเฉพาะ dev ตอนทดสอบ
restore_remote_ok() { # $1 ค่า remote ของ gcrypt $2 target $3 allow_local
  crypt_remote_ok "$1" "$2" && return 0
  [ "$2" = dev ] && [ "${3:-}" = 1 ]
}

run_tag_ok() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

test_key() { printf '%s/%s/%s' "$TEST_PREFIX" "$1" "$2"; } # $1 run tag $2 final_key

# ลบได้เฉพาะของใต้ prefix ทดสอบ
sweep_key_ok() { [[ "$1" == "$TEST_PREFIX/"* ]] && [[ "$1" != *..* ]]; }

# เลือกจากรายการที่สุ่มแล้ว (csv: key,version,size,checksum ไม่มีหัว) ไม่เกินจำนวนและขนาดรวม
pick_files() { # $1 รายการ $2 จำนวนสูงสุด $3 ไบต์สูงสุด
  awk -F, -v mf="$2" -v mb="$3" 'n < mf && t + $3 <= mb { print; n++; t += $3 }' "$1"
}

within_budget() { # $1 จำนวนไฟล์ $2 ไบต์รวม $3 จำนวนสูงสุด $4 ไบต์สูงสุด
  [ "$1" -le "$3" ] && [ "$2" -le "$4" ]
}

# ไฟล์ต้องตรงกับ manifest (ขนาด + MD5 เมื่อ checksum เป็น MD5)
file_matches_manifest() { # $1 ไฟล์ $2 ขนาด $3 checksum
  [ -f "$1" ] && [ "$(stat -c %s "$1")" = "$2" ] || return 1
  if md5_comparable "$3"; then
    [ "$(md5sum "$1" | cut -d' ' -f1)" = "${3,,}" ] || return 1
  fi
}

# ข้อความผิดพลาดของ pg_restore แบบตัดค่าในเครื่องหมายคำพูดออก (อาจมีข้อมูลจากแถว)
safe_restore_errors() { # $1 ไฟล์ stderr
  { grep -m 5 '^pg_restore: error:' "$1" || true; } |
    sed -E "s/\"[^\"]*\"/\"…\"/g; s/'[^']*'/'…'/g" | cut -c1-100
}

if [ "${RESTORE_LIB_ONLY:-}" = 1 ]; then
  # shellcheck disable=SC2317 # ใช้เมื่อ source เป็นไลบรารี (unit test)
  return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# เครื่องมือ
# ---------------------------------------------------------------------------
: "${RESTORE_B2_KEY_ID:?}" "${RESTORE_B2_APP_KEY:?}" "${B2_S3_ENDPOINT:?}" "${B2_REGION:?}"

STEP=init
WORK=$(mktemp -d)
SWEPT=0
SUCCESS_PINGED=0
STAMP=''
READ_BACK=0

# ผลของรอบสำหรับขั้นบันทึกผล (ทาง A) — จำนวนและชื่อขั้นเท่านั้น
write_result() { # $1 true|false $2 detail
  [ -n "${RESTORE_RESULT_FILE:-}" ] || return 0
  printf 'succeeded=%s\npoint=%s\nfiles=%s\ndetail=%s\n' "$1" "$STAMP" "$READ_BACK" "$2" >"$RESTORE_RESULT_FILE"
}

s3() { # $1 คำสั่ง s3api ที่เหลือคืออาร์กิวเมนต์ — stderr มี key จึงเก็บลงไฟล์
  local op=$1
  shift
  AWS_ACCESS_KEY_ID=$RESTORE_B2_KEY_ID AWS_SECRET_ACCESS_KEY=$RESTORE_B2_APP_KEY AWS_DEFAULT_REGION=$B2_REGION \
    AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
    AWS_EC2_METADATA_DISABLED=true \
    aws s3api "$op" --endpoint-url "$B2_S3_ENDPOINT" --bucket "$TEST_BUCKET" "$@" 2>>"$WORK/aws.err"
}

# ลบทุกเวอร์ชันใต้ prefix ทดสอบโดยระบุ version_id แล้วยืนยันว่าว่าง — ใช้ทั้งก่อนเริ่ม (ของค้างจากรอบที่ถูกยกเลิก) และตอนจบ
sweep_test_prefix() {
  local key ver bad=0 deleted=0 left
  : >"$WORK/versions.json"
  s3 list-object-versions --prefix "$TEST_PREFIX/" --output json >"$WORK/versions.json" || return 1
  while IFS=$'\t' read -r key ver; do
    [ -n "$key" ] || continue
    if sweep_key_ok "$key" && s3 delete-object --key "$key" --version-id "$ver" >/dev/null; then
      deleted=$((deleted + 1))
    else
      bad=$((bad + 1))
    fi
  done < <(jq -r '((.Versions // []) + (.DeleteMarkers // []))[] | "\(.Key)\t\(.VersionId)"' "$WORK/versions.json" 2>/dev/null)
  s3 list-object-versions --prefix "$TEST_PREFIX/" --output json >"$WORK/versions.json" || return 1
  left=$(jq -r '((.Versions // []) + (.DeleteMarkers // [])) | length' "$WORK/versions.json" 2>/dev/null || echo 0)
  log "ลบใต้ prefix ทดสอบ $deleted เวอร์ชัน · เหลือ ${left:-0} · ลบไม่ได้ $bad"
  [ "$bad" = 0 ] && [ "${left:-0}" = 0 ]
}

hc_ping() { # $1 '' | fail  $2 ข้อความสั้น (จำนวนและชื่อรอบเท่านั้น)
  [ -n "${HC_PING_URL:-}" ] || return 0
  local url=$HC_PING_URL
  [ -n "$1" ] && url="$HC_PING_URL/$1"
  curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "${2:-}" "$url" 2>/dev/null || log 'ส่ง ping Healthchecks ไม่สำเร็จ'
  if [ -n "${HC_STATE_FILE:-}" ]; then printf '%s\n' "${1:-success}" >"$HC_STATE_FILE"; fi
}

on_exit() {
  local rc=$?
  set +e
  trap - EXIT
  local at=$STEP
  STEP=cleanup
  if [ "$SWEPT" != 1 ] && ! sweep_test_prefix; then
    log 'ลบไฟล์ทดสอบไม่ครบ — ดูขั้นสำรองของ workflow'
    [ "$rc" != 0 ] || rc=1
  fi
  if [ "$rc" != 0 ] && [ "$SUCCESS_PINGED" != 1 ] && [ "${RESTORE_SWEEP_ONLY:-}" != 1 ]; then
    write_result false "ล้มที่ขั้น $at (exit $rc)"
    hc_ping fail "kemi-restore-test ล้มที่ขั้น $at (exit $rc)"
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT TERM

if [ "${RESTORE_SWEEP_ONLY:-}" = 1 ]; then
  STEP=sweep
  sweep_test_prefix
  SWEPT=1
  exit 0
fi

# ---------------------------------------------------------------------------
# 0. ตัวกัน
# ---------------------------------------------------------------------------
STEP=guard
: "${RCLONE_CONFIG_CONTENT:?}" "${PGHOST:?}" "${PGUSER:?}" "${PGPASSWORD:?}"
TARGET=${RESTORE_TARGET:-}
target_value "$TARGET" ref >/dev/null || die 'target_not_allowed: RESTORE_TARGET ต้องเป็น dev หรือ prod'
restore_db_allowed "$PGHOST" "$PGUSER" || die 'db_not_allowed: กู้ได้เฉพาะฐานข้อมูลชั่วคราวในเครื่อง (supabase_admin)'
MODE=${RESTORE_FILES:-sample}
case "$MODE" in
  sample | all) ;;
  *) die 'files_not_allowed: RESTORE_FILES ต้องเป็น sample หรือ all' ;;
esac
POINT=${RESTORE_POINT:-latest}
[ "$POINT" = latest ] || stamp_ok "$POINT" || die 'restore_point_not_allowed: ใส่ latest หรือชื่อรอบ เช่น 20261025T053012Z'
RUN_TAG=${RESTORE_RUN_TAG:-local}
run_tag_ok "$RUN_TAG" || die 'run_tag_not_allowed'
export PGPORT=${PGPORT:-54322} PGDATABASE=${PGDATABASE:-postgres} PGCLIENTENCODING=UTF8
export PGAPPNAME=kemi-restore-test PGCONNECT_TIMEOUT=20
log "เป้าหมาย $TARGET · จุดกู้คืน $POINT · ไฟล์ $MODE"

sql() { # คำสั่ง SQL ผ่าน stdin — stderr อาจมีข้อมูลจากแถว จึงเก็บลงไฟล์
  printf '%s\n' "$1" | psql -X -q -A -t -v ON_ERROR_STOP=1 2>>"$WORK/psql.err"
}

printf '%s\n' "$RCLONE_CONFIG_CONTENT" >"$WORK/rclone.conf"
RCLONE=(rclone --config "$WORK/rclone.conf" --log-level ERROR --log-file "$WORK/rclone.log"
  --retries 3 --low-level-retries 10)
"${RCLONE[@]}" config delete b2ro >/dev/null 2>&1 || true
[ "$("${RCLONE[@]}" config dump | jq -r '.gcrypt.type // empty')" = crypt ] || die 'rclone config ไม่มี remote gcrypt แบบ crypt'
restore_remote_ok "$("${RCLONE[@]}" config dump | jq -r '.gcrypt.remote // empty')" "$TARGET" "${RESTORE_ALLOW_LOCAL_REMOTE:-}" ||
  die "target_not_allowed: remote gcrypt ไม่ได้ครอบ gdrive:$(target_value "$TARGET" drive) ของ $TARGET (rclone config ผิดชุด)"

# ของค้างจากรอบที่ถูกยกเลิก: ลบก่อนเริ่ม เพื่อไม่ให้ไฟล์จริงค้างและไม่กินพื้นที่
STEP=preflight
sweep_test_prefix || die 'ลบของค้างใต้ prefix ทดสอบไม่ได้ (ตรวจสิทธิ์กุญแจ RESTORE_B2_*)'

# ---------------------------------------------------------------------------
# 1. ดึง dump + manifest ของจุดที่เลือกจาก gcrypt: (อ่านอย่างเดียว)
# ---------------------------------------------------------------------------
STEP=fetch
"${RCLONE[@]}" lsf --dirs-only gcrypt:runs | tr -d '/' | { grep -E '^[0-9]{8}T[0-9]{6}Z$' || true; } | sort >"$WORK/runs.txt"
[ -s "$WORK/runs.txt" ] || die 'ไม่พบจุดกู้คืนใน Drive (รหัส crypt ไม่ตรงหรือยังไม่มีรอบสำรอง)'
if [ "$POINT" = latest ]; then STAMP=$(tail -n 1 "$WORK/runs.txt"); else STAMP=$POINT; fi
grep -qxF "$STAMP" "$WORK/runs.txt" || die 'ไม่พบจุดกู้คืนที่เลือกใน Drive'
"${RCLONE[@]}" copy "gcrypt:runs/$STAMP" "$WORK/run"
for f in schema.dump data.dump manifest.csv meta.json; do
  [ -s "$WORK/run/$f" ] || die "จุดกู้คืนไม่ครบ: ไม่มี $f"
done
log "จุดกู้คืน $STAMP: schema $(stat -c %s "$WORK/run/schema.dump") ไบต์, data $(stat -c %s "$WORK/run/data.dump") ไบต์"

# ---------------------------------------------------------------------------
# 2. meta.json ↔ manifest.csv และรุ่นฐานข้อมูล
# ---------------------------------------------------------------------------
STEP=meta
META=$WORK/run/meta.json
[ "$(jq -r '.target // empty' "$META")" = "$TARGET" ] || die 'meta_target_mismatch: จุดกู้คืนไม่ใช่ของเป้าหมายที่เลือก'
[ "$(jq -r '.stamp // empty' "$META")" = "$STAMP" ] || die 'meta_stamp_mismatch'
jq -e '.table_rows | type == "object" and length > 0' "$META" >/dev/null ||
  die 'meta_no_table_rows: จุดกู้คืนนี้เก่ากว่า P7-08 ไม่มีจำนวนแถวให้เทียบ เลือกรอบใหม่กว่า'
tail -n +2 "$WORK/run/manifest.csv" >"$WORK/manifest.body"
MANIFEST_COUNT=$(wc -l <"$WORK/manifest.body")
MANIFEST_BYTES=$(awk -F, '{ t += $3 } END { printf "%.0f", t }' "$WORK/manifest.body")
[ "$(jq -r '.file_count' "$META")" = "$MANIFEST_COUNT" ] || die 'meta_file_count_mismatch'
[ "$(jq -r '.total_bytes' "$META")" = "$MANIFEST_BYTES" ] || die 'meta_total_bytes_mismatch'
while IFS=, read -r key _; do
  key_ok "$key" || die 'invalid_key: manifest มี key รูปแบบไม่ถูกต้อง'
done <"$WORK/manifest.body"
server_major=$(sql "select current_setting('server_version_num')::int / 10000")
[ "$(jq -r '.server_major' "$META")" = "$server_major" ] || die "server_major_mismatch: ฐานข้อมูลชั่วคราวรุ่น $server_major ไม่ตรงจุดกู้คืน"
log "manifest $MANIFEST_COUNT ไฟล์ $MANIFEST_BYTES ไบต์ ตรง meta.json · Postgres $server_major"

# ---------------------------------------------------------------------------
# 3. กู้: ล้าง public/private (migration ของ commit นี้อาจใหม่กว่า dump) → schema → data → ตัดการเชื่อมบัญชี Auth
# ---------------------------------------------------------------------------
STEP=restore_schema
sql 'drop schema if exists public cascade; drop schema if exists private cascade;' >/dev/null
if ! pg_restore --no-password --exit-on-error --dbname="$PGDATABASE" "$WORK/run/schema.dump" 2>"$WORK/restore.err"; then
  safe_restore_errors "$WORK/restore.err"
  die 'กู้ schema ไม่สำเร็จ'
fi
STEP=restore_data
if ! pg_restore --no-password --exit-on-error --data-only --disable-triggers --dbname="$PGDATABASE" "$WORK/run/data.dump" 2>"$WORK/restore.err"; then
  safe_restore_errors "$WORK/restore.err"
  die 'กู้ data ไม่สำเร็จ'
fi
STEP=detach_auth
detached=$(sql "begin; set local session_replication_role = replica;
  with u as (update public.accounts set auth_user_id = null where auth_user_id is not null returning 1) select count(*) from u;
  commit;")
log "ตัดการเชื่อมบัญชี Auth $detached บัญชี (ฐานข้อมูลชั่วคราวไม่มี auth.users ของจริง)"

# ---------------------------------------------------------------------------
# 4. ตรวจตรงตัว: จำนวนแถวทุกตารางกับ meta.json · assets ที่ ready กับ manifest.csv
# ---------------------------------------------------------------------------
STEP=table_rows
# คำนวณแบบเดียวกับ ops/backup.sh (ไม่นับตารางที่ไม่สำรองข้อมูล) — แก้ที่หนึ่งต้องแก้อีกที่
ROWS=$(sql "select coalesce(jsonb_object_agg(t.name, t.n order by t.name), '{}') from (select n.nspname || '.' || c.relname as name, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint as n from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public', 'private') and c.relkind in ('r', 'p') and n.nspname || '.' || c.relname not in ('private.backup_manifests', 'private.backup_run_files')) t;")
META_ROWS=$(jq -c '.table_rows' "$META")
# ชื่อตารางและจำนวนไม่ใช่ข้อมูลส่วนบุคคล
ROW_DIFF=$(jq -rn --argjson a "$META_ROWS" --argjson b "$ROWS" '($a + $b) | keys[] | . as $k | select($a[$k] != $b[$k]) | "\($k) meta=\($a[$k]) db=\($b[$k])"')
if [ -n "$ROW_DIFF" ]; then
  printf '%s\n' "$ROW_DIFF"
  die 'table_rows_mismatch: จำนวนแถวไม่ตรง meta.json'
fi
TABLE_COUNT=$(jq 'length' <<<"$ROWS")
TOTAL_ROWS=$(jq '[.[]] | add' <<<"$ROWS")
log "จำนวนแถวตรงตัว $TABLE_COUNT ตาราง รวม $TOTAL_ROWS แถว"
log "โทเคนคงเหลือรวม $(sql 'select coalesce(sum(balance), 0) from public.wallets') · เครื่องรางที่มี $(jq -r '."public.owned_charms" // 0' <<<"$ROWS") ชิ้น"

STEP=manifest
sql "\\copy (select final_key, version_id, size_bytes, checksum from public.assets where status = 'ready') to '$WORK/assets.csv' with (format csv)"
LC_ALL=C sort "$WORK/assets.csv" >"$WORK/assets.sorted"
LC_ALL=C sort "$WORK/manifest.body" >"$WORK/manifest.sorted"
cmp -s "$WORK/assets.sorted" "$WORK/manifest.sorted" || die 'manifest_mismatch: assets ที่ ready ในฐานข้อมูลที่กู้ไม่ตรง manifest.csv'
log "assets ที่ ready ตรง manifest ทุกแถว ($MANIFEST_COUNT ไฟล์)"

# ---------------------------------------------------------------------------
# 5. เลือกไฟล์: sample = สุ่มไม่เกินเพดาน · all = ทุกไฟล์ ถ้าเกินเพดานไม่เริ่ม
# ---------------------------------------------------------------------------
STEP=pick
if [ "$MODE" = sample ]; then
  shuf "$WORK/manifest.body" >"$WORK/shuffled.csv"
  pick_files "$WORK/shuffled.csv" "$SAMPLE_FILES" "$SAMPLE_BYTES" >"$WORK/picked.csv"
else
  within_budget "$MANIFEST_COUNT" "$MANIFEST_BYTES" "$ALL_FILES" "$ALL_BYTES" ||
    die "over_budget: $MANIFEST_COUNT ไฟล์ $MANIFEST_BYTES ไบต์ เกินเพดานรอบละ $ALL_FILES ไฟล์ $ALL_BYTES ไบต์ — ใช้ sample"
  cp "$WORK/manifest.body" "$WORK/picked.csv"
fi
PICKED=$(wc -l <"$WORK/picked.csv")
PICKED_BYTES=$(awk -F, '{ t += $3 } END { printf "%.0f", t }' "$WORK/picked.csv")
log "เลือก $PICKED จาก $MANIFEST_COUNT ไฟล์ · $PICKED_BYTES ไบต์"

UPLOADED=0
if [ "$PICKED" -gt 0 ]; then
  # -------------------------------------------------------------------------
  # 6. ดึงจาก Drive → ตรวจกับ manifest (ไม่อ่าน kemi-files)
  # -------------------------------------------------------------------------
  STEP=drive
  cut -d, -f1 "$WORK/picked.csv" >"$WORK/picked.keys"
  "${RCLONE[@]}" copy gcrypt: "$WORK/f" --files-from "$WORK/picked.keys" --no-traverse ||
    die 'ดึงไฟล์จาก Drive ไม่สำเร็จ'
  bad=0
  while IFS=, read -r key _ size sum; do
    file_matches_manifest "$WORK/f/$key" "$size" "$sum" || bad=$((bad + 1))
  done <"$WORK/picked.csv"
  [ "$bad" = 0 ] || die "drive_mismatch: ไฟล์จาก Drive ไม่ตรง manifest $bad ไฟล์"
  log "ไฟล์จาก Drive ตรง manifest $PICKED ไฟล์"

  # -------------------------------------------------------------------------
  # 7. วางใต้ prefix ทดสอบ เก็บ version_id ใหม่ (BUILD_PLAN ข้อ 3, TECHNICAL_DESIGN 12 ขั้นตอนกู้ไฟล์กลับ B2)
  # -------------------------------------------------------------------------
  STEP=upload
  : >"$WORK/new-versions.csv"
  while IFS=, read -r key _; do
    s3 put-object --key "$(test_key "$RUN_TAG" "$key")" --body "$WORK/f/$key" --output json >"$WORK/put.json" ||
      die 'อัปโหลดไฟล์ทดสอบไม่สำเร็จ'
    ver=$(jq -r '.VersionId // empty' "$WORK/put.json")
    [ -n "$ver" ] || die 'B2 ไม่คืน version_id'
    printf '%s,%s\n' "$key" "$ver" >>"$WORK/new-versions.csv"
    UPLOADED=$((UPLOADED + 1))
  done <"$WORK/picked.csv"
  log "อัปโหลด $UPLOADED ไฟล์ใต้ $TEST_PREFIX/$RUN_TAG/"

  # -------------------------------------------------------------------------
  # 8. จับคู่ด้วย final_key แล้วอัปเดต version_id ในฐานข้อมูลชั่วคราว: trigger กันการแก้ไว้ จึงใช้ replica เฉพาะคำสั่งนี้
  # -------------------------------------------------------------------------
  STEP=version_ids
  matched=$(sql "create temp table restored (final_key text primary key, version_id text not null);
    \\copy restored from '$WORK/new-versions.csv' with (format csv)
    begin; set local session_replication_role = replica;
    with u as (update public.assets a set version_id = r.version_id from restored r
                where a.final_key = r.final_key and a.status = 'ready' returning 1) select count(*) from u;
    commit;
    \\copy (select a.final_key, a.version_id, a.size_bytes, a.checksum from public.assets a join restored r on r.final_key = a.final_key and r.version_id = a.version_id where a.status = 'ready') to '$WORK/readback.csv' with (format csv)")
  [ "$matched" = "$UPLOADED" ] || die "version_mismatch: อัปเดต version_id $matched แถว ไม่เท่าไฟล์ที่กู้ $UPLOADED"
  # join ด้วย version_id ใหม่: แถวที่ยังเป็นค่าเดิมจะไม่ออกมาในรายการอ่านกลับ
  [ "$(wc -l <"$WORK/readback.csv")" = "$UPLOADED" ] || die 'version_mismatch: อ่านกลับจากฐานข้อมูลไม่ครบ'
  log "อัปเดต version_id ใหม่ $matched แถว"

  # -------------------------------------------------------------------------
  # 9. อ่านกลับตาม version_id ที่อยู่ในฐานข้อมูลที่กู้ แล้วเทียบขนาด/MD5 กับ checksum ใน manifest
  # -------------------------------------------------------------------------
  STEP=read_back
  bad=0
  while IFS=, read -r key ver size sum; do
    if s3 get-object --key "$(test_key "$RUN_TAG" "$key")" --version-id "$ver" "$WORK/got" >/dev/null &&
      file_matches_manifest "$WORK/got" "$size" "$sum"; then
      READ_BACK=$((READ_BACK + 1))
    else
      bad=$((bad + 1))
    fi
    rm -f "$WORK/got"
  done <"$WORK/readback.csv"
  [ "$bad" = 0 ] || die "read_back_mismatch: อ่านกลับไม่ตรง $bad ไฟล์"
  log "อ่านกลับตรง manifest $READ_BACK ไฟล์"
else
  log 'จุดกู้คืนนี้ไม่มีไฟล์ ข้ามขั้นไฟล์'
fi

# ---------------------------------------------------------------------------
# 10. ลบไฟล์ทดสอบก่อนรายงานผ่าน — ลบไม่ครบ = ล้ม
# ---------------------------------------------------------------------------
STEP=cleanup
sweep_test_prefix || die 'ลบไฟล์ทดสอบไม่ครบ'
SWEPT=1

STEP=finish
summary="target=$TARGET point=$STAMP files=$MODE tables=$TABLE_COUNT rows=$TOTAL_ROWS manifest=$MANIFEST_COUNT uploaded=$UPLOADED verified=$READ_BACK bytes=$PICKED_BYTES"
log "ผ่าน: $summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo '### ผลทดสอบกู้คืน: ผ่าน'
    echo "| เป้าหมาย | จุดกู้คืน | ไฟล์ | ตาราง/แถว | manifest | อ่านกลับตรง | ไบต์ |"
    echo '| --- | --- | --- | --- | --- | --- | --- |'
    echo "| $TARGET | $STAMP | $MODE | $TABLE_COUNT / $TOTAL_ROWS | $MANIFEST_COUNT | $READ_BACK | $PICKED_BYTES |"
  } >>"$GITHUB_STEP_SUMMARY"
fi
write_result true "$summary"
hc_ping '' "kemi-restore-test ผ่าน $summary"
SUCCESS_PINGED=1
