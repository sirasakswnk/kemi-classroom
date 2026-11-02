#!/usr/bin/env bash
# ทดสอบ ops/backup.sh ในเครื่อง: unit + shellcheck + ครบรอบใน container (ไม่แตะบริการจริง)
# ต้องเปิด Docker Desktop และ Supabase ในเครื่อง (npm run db:start; แนะนำ npm run db:reset ก่อน เพราะ e2e เขียนข้อมูลสมมติ)
# รันจาก root ของ repo: bash ops/backup-test/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && (pwd -W 2>/dev/null || pwd))
bash "$here/unit.sh"
bash "$here/restore-unit.sh"
bash "$here/record-unit.sh"
MSYS_NO_PATHCONV=1 docker run --rm -w /mnt -v "$root:/mnt:ro" koalaman/shellcheck:stable -x \
  /mnt/ops/backup.sh /mnt/ops/backup-test/unit.sh /mnt/ops/backup-test/e2e.sh /mnt/ops/backup-test/fake-aws /mnt/ops/backup-test/run.sh \
  /mnt/ops/restore-test.sh /mnt/ops/backup-test/restore-unit.sh /mnt/ops/backup-test/restore-e2e.sh \
  /mnt/ops/restore-record.sh /mnt/ops/backup-test/record-unit.sh
echo 'shellcheck: ผ่าน'
MSYS_NO_PATHCONV=1 docker run --rm -v "$root:/repo:ro" --add-host=host.docker.internal:host-gateway \
  postgres:17 bash /repo/ops/backup-test/e2e.sh
# ล้าง public/private ของ Supabase ในเครื่อง — จบแล้วรัน npm run db:reset
MSYS_NO_PATHCONV=1 docker run --rm -v "$root:/repo:ro" --add-host=host.docker.internal:host-gateway \
  postgres:17 bash /repo/ops/backup-test/restore-e2e.sh
