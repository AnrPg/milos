#!/usr/bin/env sh
set -eu

BACKUP_ROOT="${BACKUP_ROOT:-/backups/postgres}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
MIN_FREE_PERCENT="${BACKUP_MIN_FREE_PERCENT:-15}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET="${BACKUP_ROOT}/${STAMP}"

mkdir -p "${BACKUP_ROOT}"

free_percent() {
  df -P "${BACKUP_ROOT}" | awk 'NR == 2 {gsub("%", "", $5); print 100 - $5}'
}

FREE="$(free_percent)"
if [ "${FREE}" -lt "${MIN_FREE_PERCENT}" ]; then
  echo "backup_aborted reason=low_disk_space free_percent=${FREE} min_free_percent=${MIN_FREE_PERCENT}" >&2
  exit 75
fi

pg_isready -h "${PGHOST:-postgres}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -d "${PGDATABASE:-milos_training_dev}"

pg_basebackup \
  -h "${PGHOST:-postgres}" \
  -p "${PGPORT:-5432}" \
  -U "${PGUSER:-postgres}" \
  -D "${TARGET}" \
  -Fp \
  -Xs \
  -P \
  --checkpoint=fast \
  --write-recovery-conf \
  --label="milos-${STAMP}"

pg_verifybackup "${TARGET}"
ln -sfn "${TARGET}" "${BACKUP_ROOT}/latest"

find "${BACKUP_ROOT}" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -mtime "+${RETENTION_DAYS}" \
  -exec rm -rf {} +

echo "backup_completed target=${TARGET} retention_days=${RETENTION_DAYS} free_percent=${FREE}"
