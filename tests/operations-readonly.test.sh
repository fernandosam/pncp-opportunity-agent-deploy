#!/usr/bin/env bash
# Executable offline tests with real OpenSSL certificates and a mocked Docker client.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fixture/scripts" "$tmp/fixture/backups" "$tmp/fixture/.secrets" "$tmp/bin"
cp "$root/scripts/check-operations-readonly.sh" "$root/scripts/check-backup-health.sh" "$tmp/fixture/scripts/"
bash -n "$tmp/fixture/scripts/check-operations-readonly.sh"
chmod 700 "$tmp/fixture/.secrets"
backup="$tmp/fixture/backups/pncp-test.dump.age"
printf 'synthetic nonempty file (not a valid age archive)\n' > "$backup"
chmod 600 "$backup"

cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
case "$*" in
  'compose --profile backups config --quiet') [[ ${MOCK_INVALID_COMPOSE:-0} == 0 ]] ;;
  'compose --profile backups ps -q backup-scheduler') [[ ${MOCK_MISSING_SCHEDULER:-0} == 0 ]] && printf 'scheduler123\n' || : ;;
  'inspect --format {{.State.Running}} scheduler123') [[ ${MOCK_DOCKER_ERROR:-0} == 0 ]] || exit 4; printf '%s\n' "${MOCK_RUNNING:-true}" ;;
  *) printf 'Unexpected Docker action\n' >&2; exit 99 ;;
esac
DOCKER
chmod +x "$tmp/bin/docker"
export MOCK_DOCKER_LOG="$tmp/docker.log" PATH="$tmp/bin:$PATH"
check="$tmp/fixture/scripts/check-operations-readonly.sh"
cert="$tmp/fixture/.secrets/database.crt"
key="$tmp/fixture/.secrets/database.key"
certify() {
  local days=$1 hostname=$2
  openssl req -x509 -newkey rsa:2048 -nodes -days "$days" -sha256 -subj "/CN=$hostname" \
     -addext "subjectAltName=DNS:$hostname" -addext 'basicConstraints=critical,CA:TRUE' \
     -keyout "$key" -out "$cert" >/dev/null 2>&1
  chmod 600 "$key"
}
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { bash "$check" > "$tmp/output" || { cat "$tmp/output"; fail 'Expected health pass'; }; }
reject() { if bash "$check" > "$tmp/output" 2>&1; then fail 'Expected fail-closed health check'; fi; }
certify 90 database
pass
[[ $(wc -l < "$tmp/docker.log") == 3 ]] || fail 'Unexpected Docker calls'
! grep -Eq '^compose (up|run|start|build|restart|logs|rm|down)( |$)' "$tmp/docker.log" || fail 'Side effect or unsafe log read'
certify 3 database
reject
certify 90 wrong-host
reject
certify 90 database
chmod 644 "$key"
reject
chmod 600 "$key"
chmod 755 "$tmp/fixture/.secrets"
reject
chmod 700 "$tmp/fixture/.secrets"
MOCK_MISSING_SCHEDULER=1 reject
MOCK_RUNNING=false reject
MOCK_INVALID_COMPOSE=1 reject
MOCK_DOCKER_ERROR=1 reject
touch -d '3 days ago' "$backup"
reject
touch "$backup"
chmod 644 "$backup"
reject
chmod 600 "$backup"
touch -d '8 days ago' "$backup"
reject
touch "$backup"
pass
printf '%s\n' 'PASS: valid operations check, expiring/invalid TLS, key permissions, scheduler stopped/missing, invalid Compose, Docker error, stale/insecure/expired backups, no service startup.'
