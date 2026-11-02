#!/usr/bin/env bash
# สำรองข้อมูลหนึ่งรอบ — TECHNICAL_BUILD_PLAN ส่วน 8 (ขั้นตอน backup.yml ข้อ 2–9), TECHNICAL_DESIGN ส่วน 9.3 และ 12
#
# รันจาก .github/workflows/backup.yml (ping /start และติดตั้ง psql/pg_dump/rclone อยู่ใน workflow)
# ทดสอบในเครื่องด้วย ops/backup-test/ (Postgres ในเครื่อง + remote ปลอม ไม่แตะ B2/Drive จริง)
#
# ตัวแปรที่ต้องมี
#   PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD   Session pooler ของโปรเจกต์เป้าหมาย (รหัสผ่านเป็น secret ตัวเดียว)
#   RCLONE_CONFIG_CONTENT                        rclone.conf ที่มี remote gcrypt (crypt ครอบ gdrive:kemi-backup หรือ
#                                                gdrive:kemi-backup-prod ตามเป้าหมาย) และ b2ro
#   B2_BUCKET B2_S3_ENDPOINT B2_REGION           bucket ที่อ่าน (อ่านด้วยกุญแจ b2ro ผ่าน S3 API ระบุ versionId)
# ไม่บังคับ
#   BACKUP_TARGET              dev (ค่าเริ่มต้น) | prod — ต้องตรงกับ PGUSER/bucket/โฟลเดอร์ Drive ทั้งชุด (P7-08)
#   HC_PING_URL                ว่าง = ไม่ ping (ทดสอบในเครื่อง)
#   HC_STATE_FILE              ไฟล์บอก workflow ว่าส่ง ping ผล (success/fail) แล้ว
#   SUPABASE_URL SUPABASE_PING_KEY   ข้อ 9: เรียก public.ping() ผ่าน Data API (secret key แยกของงานนี้)
#   PG_BIN                     โฟลเดอร์ psql/pg_dump รุ่นหลักตรงเซิร์ฟเวอร์
#   SIMULATE_FAILURE=true      ล้มโดยตั้งใจหลังเริ่มรอบ (ทดสอบอีเมล Healthchecks + ปลดล็อก)
#   BACKUP_ALLOW_LOCAL=1       ยอมฐานข้อมูลในเครื่อง (localhost/host.docker.internal) — สำหรับ ops/backup-test เท่านั้น
#
# ห้ามพิมพ์ความลับ (รหัสผ่าน, rclone.conf, URL ping, กุญแจ) — ไม่ใช้ set -x
set -Eeuo pipefail
umask 077

# ---------------------------------------------------------------------------
# ตัวกัน: รันได้เฉพาะชุด dev หรือ prod ที่เขียนตายในสคริปต์ (ไม่รับ ref/bucket/โฟลเดอร์จาก env)
# ชุดต้องตรงกันทั้ง ref + bucket + โฟลเดอร์ Drive — ห้ามสำรอง dev กับ prod ปนกัน (BUILD_PLAN 10 ระยะ 7)
# ---------------------------------------------------------------------------
readonly DEV_REF=igchlnmxbghsigyziomk
readonly DEV_BUCKET=kemi-dev-files
readonly DEV_DRIVE=kemi-backup
readonly PROD_REF=fcwbomasayvlubijsssh
readonly PROD_BUCKET=kemi-files
readonly PROD_DRIVE=kemi-backup-prod
readonly KEY_RE='^files/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'

STEP=init
RUN_ID=''
STAMP=''
LOCKED=0
FINISHED=0
RUN_UPLOADED=0
SUCCESS_PINGED=0
USAGE_REQUESTS=0
USAGE_BYTES=0
RECORDED_REQUESTS=0
RECORDED_BYTES=0
SA_PID=''
WORK=''

log() { printf '%s [%s] %s\n' "$(date -u +%H:%M:%S)" "$STEP" "$*"; }
die() {
  log "ERROR: $*"
  exit 1
}

# ---------------------------------------------------------------------------
# ฟังก์ชันล้วน (ทดสอบได้โดยไม่ต่ออะไร — ops/backup-test/unit.sh)
# ---------------------------------------------------------------------------
# ค่าของเป้าหมาย: target_value dev|prod ref|bucket|drive → ค่าที่เขียนตาย (เป้าหมายอื่น = ล้ม)
target_value() { # $1 target $2 field
  case "$1:$2" in
    dev:ref) printf '%s' "$DEV_REF" ;;
    dev:bucket) printf '%s' "$DEV_BUCKET" ;;
    dev:drive) printf '%s' "$DEV_DRIVE" ;;
    prod:ref) printf '%s' "$PROD_REF" ;;
    prod:bucket) printf '%s' "$PROD_BUCKET" ;;
    prod:drive) printf '%s' "$PROD_DRIVE" ;;
    *) return 1 ;;
  esac
}

# อนุญาตเป้าหมาย: bucket และผู้ใช้ pooler (postgres.<ref>) ต้องเป็นของเป้าหมายเดียวกัน
# ฐานข้อมูลในเครื่องได้เฉพาะ dev เมื่อตั้ง BACKUP_ALLOW_LOCAL=1 (ops/backup-test)
target_allowed() { # $1 PGUSER $2 PGHOST $3 bucket $4 allow_local $5 target (dev ถ้าว่าง)
  local user=$1 host=$2 bucket=$3 allow_local=${4:-} target=${5:-dev} ref want_bucket
  ref=$(target_value "$target" ref) || return 1
  want_bucket=$(target_value "$target" bucket) || return 1
  [ "$bucket" = "$want_bucket" ] || return 1
  [ "$user" = "postgres.$ref" ] && return 0
  [ "$target" = dev ] && [ "$allow_local" = 1 ] &&
    [[ "$host" =~ ^(localhost|127\.0\.0\.1|host\.docker\.internal)$ ]] && return 0
  return 1
}

# remote gcrypt ต้องครอบโฟลเดอร์ Drive ของเป้าหมาย (gdrive:kemi-backup / gdrive:kemi-backup-prod) — กันใส่ config ผิดชุด
crypt_remote_ok() { # $1 ค่า remote ของ gcrypt $2 target
  local drive
  drive=$(target_value "$2" drive) || return 1
  [[ "$1" =~ ^[A-Za-z0-9_-]+:$drive/?$ ]]
}

key_ok() { [[ "$1" =~ $KEY_RE ]] && [[ "$1" != *..* ]]; }

# Session pooler + ผู้ใช้ postgres.<ref ของ prod> เท่านั้น (ops/restore-record.sh, ops/guard.sh) — dev/โปรเจกต์อื่นไม่ผ่าน
readonly PROD_POOLER_HOST=aws-0-ap-southeast-1.pooler.supabase.com
prod_db_allowed() { # $1 PGHOST $2 PGUSER $3 allow_local (ฐานข้อมูลในเครื่อง ผู้ใช้ postgres — ops/backup-test เท่านั้น)
  [ "$1" = "$PROD_POOLER_HOST" ] && [ "$2" = "postgres.$PROD_REF" ] && return 0
  [ "${3:-}" = 1 ] && [[ "$1" =~ ^(localhost|127\.0\.0\.1|host\.docker\.internal)$ ]] && [ "$2" = postgres ]
}

# SQL ที่ใช้ร่วมกับ ops/restore-test.sh (ops/sql/) เป็นบรรทัดเดียวสำหรับ session A
sql_file_line() { tr '\n' ' ' <"$SQL_DIR/$1"; }
SQL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql

# ETag ของ PUT/CopyObject ชิ้นเดียวคือ MD5 (BUILD_PLAN 13 ข้อ 9) — ค่าแบบอื่นตรวจแค่ขนาด
md5_comparable() { [[ "$1" =~ ^[0-9a-fA-F]{32}$ ]]; }

# ไฟล์ใหม่ที่ยังไม่มีใน Drive ขนาดตรง (csv ไม่มีหัว) — ที่มีแล้วคือของเหลือจากรอบที่ล้มหลังคัดลอก ไม่ต้องอ่าน B2 ซ้ำ
not_in_drive() { # $1 new.csv $2 drive.tsv
  awk 'FILENAME == ARGV[1] { split($0, d, "\t"); have[d[1]] = d[2]; next }
       { split($0, f, ","); if (!(f[1] in have) || have[f[1]] != f[3]) print }' "$2" "$1"
}

# เทียบรายการ manifest (key,size) กับรายการใน Drive (key<TAB>size) → พิมพ์ key ที่หายหรือขนาดไม่ตรง
missing_or_mismatch() { # $1 manifest.csv (มีหัว) $2 drive.tsv
  awk 'FILENAME == ARGV[1] { split($0, d, "\t"); have[d[1]] = d[2]; next }
       FNR == 1 { next }
       { split($0, f, ","); if (!(f[1] in have) || have[f[1]] != f[3]) print f[1] }' "$2" "$1"
}

# ชื่อโฟลเดอร์รอบ runs/<เวลา UTC> ที่สคริปต์นี้สร้าง — โฟลเดอร์ชื่ออื่นไม่แตะ
stamp_ok() { [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; }

if [ "${BACKUP_LIB_ONLY:-}" = 1 ]; then
  # shellcheck disable=SC2317 # ใช้เมื่อ source เป็นไลบรารี (unit test)
  return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# เครื่องมือ
# ---------------------------------------------------------------------------
: "${PGHOST:?}" "${PGUSER:?}" "${PGPASSWORD:?}" "${RCLONE_CONFIG_CONTENT:?}"
: "${B2_BUCKET:?}" "${B2_S3_ENDPOINT:?}" "${B2_REGION:?}"
export PGPORT=${PGPORT:-5432} PGDATABASE=${PGDATABASE:-postgres} PGCLIENTENCODING=UTF8
export PGAPPNAME=kemi-backup PGCONNECT_TIMEOUT=20

STEP=guard
TARGET=${BACKUP_TARGET:-dev}
target_value "$TARGET" ref >/dev/null || die "target_not_allowed: BACKUP_TARGET ต้องเป็น dev หรือ prod"
target_allowed "$PGUSER" "$PGHOST" "$B2_BUCKET" "${BACKUP_ALLOW_LOCAL:-}" "$TARGET" ||
  die "target_not_allowed: PGUSER/bucket ไม่ตรงชุด $TARGET ($(target_value "$TARGET" ref) / $(target_value "$TARGET" bucket))"
if [ -n "${SUPABASE_URL:-}" ] && [ "${BACKUP_ALLOW_LOCAL:-}" != 1 ] &&
  [ "$SUPABASE_URL" != "https://$(target_value "$TARGET" ref).supabase.co" ]; then
  die "target_not_allowed: SUPABASE_URL ไม่ใช่โปรเจกต์ของ $TARGET"
fi
log "เป้าหมาย $TARGET"

PSQL=(psql -X -q -A -t -v ON_ERROR_STOP=1)
PG_DUMP=pg_dump
if [ -n "${PG_BIN:-}" ]; then
  PSQL[0]="$PG_BIN/psql"
  PG_DUMP="$PG_BIN/pg_dump"
fi

WORK=$(mktemp -d)
mkdir -p "$WORK/new" "$WORK/repair" "$WORK/run"
printf '%s\n' "$RCLONE_CONFIG_CONTENT" >"$WORK/rclone.conf"
# --drive-use-trash=false: ลบถาวร (ค่าเริ่มต้นย้ายลงถังขยะซึ่งยังกินพื้นที่ Drive)
RCLONE=(rclone --config "$WORK/rclone.conf" --log-level NOTICE --drive-use-trash=false
  --retries 3 --low-level-retries 10)

# คำสั่ง SQL หนึ่งชุดผ่าน stdin (ตัวแปร psql :'x' ใช้ได้) — พิมพ์ผลแบบไม่มีหัว
sql() {
  local q=$1
  shift
  printf '%s\n' "$q" | "${PSQL[@]}" "$@"
}

hc_ping() { # $1 '' | start | fail  $2 ข้อความสั้น (ห้ามมีข้อมูลนักเรียน)
  [ -n "${HC_PING_URL:-}" ] || return 0
  local url=$HC_PING_URL
  [ -n "$1" ] && url="$HC_PING_URL/$1"
  curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "${2:-}" "$url" || log "ส่ง ping Healthchecks ไม่สำเร็จ"
  if [ -n "${HC_STATE_FILE:-}" ]; then printf '%s\n' "${1:-success}" >"$HC_STATE_FILE"; fi
}

# ข้อ 9: เรียก ping() ผ่าน Data API (กันโปรเจกต์ Free หลับ) — ล้มไม่ทำให้รอบสำรองล้ม แต่ขึ้นคำเตือนใน Actions
supabase_ping() {
  if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PING_KEY:-}" ]; then
    log 'ข้าม ping() ผ่าน Data API: ไม่มี SUPABASE_URL/SUPABASE_PING_KEY'
    return 0
  fi
  local out
  if out=$(curl -sS -m 15 -X POST "$SUPABASE_URL/rest/v1/rpc/ping" \
    -H "apikey: $SUPABASE_PING_KEY" -H 'Content-Type: application/json' -d '{}' -w ' %{http_code}'); then
    if [[ "$out" == *' 200' ]]; then
      log "ping() ผ่าน Data API: ${out% *}"
      return 0
    fi
  fi
  log "ping() ผ่าน Data API ไม่สำเร็จ: ${out:-เชื่อมต่อไม่ได้}"
  echo "::warning title=ping() ไม่สำเร็จ::เรียก public.ping() ผ่าน Data API ไม่ได้ (${out##* })"
}

# อ่านไฟล์จาก B2 ตามเวอร์ชันที่บันทึก (S3 API, GET เดียว = Class B 1 คำขอ ไม่ HEAD/List)
b2_get() { # $1 key $2 version_id $3 ไฟล์ปลายทาง
  USAGE_REQUESTS=$((USAGE_REQUESTS + 1))
  AWS_ACCESS_KEY_ID=$B2_KEY_ID AWS_SECRET_ACCESS_KEY=$B2_APP_KEY AWS_DEFAULT_REGION=$B2_REGION \
    AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
    AWS_EC2_METADATA_DISABLED=true \
    aws s3api get-object --endpoint-url "$B2_S3_ENDPOINT" --bucket "$B2_BUCKET" \
    --key "$1" --version-id "$2" "$3" >/dev/null || return 1
  USAGE_BYTES=$((USAGE_BYTES + $(stat -c %s "$3")))
}

# ไฟล์ในเครื่องต้องตรงกับ manifest (ขนาด + MD5 เมื่อ checksum เป็น MD5)
file_matches() { # $1 ไฟล์ $2 ขนาด $3 checksum
  [ -f "$1" ] && [ "$(stat -c %s "$1")" = "$2" ] || return 1
  if md5_comparable "$3"; then
    [ "$(md5sum "$1" | cut -d' ' -f1)" = "${3,,}" ] || return 1
  fi
}

# ดาวน์โหลดรายการ (csv: key,version,size,checksum ไม่มีหัว) ลงโฟลเดอร์ แล้วตรวจกับ manifest
fetch_list() { # $1 รายการ $2 โฟลเดอร์ปลายทาง
  local key ver size sum bad=0
  while IFS=, read -r key ver size sum; do
    [ -n "$key" ] || continue
    key_ok "$key" || die "invalid_key: $key"
    mkdir -p "$(dirname "$2/$key")"
    if ! b2_get "$key" "$ver" "$2/$key"; then
      log "อ่านจาก B2 ไม่สำเร็จ: $key"
      bad=$((bad + 1))
    elif ! file_matches "$2/$key" "$size" "$sum"; then
      log "เนื้อไฟล์ไม่ตรง manifest: $key"
      bad=$((bad + 1))
    fi
  done <"$1"
  [ "$bad" = 0 ]
}

# บันทึกคำขอ/ไบต์ที่อ่านจาก B2 ลงงบรายวัน (แหล่ง backup) เฉพาะส่วนที่ยังไม่ได้บันทึก — เรียกซ้ำได้
record_usage() {
  local req=$((USAGE_REQUESTS - RECORDED_REQUESTS)) bytes=$((USAGE_BYTES - RECORDED_BYTES))
  [ "$req" -gt 0 ] || return 0
  sql "select private.b2_usage_add('backup', $req, $bytes)" >/dev/null || return 1
  RECORDED_REQUESTS=$USAGE_REQUESTS
  RECORDED_BYTES=$USAGE_BYTES
  log "บันทึกงบ B2: Class B $req คำขอ, $bytes ไบต์"
}

drive_listing() { # → $WORK/drive.tsv (files/<path><TAB><ขนาดก่อนเข้ารหัส>)
  "${RCLONE[@]}" lsjson -R --files-only gcrypt:files >"$WORK/drive.json"
  jq -r '.[] | "files/\(.Path)\t\(.Size)"' "$WORK/drive.json" | sort >"$WORK/drive.tsv"
}

on_exit() {
  local rc=$?
  set +e
  trap - EXIT
  if [ -n "$SA_PID" ]; then kill "$SA_PID" 2>/dev/null; fi # session A ค้าง = rollback
  if [ -n "$RUN_ID" ] && [ "$FINISHED" != 1 ]; then
    record_usage
    if [ "$RUN_UPLOADED" = 1 ]; then "${RCLONE[@]}" purge "gcrypt:runs/$STAMP"; fi
    sql "select private.backup_finish('$RUN_ID', false, null, null, null, null, :'detail')" \
      -v detail="ล้มที่ขั้น $STEP" >/dev/null && log "บันทึกรอบ $RUN_ID เป็นล้มเหลว"
  fi
  # จบรอบไม่ปลดธงเอง — ปลดทุกครั้งที่ออก (BUILD_PLAN ส่วน 8 ข้อ 2)
  if [ "$LOCKED" = 1 ]; then sql 'select private.backup_release_lock()' >/dev/null && log 'ปลดธง maintenance_locks แล้ว'; fi
  if [ "$rc" != 0 ] && [ "$SUCCESS_PINGED" != 1 ]; then hc_ping fail "kemi-backup ล้มที่ขั้น $STEP (exit $rc)"; fi
  if [ "$STEP" != guard ]; then supabase_ping; fi
  if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
  exit "$rc"
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# 1. ตรวจเครื่องมือ: pg_dump รุ่นหลักต้องตรงกับเซิร์ฟเวอร์
# ---------------------------------------------------------------------------
STEP=tools
server_major=$(sql "select current_setting('server_version_num')::int / 10000")
dump_major=$("$PG_DUMP" --version | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
[ "$server_major" = "$dump_major" ] || die "pg_dump $dump_major ไม่ตรงกับเซิร์ฟเวอร์ $server_major"
B2_KEY_ID=$("${RCLONE[@]}" config dump | jq -r '.b2ro.account // empty')
B2_APP_KEY=$("${RCLONE[@]}" config dump | jq -r '.b2ro.key // empty')
[ -n "$B2_KEY_ID" ] && [ -n "$B2_APP_KEY" ] || die 'rclone config ไม่มี remote b2ro (account/key)'
[ "$("${RCLONE[@]}" config dump | jq -r '.gcrypt.type // empty')" = crypt ] || die 'rclone config ไม่มี remote gcrypt แบบ crypt'
if [ "${BACKUP_ALLOW_LOCAL:-}" != 1 ]; then
  crypt_remote_ok "$("${RCLONE[@]}" config dump | jq -r '.gcrypt.remote // empty')" "$TARGET" ||
    die "target_not_allowed: remote gcrypt ไม่ได้ครอบ gdrive:$(target_value "$TARGET" drive) ของ $TARGET (rclone config ผิดชุด)"
fi
log "pg_dump $dump_major / server $server_major · $(rclone version | sed -n 1p)"

# ---------------------------------------------------------------------------
# 2. เริ่มรอบ: ธง maintenance_locks 2 ชม. + backup_runs running (transaction เดียว)
# ---------------------------------------------------------------------------
STEP=start
RUN_ID=$(sql 'select private.backup_start()')
LOCKED=1
[[ "$RUN_ID" =~ ^[0-9a-f-]{36}$ ]] || die "backup_start คืนค่าไม่ถูกต้อง"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
log "รอบ $RUN_ID → runs/$STAMP"
if [ "${SIMULATE_FAILURE:-}" = true ]; then
  STEP=simulate
  die 'simulated_failure: ล้มโดยตั้งใจเพื่อทดสอบอีเมลของ Healthchecks'
fi

# ---------------------------------------------------------------------------
# 3–4. session A: snapshot + manifest; session B: pg_dump --snapshot เดียวกัน แล้ว COMMIT session A
# ---------------------------------------------------------------------------
STEP=snapshot
coproc SA { "${PSQL[@]}" 2>"$WORK/sa.err"; }

sa_query() { # ส่งคำสั่งหนึ่งบรรทัดที่คืนค่าเดียว แล้วอ่านผล
  local line
  printf '%s\n' "$1" >&"${SA[1]}"
  if ! IFS= read -r -t 120 line <&"${SA[0]}"; then
    log "session A: $(tail -c 500 "$WORK/sa.err" 2>/dev/null)"
    return 1
  fi
  printf '%s' "$line"
}
sa_query 'begin isolation level repeatable read; select 1;' >/dev/null || die 'เปิด session A ไม่ได้'
SNAPSHOT=$(sa_query 'select pg_export_snapshot();') || die 'export snapshot ไม่ได้'
[[ "$SNAPSHOT" =~ ^[0-9A-F-]+$ ]] || die "snapshot id ไม่ถูกต้อง"
MANIFEST_JSON=$(sa_query "select private.backup_record_manifest('$RUN_ID');") || die 'บันทึก manifest ไม่ได้'
FILE_COUNT=$(jq -r '.file_count' <<<"$MANIFEST_JSON")
TOTAL_BYTES=$(jq -r '.total_bytes' <<<"$MANIFEST_JSON")
log "snapshot $SNAPSHOT · manifest $FILE_COUNT ไฟล์ $TOTAL_BYTES ไบต์"
# จำนวนแถวทุกตาราง (P7-08) และยอดโทเคน (P7-01) ณ snapshot เดียวกับ dump — ใช้เทียบตอนกู้คืนแบบตรงตัว
# SQL อยู่ใน ops/sql/ ใช้ร่วมกับ ops/restore-test.sh · ผลเป็น JSON บรรทัดเดียว ไม่มีข้อมูลนักเรียน
TABLE_ROWS=$(sa_query "$(sql_file_line table-rows.sql)") ||
  die 'นับแถวตารางไม่ได้'
jq -e 'type == "object" and length > 0' <<<"$TABLE_ROWS" >/dev/null || die 'จำนวนแถวตารางไม่ถูกต้อง'
log "นับแถว $(jq 'length' <<<"$TABLE_ROWS") ตาราง"
TOKEN_TOTALS=$(sa_query "$(sql_file_line token-totals.sql)") || die 'นับยอดโทเคนไม่ได้'
jq -e 'type == "object" and has("balance_digest")' <<<"$TOKEN_TOTALS" >/dev/null || die 'ยอดโทเคนไม่ถูกต้อง'
log "ยอดโทเคน: $(jq -r '"\(.wallets) กระเป๋า รวม \(.balance_sum)"' <<<"$TOKEN_TOTALS")"

STEP=pg_dump
dump_args=(--snapshot="$SNAPSHOT" --schema=public --schema=private --format=custom --no-password)
"$PG_DUMP" "${dump_args[@]}" --schema-only --file="$WORK/run/schema.dump"
"$PG_DUMP" "${dump_args[@]}" --data-only \
  --exclude-table-data=private.backup_manifests --exclude-table-data=private.backup_run_files \
  --file="$WORK/run/data.dump"
sa_query 'commit; select 1;' >/dev/null || die 'commit session A ไม่ได้'
sa_in=${SA[1]}
exec {sa_in}>&-
wait "$SA_PID" || die 'session A จบไม่ปกติ'
SA_PID=''
log "dump: schema $(stat -c %s "$WORK/run/schema.dump") ไบต์, data $(stat -c %s "$WORK/run/data.dump") ไบต์"

# รายการเต็มของจุดกู้คืน (อัปโหลดคู่ dump) และไฟล์ใหม่ — เรียกก่อนจบรอบเพราะจบรอบล้างรายการ
STEP=manifest
sql "\\copy (select final_key, version_id, size_bytes, checksum from private.backup_run_file_list('$RUN_ID')) to '$WORK/run/manifest.csv' with (format csv, header)"
sql "\\copy (select f.final_key, f.version_id, f.size_bytes, f.checksum from private.backup_run_file_list('$RUN_ID') f join private.backup_new_files('$RUN_ID') n using (final_key)) to '$WORK/new.csv' with (format csv)"
[ "$(($(wc -l <"$WORK/run/manifest.csv") - 1))" = "$FILE_COUNT" ] || die 'จำนวนแถว manifest.csv ไม่ตรงกับที่บันทึก'
NEW_COUNT=$(wc -l <"$WORK/new.csv")
log "ไฟล์ใหม่ $NEW_COUNT ไฟล์"

# ---------------------------------------------------------------------------
# 5. ไฟล์ใหม่: อ่าน B2 ครั้งเดียวลงเครื่อง (ตามเวอร์ชันที่บันทึก) ตรวจกับ manifest → คัดลอกขึ้น Drive (เข้ารหัส)
# ---------------------------------------------------------------------------
STEP=copy_new
"${RCLONE[@]}" mkdir gcrypt:files
SKIP_COUNT=0
if [ "$NEW_COUNT" -gt 0 ]; then
  drive_listing
  not_in_drive "$WORK/new.csv" "$WORK/drive.tsv" >"$WORK/fetch.csv"
  SKIP_COUNT=$((NEW_COUNT - $(wc -l <"$WORK/fetch.csv")))
  [ "$SKIP_COUNT" = 0 ] || log "ไฟล์ใหม่ที่มีใน Drive แล้วขนาดตรง (จากรอบที่ล้ม) $SKIP_COUNT ไฟล์ → ไม่อ่าน B2"
fi
if [ -s "$WORK/fetch.csv" ]; then
  fetch_ok=1
  fetch_list "$WORK/fetch.csv" "$WORK/new" || fetch_ok=0
  record_usage
  [ "$fetch_ok" = 1 ] || die 'อ่านไฟล์ใหม่จาก B2 ไม่ครบหรือเนื้อไม่ตรง manifest'
  "${RCLONE[@]}" copy "$WORK/new" gcrypt: --no-traverse
  # 6. ตรวจเนื้อไฟล์ที่คัดลอกใหม่: ต้นทางเป็นสำเนาในเครื่อง ไม่อ่าน B2 ซ้ำ
  STEP=cryptcheck
  "${RCLONE[@]}" cryptcheck "$WORK/new" gcrypt: --one-way
fi

# ---------------------------------------------------------------------------
# 6. ความครบ: ทุกไฟล์ใน manifest ต้องอยู่ใน Drive ขนาดตรง — ไม่ครบให้ดึงตาม version_id มาแทน แล้วตรวจอีกครั้ง
# ---------------------------------------------------------------------------
STEP=verify
drive_listing
missing_or_mismatch "$WORK/run/manifest.csv" "$WORK/drive.tsv" >"$WORK/repair.keys"
REPAIR_COUNT=$(wc -l <"$WORK/repair.keys")
if [ "$REPAIR_COUNT" -gt 0 ]; then
  STEP=repair
  log "ไฟล์เดิมหาย/ขนาดไม่ตรงใน Drive $REPAIR_COUNT ไฟล์ → ดึงตาม version_id"
  awk -F, 'FILENAME == ARGV[1] { want[$1] = 1; next } FNR > 1 && ($1 in want)' \
    "$WORK/repair.keys" "$WORK/run/manifest.csv" >"$WORK/repair.csv"
  repair_ok=1
  fetch_list "$WORK/repair.csv" "$WORK/repair" || repair_ok=0
  record_usage
  [ "$repair_ok" = 1 ] || die 'ดึงไฟล์ที่ขาดจาก B2 ไม่ครบ'
  "${RCLONE[@]}" copy "$WORK/repair" gcrypt: --no-traverse
  "${RCLONE[@]}" cryptcheck "$WORK/repair" gcrypt: --one-way
  drive_listing
  missing_or_mismatch "$WORK/run/manifest.csv" "$WORK/drive.tsv" >"$WORK/repair.keys"
  [ ! -s "$WORK/repair.keys" ] || die "ไฟล์ใน Drive ยังไม่ครบ $(wc -l <"$WORK/repair.keys") ไฟล์"
fi
log "ความครบ: ไฟล์ใน manifest $FILE_COUNT ไฟล์อยู่ใน Drive ขนาดตรงทุกไฟล์"

# ---------------------------------------------------------------------------
# 7. อัปโหลด dump + manifest → จบรอบสำเร็จ (ยอดไม่ตรง = manifest_mismatch = ล้มเหลว) → ping สำเร็จ
# ---------------------------------------------------------------------------
STEP=upload_run
jq -n --arg run "$RUN_ID" --arg stamp "$STAMP" --arg snapshot "$SNAPSHOT" --argjson files "$FILE_COUNT" \
  --argjson bytes "$TOTAL_BYTES" --argjson new "$NEW_COUNT" --argjson server "$server_major" \
  --arg target "$TARGET" --argjson rows "$TABLE_ROWS" --argjson tokens "$TOKEN_TOTALS" \
  '{run_id: $run, stamp: $stamp, target: $target, snapshot: $snapshot, file_count: $files, total_bytes: $bytes,
    new_file_count: $new, server_major: $server, schemas: ["public", "private"],
    excluded_table_data: ["private.backup_manifests", "private.backup_run_files"],
    table_rows: $rows, token_totals: $tokens}' >"$WORK/run/meta.json"
RUN_UPLOADED=1
"${RCLONE[@]}" copy "$WORK/run" "gcrypt:runs/$STAMP"
"${RCLONE[@]}" cryptcheck "$WORK/run" "gcrypt:runs/$STAMP" --one-way

STEP=finish
detail="ไฟล์ใหม่ $NEW_COUNT (มีใน Drive แล้ว $SKIP_COUNT) · ดึงซ่อม $REPAIR_COUNT · อ่าน B2 $USAGE_REQUESTS คำขอ $USAGE_BYTES ไบต์"
sql "select private.backup_finish('$RUN_ID', true, '$STAMP', $FILE_COUNT, $TOTAL_BYTES, $NEW_COUNT, :'detail')" \
  -v detail="$detail" >/dev/null
FINISHED=1
log "สำเร็จ: $detail"
hc_ping '' "kemi-backup สำเร็จ runs/$STAMP · $detail"
SUCCESS_PINGED=1

# ---------------------------------------------------------------------------
# 8. ล้างของเก่าใน Drive (เฉพาะในโฟลเดอร์สำรอง ลบถาวร) — ผิดพลาดตรงนี้ไม่ทำให้รอบที่สำเร็จแล้วล้ม
#    แต่ workflow ล้ม (GitHub ส่งอีเมล) เพื่อไม่ให้ Drive เต็มเงียบ ๆ
# ---------------------------------------------------------------------------
STEP=prune
prune_failed=0
# จุดกู้คืนที่เก็บ: รอบสำเร็จใน 7 วัน + รอบสำเร็จล่าสุดเสมอ
sql "select dump_name from public.backup_runs where kind = 'backup' and status = 'succeeded' and dump_name is not null
       and (started_at > clock_timestamp() - interval '7 days'
            or id = (select id from public.backup_runs where kind = 'backup' and status = 'succeeded' order by started_at desc limit 1))" \
  >"$WORK/keep.txt"
"${RCLONE[@]}" lsf --dirs-only gcrypt:runs | tr -d '/' >"$WORK/runs.txt" || prune_failed=1
while IFS= read -r d; do
  stamp_ok "$d" || continue
  grep -qxF "$d" "$WORK/keep.txt" && continue
  log "ลบจุดกู้คืนเก่า runs/$d"
  "${RCLONE[@]}" purge "gcrypt:runs/$d" || prune_failed=1
done <"$WORK/runs.txt"

# ไฟล์ที่ไม่มีจุดกู้คืนใดอ้างแล้ว: ลบจาก Drive ก่อน แล้วยืนยันเฉพาะที่หายจาก Drive จริง (สองขั้นตาม 0013)
sql 'select final_key from private.backup_prune_candidates()' >"$WORK/prune.all"
: >"$WORK/prune.txt"
while IFS= read -r key; do
  if key_ok "$key"; then printf '%s\n' "$key" >>"$WORK/prune.txt"; else prune_failed=1; fi
done <"$WORK/prune.all"
if [ -s "$WORK/prune.txt" ]; then
  while IFS= read -r key; do
    "${RCLONE[@]}" deletefile "gcrypt:$key" 2>/dev/null || true # ไม่มีอยู่แล้วก็นับว่าลบแล้ว
  done <"$WORK/prune.txt"
  if drive_listing; then
    gone=$({ cut -f1 "$WORK/drive.tsv" | grep -vxFf - "$WORK/prune.txt" || true; } |
      jq -Rsc 'split("\n") | map(select(. != ""))')
    confirmed=$(sql "select private.backup_prune_confirm(array(select jsonb_array_elements_text(:'keys'::jsonb)))" -v keys="$gone")
    log "ล้างไฟล์ที่พ้นอายุ: ขอ $(wc -l <"$WORK/prune.txt") ยืนยัน $confirmed"
    [ "$confirmed" = "$(wc -l <"$WORK/prune.txt")" ] || prune_failed=1
  else
    prune_failed=1
  fi
fi

# 9. ปลดธง + ping() อยู่ใน on_exit
STEP=finished
[ "$prune_failed" = 0 ] || die 'ล้างของเก่าใน Drive ไม่ครบ (รอบสำรองสำเร็จแล้ว)'
log 'จบรอบ'
