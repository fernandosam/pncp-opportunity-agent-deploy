#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fixture/scripts" "$tmp/fixture/backups" "$tmp/bin"
cp "$root"/scripts/check-{backup-health,stack-readonly,app-local}.sh "$tmp/fixture/scripts/"
for script in "$root"/scripts/check-{backup-health,stack-readonly,app-local}.sh; do bash -n "$script"; done
# GitHub Contents API creates files with mode 0644; execute copies explicitly.
chmod +x "$tmp/fixture/scripts/"*.sh
printf '%s\n' '// smoke input fixture' > "$tmp/fixture/scripts/smoke.mjs"
check_backup="$tmp/fixture/scripts/check-backup-health.sh"
check_stack="$tmp/fixture/scripts/check-stack-readonly.sh"
check_app="$tmp/fixture/scripts/check-app-local.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
expect_pass() { "$@" >/dev/null || fail "expected pass: $*"; }
expect_fail() { if "$@" >/dev/null 2>&1; then fail "expected rejection: $*"; fi; }

expect_fail "$check_backup"
file="$tmp/fixture/backups/pncp-20261028T030000Z-abc.dump.age"
printf 'encrypted mock, not a real archive\n' > "$file"
chmod 600 "$file"
expect_pass "$check_backup"
chmod 644 "$file"
expect_fail "$check_backup"
chmod 600 "$file"
touch -d '2 days ago' "$file"
expect_fail "$check_backup"
touch "$file"
expect_fail env BACKUP_MAX_AGE_HOURS=0 "$check_backup"
expect_pass env BACKUP_MAX_AGE_HOURS=36 "$check_backup"
touch -d '8 days ago' "$file"
expect_fail env BACKUP_MAX_AGE_HOURS=168 "$check_backup"
touch "$file"

cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_TRACE"
case "$*" in
 'compose config --quiet') [[ ${DOCKER_INVALID_CONFIG:-0} != 1 ]] ;;
 'compose ps -q database') printf 'db123\n' ;;
 'compose ps -q web') printf 'web123\n' ;;
 'compose ps -a -q worker') [[ ${DOCKER_WORKER_RUNNING:-0} == 1 ]] && printf 'worker123\n' || : ;;
 'inspect --format {{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}} db123') printf '%s\n' "${DOCKER_DB_HEALTH:-healthy}" ;;
 'inspect --format {{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}} web123') printf 'healthy\n' ;;
 'inspect --format {{.State.Running}} worker123') printf 'true\n' ;;
 'compose exec -T web node --input-type=module') cat >/dev/null; [[ ${DOCKER_SMOKE_FAIL:-0} != 1 ]] ;;
 *) echo "unexpected docker command: $*" >&2; exit 99 ;;
esac
DOCKER
chmod 755 "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" DOCKER_TRACE="$tmp/trace"
expect_pass "$check_stack"
if grep -E '^compose (up|run|build|restart|stop|down)( |$)' "$tmp/trace" >/dev/null; then fail 'Forbidden side-effect command invoked'; fi
expect_fail env DOCKER_WORKER_RUNNING=1 "$check_stack"
expect_fail env DOCKER_DB_HEALTH=unhealthy "$check_stack"
expect_fail env DOCKER_INVALID_CONFIG=1 "$check_stack"
expect_fail env DOCKER_SMOKE_FAIL=1 "$check_stack"
# The dedicated quality-runner contract suite covers sanitized CI env, SHA and failures.
bash "$root/tests/check-app-local.test.sh"
echo 'PASS: backup health (missing, recent, stale, insecure, expired and invalid threshold); stack pre-activation (healthy, worker active, DB unhealthy, invalid config, smoke failure); no worker activation.'
