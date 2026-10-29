#!/usr/bin/env bash
# Offline safety tests. Neither Docker nor a real decryption identity is used.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/deploy/scripts" "$tmp/deploy/.secrets" "$tmp/bin"
cp "$root/scripts/restore-isolated.sh" "$tmp/deploy/scripts/"
file="$tmp/example.dump.age"; identity="$tmp/identity"
printf '%s\n' 'opaque encrypted archive fixture' > "$file"
printf '%s\n' 'synthetic identity only' > "$identity"
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == compose\ -p\ pncp-restore-fixture* ]] || { echo 'Non-isolated project!' >&2; exit 99; }
if [[ "$*" == *'backup -o pipefail -c '* ]]; then
 echo PREFLIGHT >> "$MOCK_LOG"
 [[ "$*" == *'read -r -N 5 magic'* && "$*" == *'[[ "$magic" == PGDMP ]]'* && "$*" == *'cat >/dev/null'* ]] || exit 97
 [[ ${MOCK_PREFLIGHT_FAIL:-0} == 0 ]] || exit 11
elif [[ "$*" == *' up -d --wait database' ]]; then
 echo START >> "$MOCK_LOG"
elif [[ "$*" == *' -Atc select count('* ]]; then
 echo PRECHECK >> "$MOCK_LOG"
 printf '%s\n' "${MOCK_TARGET_COUNT:-0}"
elif [[ "$*" == *'backup --decrypt --identity'* ]]; then
 echo DECRYPT >> "$MOCK_LOG"
 [[ ${MOCK_AGE_FAIL:-0} == 0 ]] || exit 11
 printf '%s\n' 'mock pg archive stream'
elif [[ "$*" == *'pg_restore --username pncp_admin'* ]]; then
 echo RESTORE >> "$MOCK_LOG"
 cat > /dev/null
 [[ ${MOCK_RESTORE_FAIL:-0} == 0 ]] || exit 12
elif [[ "$*" == *'run --rm migrate' ]]; then
 echo MIGRATE >> "$MOCK_LOG"
elif [[ "$*" == *'psql -v ON_ERROR_STOP=1'* ]]; then
 echo POSTFLIGHT >> "$MOCK_LOG"
 printf '%s\n' "${MOCK_POSTFLIGHT:-ok}"
else
 echo "Unexpected Docker command" >&2; exit 98
fi
DOCKER
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" MOCK_LOG="$tmp/log"
fail() { echo "FAIL: $1" >&2; exit 1; }
expect_fail() { if "$@" >/dev/null 2>&1; then fail "Expected failure: $*"; fi; }
expect_pass() { "$@" >/dev/null || fail "Expected pass: $*"; }
script="$tmp/deploy/scripts/restore-isolated.sh"
expect_fail bash "$script" prod "$file" "$identity"
[[ ! -s "$tmp/log" ]] || fail 'Wrong project accessed Docker'
expect_fail bash "$script" pncp-restore-fixture missing.age "$identity"
[[ ! -s "$tmp/log" ]] || fail 'Missing backup accessed Docker'
expect_fail bash "$script" pncp-restore-fixture "$file" missing.identity
[[ ! -s "$tmp/log" ]] || fail 'Missing identity accessed Docker'
: > "$tmp/log"
expect_fail env MOCK_PREFLIGHT_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
[[ $(cat "$tmp/log") == PREFLIGHT ]] || fail 'Failed age identity must not create an isolated DB'
: > "$tmp/log"
expect_fail env MOCK_TARGET_COUNT=2 bash "$script" pncp-restore-fixture "$file" "$identity"
[[ $(cat "$tmp/log") == 
: > "$tmp/log"
expect_fail env MOCK_AGE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed decrypt'
: > "$tmp/log"
expect_fail env MOCK_RESTORE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed pg_restore'
: > "$tmp/log"
expect_fail env MOCK_POSTFLIGHT=fail bash "$script" pncp-restore-fixture "$file" "$identity"
grep -q '^POSTFLIGHT$' "$tmp/log" || fail 'Postflight was skipped'
: > "$tmp/log"
expect_pass bash "$script" pncp-restore-fixture "$file" "$identity"
for step in PREFLIGHT START PRECHECK DECRYPT RESTORE MIGRATE POSTFLIGHT; do
  [[ $(grep -cx "$step" "$tmp/log") == 1 ]] || fail "Missing or duplicate $step"
done
[[ $(head -n 3 "$tmp/log") == 
[[ $(tail -n 2 "$tmp/log") == $'MIGRATE\nPOSTFLIGHT' ]] || fail 'Migration/postflight out of order'
printf '%s\n' 'PASS: isolated restore rejects wrong identity before starting DB, refuses occupied target, stops after decrypt/pg_restore failure, and requires RLS postflight.'
PREFLIGHT\nSTART\nPRECHECK' ]] || fail 'Occupied target was written to'
: > "$tmp/log"
expect_fail env MOCK_AGE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed decrypt'
: > "$tmp/log"
expect_fail env MOCK_RESTORE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed pg_restore'
: > "$tmp/log"
expect_fail env MOCK_POSTFLIGHT=fail bash "$script" pncp-restore-fixture "$file" "$identity"
grep -q '^POSTFLIGHT$' "$tmp/log" || fail 'Postflight was skipped'
: > "$tmp/log"
expect_pass bash "$script" pncp-restore-fixture "$file" "$identity"
for step in START PRECHECK DECRYPT RESTORE MIGRATE POSTFLIGHT; do
  [[ $(grep -cx "$step" "$tmp/log") == 1 ]] || fail "Missing or duplicate $step"
done
[[ $(head -n 2 "$tmp/log") == $'START\nPRECHECK' ]] || fail 'Missing preflight'
[[ $(tail -n 2 "$tmp/log") == $'MIGRATE\nPOSTFLIGHT' ]] || fail 'Migration/postflight out of order'
printf '%s\n' 'PASS: isolated restore rejects invalid/missing sources and occupied targets, stops after decrypt/pg_restore failure, and requires RLS postflight.'
PREFLIGHT\nSTART\nPRECHECK' ]] || fail 'Identity preflight must precede DB creation'
[[ $(tail -n 2 "$tmp/log") == $'MIGRATE\nPOSTFLIGHT' ]] || fail 'Migration/postflight out of order'
printf '%s\n' 'PASS: isolated restore rejects invalid/missing sources and occupied targets, stops after decrypt/pg_restore failure, and requires RLS postflight.'
PREFLIGHT\nSTART\nPRECHECK' ]] || fail 'Occupied target was written to'
: > "$tmp/log"
expect_fail env MOCK_AGE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed decrypt'
: > "$tmp/log"
expect_fail env MOCK_RESTORE_FAIL=1 bash "$script" pncp-restore-fixture "$file" "$identity"
! grep -q '^MIGRATE$' "$tmp/log" || fail 'Migration after failed pg_restore'
: > "$tmp/log"
expect_fail env MOCK_POSTFLIGHT=fail bash "$script" pncp-restore-fixture "$file" "$identity"
grep -q '^POSTFLIGHT$' "$tmp/log" || fail 'Postflight was skipped'
: > "$tmp/log"
expect_pass bash "$script" pncp-restore-fixture "$file" "$identity"
for step in START PRECHECK DECRYPT RESTORE MIGRATE POSTFLIGHT; do
  [[ $(grep -cx "$step" "$tmp/log") == 1 ]] || fail "Missing or duplicate $step"
done
[[ $(head -n 2 "$tmp/log") == $'START\nPRECHECK' ]] || fail 'Missing preflight'
[[ $(tail -n 2 "$tmp/log") == $'MIGRATE\nPOSTFLIGHT' ]] || fail 'Migration/postflight out of order'
printf '%s\n' 'PASS: isolated restore rejects invalid/missing sources and occupied targets, stops after decrypt/pg_restore failure, and requires RLS postflight.'
