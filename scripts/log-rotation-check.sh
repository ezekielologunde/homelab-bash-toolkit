#!/usr/bin/env bash
# Checks that a log file is being rotated: flags any file above a size
# threshold with no rotated sibling (name.1, name.1.gz, etc.) newer than a
# configurable max age. Meant to catch "logrotate is configured but silently
# stopped working" rather than duplicate logrotate's own job.
set -euo pipefail

MAX_SIZE_MB="${MAX_SIZE_MB:-100}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-8}"

usage() {
  cat <<'EOF'
Usage: log-rotation-check.sh LOG_FILE [LOG_FILE ...]

Environment overrides:
  MAX_SIZE_MB   size (MB) above which a log file must have a recent rotated
                sibling, or this reports a warning (default 100)
  MAX_AGE_DAYS  maximum age, in days, allowed for the newest rotated sibling
                before it's considered stale (default 8, i.e. weekly rotation
                plus a day of slack)

Exit codes: 0 ok, 1 warning (at least one file flagged), 3 usage error.
EOF
}

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  [ $# -eq 0 ] && exit 3
  exit 0
fi

status=0

for log_file in "$@"; do
  if [ ! -f "$log_file" ]; then
    echo "WARNING: $log_file does not exist"
    status=1
    continue
  fi

  size_mb=$(du -m "$log_file" | cut -f1)
  if [ "$size_mb" -lt "$MAX_SIZE_MB" ]; then
    echo "OK: $log_file is ${size_mb}MB, below the ${MAX_SIZE_MB}MB rotation-check threshold"
    continue
  fi

  newest_sibling=$(find "$(dirname "$log_file")" -maxdepth 1 \
    -name "$(basename "$log_file").*" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2- || true)

  if [ -z "$newest_sibling" ]; then
    echo "WARNING: $log_file is ${size_mb}MB (>= ${MAX_SIZE_MB}MB) with no rotated sibling found - rotation may not be configured"
    status=1
    continue
  fi

  age_days=$(( ( $(date +%s) - $(stat -c %Y "$newest_sibling") ) / 86400 ))
  if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
    echo "WARNING: $log_file is ${size_mb}MB and its newest rotated sibling ($newest_sibling) is ${age_days} days old (> ${MAX_AGE_DAYS}) - rotation may have stopped running"
    status=1
  else
    echo "OK: $log_file is ${size_mb}MB, rotated sibling $newest_sibling is ${age_days} day(s) old"
  fi
done

exit "$status"
