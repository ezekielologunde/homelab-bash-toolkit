#!/usr/bin/env bash
# Reports disk usage and system load average; exits non-zero (Nagios-style:
# 0 ok, 1 warning, 2 critical) if either crosses a configurable threshold.
set -euo pipefail

DISK_WARN_PCT="${DISK_WARN_PCT:-80}"
DISK_CRIT_PCT="${DISK_CRIT_PCT:-90}"
LOAD_WARN_MULT="${LOAD_WARN_MULT:-1.0}"   # multiple of nproc
LOAD_CRIT_MULT="${LOAD_CRIT_MULT:-2.0}"
CHECK_PATH="${CHECK_PATH:-/}"

usage() {
  cat <<'EOF'
Usage: disk-load-report.sh [--path DIR]

Environment overrides:
  DISK_WARN_PCT   disk-use-percent warning threshold (default 80)
  DISK_CRIT_PCT   disk-use-percent critical threshold (default 90)
  LOAD_WARN_MULT  1-min load average warning, as a multiple of nproc (default 1.0)
  LOAD_CRIT_MULT  1-min load average critical, as a multiple of nproc (default 2.0)
  CHECK_PATH      filesystem path to check disk usage for (default /)

Exit codes: 0 ok, 1 warning, 2 critical, 3 usage error.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --path)
      CHECK_PATH="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 3
      ;;
  esac
done

status=0

disk_pct=$(df -P "$CHECK_PATH" | awk 'NR==2 {gsub("%","",$(NF-1)); print $(NF-1)}')
if [ -z "$disk_pct" ]; then
  echo "CRITICAL: could not read disk usage for $CHECK_PATH" >&2
  exit 2
fi

if [ "$disk_pct" -ge "$DISK_CRIT_PCT" ]; then
  echo "CRITICAL: disk usage on $CHECK_PATH is ${disk_pct}% (>= ${DISK_CRIT_PCT}%)"
  status=2
elif [ "$disk_pct" -ge "$DISK_WARN_PCT" ]; then
  echo "WARNING: disk usage on $CHECK_PATH is ${disk_pct}% (>= ${DISK_WARN_PCT}%)"
  [ "$status" -lt 1 ] && status=1
else
  echo "OK: disk usage on $CHECK_PATH is ${disk_pct}%"
fi

load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || uptime | awk -F'load average: ' '{print $2}' | cut -d',' -f1)
cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

load_crit=$(awk -v c="$cores" -v m="$LOAD_CRIT_MULT" 'BEGIN { printf "%.2f", c * m }')
load_warn=$(awk -v c="$cores" -v m="$LOAD_WARN_MULT" 'BEGIN { printf "%.2f", c * m }')

if awk -v l="$load1" -v t="$load_crit" 'BEGIN { exit !(l >= t) }'; then
  echo "CRITICAL: 1-min load average is $load1 (>= $load_crit across $cores cores)"
  status=2
elif awk -v l="$load1" -v t="$load_warn" 'BEGIN { exit !(l >= t) }'; then
  echo "WARNING: 1-min load average is $load1 (>= $load_warn across $cores cores)"
  [ "$status" -lt 1 ] && status=1
else
  echo "OK: 1-min load average is $load1 across $cores cores"
fi

exit "$status"
