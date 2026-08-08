#!/usr/bin/env sh
set -eu

BACKUP_ROOT="${BACKUP_ROOT:-/backups/postgres}"
WAL_ARCHIVE="${WAL_ARCHIVE:-/wal-archive}"
LATEST="${BACKUP_ROOT}/latest"

if [ ! -d "${LATEST}" ]; then
  echo "restore_drill_failed reason=missing_latest_backup path=${LATEST}" >&2
  exit 66
fi

pg_verifybackup "${LATEST}"

if [ ! -f "${LATEST}/backup_manifest" ]; then
  echo "restore_drill_failed reason=missing_backup_manifest path=${LATEST}" >&2
  exit 66
fi

if [ ! -d "${WAL_ARCHIVE}" ]; then
  echo "restore_drill_failed reason=missing_wal_archive path=${WAL_ARCHIVE}" >&2
  exit 66
fi

if ! find "${WAL_ARCHIVE}" -type f | grep -q .; then
  echo "restore_drill_failed reason=empty_wal_archive path=${WAL_ARCHIVE}" >&2
  exit 66
fi

echo "restore_drill_ok backup=${LATEST} wal_archive=${WAL_ARCHIVE}"
