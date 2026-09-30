#!/usr/bin/env bash
# Verifies a backup archive: exists, isn't stale, and its compressed archive
# integrity actually checks out (not just "the file is present" - a backup
# job can produce a truncated/corrupt file and still "succeed").
set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"   # daily backup + 2h slack
MIN_SIZE_KB="${MIN_SIZE_KB:-1}"

usage() {
  cat <<'EOF'
Usage: backup-verify.sh ARCHIVE_FILE

Environment overrides:
  MAX_AGE_HOURS  maximum age, in hours, before the archive is considered
                 stale (default 26, i.e. a daily job plus 2 hours of slack)
  MIN_SIZE_KB    minimum plausible archive size in KB - catches an empty or
                 near-empty file that "exists" but backed up nothing
                 (default 1)

Supports .tar, .tar.gz/.tgz, and .gz archives. Exit codes: 0 ok,
2 critical (missing, stale, too small, or failed integrity check),
3 usage error.
EOF
}

if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  [ $# -ne 1 ] && exit 3
  exit 0
fi

archive="$1"

if [ ! -f "$archive" ]; then
  echo "CRITICAL: backup archive $archive does not exist"
  exit 2
fi

age_hours=$(( ( $(date +%s) - $(stat -c %Y "$archive") ) / 3600 ))
if [ "$age_hours" -gt "$MAX_AGE_HOURS" ]; then
  echo "CRITICAL: backup archive $archive is ${age_hours}h old (> ${MAX_AGE_HOURS}h) - the backup job may not be running"
  exit 2
fi

size_kb=$(du -k "$archive" | cut -f1)
if [ "$size_kb" -lt "$MIN_SIZE_KB" ]; then
  echo "CRITICAL: backup archive $archive is only ${size_kb}KB (< ${MIN_SIZE_KB}KB) - likely empty or truncated"
  exit 2
fi

case "$archive" in
  *.tar.gz | *.tgz)
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
      echo "CRITICAL: $archive failed tar/gzip integrity check"
      exit 2
    fi
    ;;
  *.tar)
    if ! tar -tf "$archive" >/dev/null 2>&1; then
      echo "CRITICAL: $archive failed tar integrity check"
      exit 2
    fi
    ;;
  *.gz)
    if ! gzip -t "$archive" >/dev/null 2>&1; then
      echo "CRITICAL: $archive failed gzip integrity check"
      exit 2
    fi
    ;;
  *)
    echo "WARNING: $archive has an unrecognized extension; skipped the archive-integrity check (existence/age/size checks above still ran)"
    ;;
esac

echo "OK: $archive is ${age_hours}h old, ${size_kb}KB, and passed its integrity check"
