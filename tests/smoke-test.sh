#!/usr/bin/env bash
# Exercises each script against synthetic fixtures in a throwaway temp dir -
# no real system state required, safe to run anywhere including CI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

fail_count=0

expect() {
  local desc="$1"
  local expected_code="$2"
  shift 2
  local actual_code=0
  "$@" >/tmp/smoke-test-out.$$ 2>&1 || actual_code=$?
  if [ "$actual_code" -eq "$expected_code" ]; then
    echo "PASS: $desc (exit $actual_code)"
  else
    echo "FAIL: $desc (expected exit $expected_code, got $actual_code)"
    sed 's/^/    /' /tmp/smoke-test-out.$$
    fail_count=$((fail_count + 1))
  fi
  rm -f /tmp/smoke-test-out.$$
}

echo "== --help on every script =="
for script in "$SCRIPT_DIR"/*.sh; do
  expect "$(basename "$script") --help" 0 "$script" --help
done

echo "== disk-load-report.sh =="
expect "disk-load-report.sh against / with a trivially low threshold" 2 \
  env DISK_WARN_PCT=0 DISK_CRIT_PCT=0 "$SCRIPT_DIR/disk-load-report.sh"
expect "disk-load-report.sh against / with an unreachable-high threshold" 0 \
  env DISK_WARN_PCT=100 DISK_CRIT_PCT=100 LOAD_WARN_MULT=1000 LOAD_CRIT_MULT=1000 "$SCRIPT_DIR/disk-load-report.sh"

echo "== log-rotation-check.sh =="
mkdir -p "$WORKDIR/logs"
touch "$WORKDIR/logs/no-rotation.log"
dd if=/dev/zero of="$WORKDIR/logs/no-rotation.log" bs=1M count=1 status=none
expect "flags a large log with no rotated sibling" 1 \
  env MAX_SIZE_MB=0 "$SCRIPT_DIR/log-rotation-check.sh" "$WORKDIR/logs/no-rotation.log"

touch "$WORKDIR/logs/rotated.log" "$WORKDIR/logs/rotated.log.1"
dd if=/dev/zero of="$WORKDIR/logs/rotated.log" bs=1M count=1 status=none
expect "passes a large log with a fresh rotated sibling" 0 \
  env MAX_SIZE_MB=0 MAX_AGE_DAYS=365 "$SCRIPT_DIR/log-rotation-check.sh" "$WORKDIR/logs/rotated.log"

expect "flags a missing log file" 1 \
  "$SCRIPT_DIR/log-rotation-check.sh" "$WORKDIR/logs/does-not-exist.log"

echo "== backup-verify.sh =="
tar -czf "$WORKDIR/good.tar.gz" -C "$WORKDIR" logs
expect "passes a fresh, valid tar.gz" 0 \
  env MIN_SIZE_KB=0 "$SCRIPT_DIR/backup-verify.sh" "$WORKDIR/good.tar.gz"

echo "not a real archive" > "$WORKDIR/bad.tar.gz"
expect "fails a corrupt tar.gz" 2 \
  env MIN_SIZE_KB=0 "$SCRIPT_DIR/backup-verify.sh" "$WORKDIR/bad.tar.gz"

touch -d '3 days ago' "$WORKDIR/good.tar.gz" 2>/dev/null || touch -t "$(date -d '3 days ago' +%Y%m%d%H%M)" "$WORKDIR/good.tar.gz"
expect "fails a stale (3-day-old) archive against a 26h max age" 2 \
  env MIN_SIZE_KB=0 "$SCRIPT_DIR/backup-verify.sh" "$WORKDIR/good.tar.gz"

expect "fails a missing archive" 2 \
  "$SCRIPT_DIR/backup-verify.sh" "$WORKDIR/does-not-exist.tar.gz"

echo "== syslog-forward-health.sh =="
# The systemctl-based service check legitimately depends on the host's
# service state (a minimal CI runner has neither rsyslog nor syslog-ng
# active), so these assertions only check the part under the script's own
# control: reachability detection. tolerate() accepts either 0 (service
# check happened to pass on this host) or 1 (it didn't) as long as the
# expected reachability line is present in the output.
tolerate_with_marker() {
  local desc="$1" marker="$2"
  shift 2
  local code=0
  "$@" >/tmp/smoke-test-out.$$ 2>&1 || code=$?
  if { [ "$code" -eq 0 ] || [ "$code" -eq 1 ]; } && grep -q "$marker" /tmp/smoke-test-out.$$; then
    echo "PASS: $desc (exit $code, found '$marker')"
  else
    echo "FAIL: $desc (exit $code, expected to find '$marker')"
    sed 's/^/    /' /tmp/smoke-test-out.$$
    fail_count=$((fail_count + 1))
  fi
  rm -f /tmp/smoke-test-out.$$
}

python3 -m http.server 18999 --bind 127.0.0.1 >/dev/null 2>&1 &
http_pid=$!
sleep 1
tolerate_with_marker "detects a reachable target" "is reachable" \
  "$SCRIPT_DIR/syslog-forward-health.sh" --target 127.0.0.1:18999
kill "$http_pid" 2>/dev/null || true

tolerate_with_marker "detects an unreachable target" "not reachable" \
  env TIMEOUT_SECONDS=1 "$SCRIPT_DIR/syslog-forward-health.sh" --target 127.0.0.1:1
tolerate_with_marker "runs with no target given" "skipped remote reachability check" \
  "$SCRIPT_DIR/syslog-forward-health.sh"

echo
if [ "$fail_count" -eq 0 ]; then
  echo "All smoke tests passed."
  exit 0
else
  echo "$fail_count smoke test(s) failed."
  exit 1
fi
