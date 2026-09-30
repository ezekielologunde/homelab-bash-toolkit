# homelab-bash-toolkit

Four small, focused Bash health-check scripts, shellcheck-clean and run in
CI against synthetic fixtures (not a live system) so anyone can verify the
tests actually mean something without needing access to real infrastructure.

## What this is

Practical Bash scripting for the kind of checks a small homelab or a
single-host environment actually needs day to day: is a log rotating, is
disk/load in a sane range, did the backup produce a real archive (not just
a file that exists), is log forwarding to a SIEM actually reachable. Each
script follows a Nagios-style exit-code convention (0 ok, 1 warning, 2
critical) so it composes with any monitoring system that understands that
convention, or can be run standalone from cron.

## What this is not

Not a claim of a broader DevOps/SRE tooling platform - four scripts, each
doing one clearly scoped thing, nothing more.

## Scripts

| Script | Checks |
|---|---|
| `disk-load-report.sh` | Disk usage % and 1-minute load average (as a multiple of core count) against configurable warn/critical thresholds |
| `log-rotation-check.sh` | A log file above a size threshold has a recently-rotated sibling - catches "logrotate is configured but silently stopped working," not just "is logrotate installed" |
| `backup-verify.sh` | A backup archive exists, isn't stale, isn't implausibly small, and actually passes its own tar/gzip integrity check - a backup job can "succeed" and still produce a truncated file |
| `syslog-forward-health.sh` | The local syslog daemon is active, and (if a target is given) that the remote SIEM's syslog port is actually reachable over TCP |

Every script supports `--help` and documents its environment-variable
overrides there; none require root or any specific distro beyond a
reasonably standard `coreutils`/`bash` environment.

## Testing approach

`tests/smoke-test.sh` builds synthetic fixtures in a `mktemp -d` throwaway
directory (fake log files, a real valid `tar.gz`, a deliberately corrupted
one, a backdated file) and asserts each script's exit code and, where the
result legitimately depends on host state (e.g. whether rsyslog happens to
be active on the machine running the test), asserts on the specific output
line the script controls instead of the exit code alone.

CI (`.github/workflows/ci.yml`) runs `shellcheck` first, then the smoke
tests, on every push - both visible in the repo's own Actions history.

One real bug the tests caught during development: an early version of
`disk-load-report.sh` parsed `df -P`'s output by fixed column position
(`$5`), which breaks the moment a filesystem name contains a space (for
example a mount whose device path is `C:/Program Files/Git`, which
splits into extra fields). Fixed by indexing from the end
(`$(NF-1)`), which stays correct however many fields the filesystem-name
column expands into. Left as an authentic example of what the smoke tests
are actually for, not cleaned out of the commit history.

## Running locally

```bash
shellcheck scripts/*.sh tests/*.sh
bash tests/smoke-test.sh
```
