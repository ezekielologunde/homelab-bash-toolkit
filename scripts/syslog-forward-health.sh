#!/usr/bin/env bash
# Checks that rsyslog (or syslog-ng) is running and that a configured
# remote syslog forwarding target is actually reachable on its port - the
# two failure modes a naive "is rsyslog running?" check would miss.
set -euo pipefail

TARGET="${SYSLOG_TARGET:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3}"

usage() {
  cat <<'EOF'
Usage: syslog-forward-health.sh [--target HOST:PORT]

Environment overrides:
  SYSLOG_TARGET     host:port of the remote syslog collector to test
                     reachability against (TCP). If unset and --target is
                     not given, only the local service-running check runs.
  TIMEOUT_SECONDS   connect timeout for the reachability check (default 3)

Exit codes: 0 ok, 1 warning (service down or target unreachable),
3 usage error.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="$2"
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

service_up=0
for svc in rsyslog syslog-ng; do
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "OK: $svc is active"
    service_up=1
    break
  fi
done

if [ "$service_up" -eq 0 ]; then
  echo "WARNING: neither rsyslog nor syslog-ng reports as active via systemctl"
  status=1
fi

if [ -z "$TARGET" ]; then
  echo "OK: no SYSLOG_TARGET/--target given, skipped remote reachability check"
  exit "$status"
fi

host="${TARGET%%:*}"
port="${TARGET##*:}"

if [ "$host" = "$TARGET" ] || [ "$port" = "$TARGET" ]; then
  echo "Invalid target '$TARGET', expected HOST:PORT" >&2
  exit 3
fi

if timeout "$TIMEOUT_SECONDS" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
  echo "OK: $host:$port is reachable (TCP)"
else
  echo "WARNING: $host:$port is not reachable within ${TIMEOUT_SECONDS}s - log forwarding to this target may be silently failing"
  status=1
fi

exit "$status"
