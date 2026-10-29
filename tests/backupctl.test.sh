#!/usr/bin/env bash
# Offline contract: no real DB, provider or Docker volume is used.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fixture/scripts" "$tmp/fixture/backups" "$tmp/bin"
cp "$root/backupctl" "$tmp/fixture/backupctl"
chmod +x "$tmp/fixture/backupctl"
bash -n "$tmp/fixture/backupctl"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { "$@" >"$tmp/stdout" 2>"$tmp/stderr" || { cat "$tmp/stderr"; fail 'Expected command to pass'; }; }
reject() { if "$@" >"$tmp/stdout" 2>"$tmp/stderr"; then fail 'Expected command to reject'; fi; }
cat > "$tmp/fixture/scripts/check-operations-readonly.sh" <<'CHECK'
#!/usr/bin/env bash
printf 'checked-status\n' >> "$TRACE"
CHECK
cat > "$tmp/fixture/scripts/backup.sh" <<'BACKUP'
#!/usr/bin/env bash
printf 'made-backup\n' >> "$TRACE"
BACKUP
cat > "$tmp/fixture/scripts/check-backup-health.sh" <<'CHECK'
#!/usr/bin/env bash
printf 'checked-backup\n' >> "$TRACE"
CHECK
cat > "$tmp/fixture/scripts/restore-isolated.sh" <<'RESTORE'
#!/usr/bin/env bash
printf 'restore %s %s\n' "$1" "$2" >> "$TRACE"
[[ "$1" =~ ^pncp-restore-check-[0-9]{14}-[0-9a-f]{8}$ ]] || exit 98
[[ "$2" == *'.dump.age' ]] || exit 97
[[ ${RESTORE_PREFLIGHT_FAIL:-0} == 0 ]] || exit 42
[[ ${RESTORE_FAIL:-0} == 0 ]]
RESTORE
cat > "$tmp/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$TRACE"
case "$*" in
  'volume inspect pncp-restore-check-'*) [[ ${VOLUME_EXISTS:-0} == 1 ]] ;;
  'compose -p pncp-restore-check-'*' down --volumes') [[ ${CLEANUP_FAIL:-0} == 0 ]] ;;
  *) exit 99 ;;
esac
DOCKER
chmod 755 "$tmp/bin/docker"
export TRACE="$tmp/trace" PATH="$tmp/bin:$PATH"
cli="$tmp/fixture/backupctl"
archive="$tmp/fixture/backups/pncp-20261028T120000Z-abc.dump.age"
archive_old="$tmp/fixture/backups/pncp-20261027T120000Z-abc.dump.age"
identity="$tmp/private-age-identity"
printf 'fake encrypted bytes\n' > "$archive_old"
printf 'new fake encrypted bytes\n' > "$archive"
printf 'private test fixture\n' > "$identity"
chmod 600 "$archive" "$archive_old" "$identity"
touch -d '2 days ago' "$archive_old"
pass "$cli" --help
pass "$cli" status
pass "$cli" run
[[ $(cat "$tmp/trace") == $'checked-status\nmade-backup\nchecked-backup' ]] || fail 'Status/run delegated incorrectly'
pass "$cli" list
grep -q 'pncp-20261028T120000Z-abc.dump.age' "$tmp/stdout" || fail 'List missing archive'
! grep -q 'fake encrypted bytes' "$tmp/stdout" || fail 'List leaked content'
: > "$tmp/trace"
pass "$cli" verify --identity "$identity"
grep -q '^PASS: backup decrypted, restored' "$tmp/stdout" || fail 'Verify missing RTO output'
[[ $(grep -c '^restore ' "$tmp/trace") == 1 ]] || fail 'Verify restore skipped'
! grep -q ' down --volumes' "$tmp/trace" || fail 'Default verify unexpectedly deleted isolated volume'
: > "$tmp/trace"
pass "$cli" verify --backup "$archive_old" --identity "$identity" --cleanup
grep -Eq '^docker compose -p pncp-restore-check-[0-9]{14}-[0-9a-f]{8} down --volumes$' "$tmp/trace" || fail 'Cleanup wrong project scope'
: > "$tmp/trace"
reject env RESTORE_PREFLIGHT_FAIL=1 "$cli" verify --identity "$identity" --cleanup
grep -q 'BEFORE creating the isolated database' "$tmp/stderr" || fail 'Incorrect age identity message'
! grep -q 'retained for investigation' "$tmp/stderr" || fail 'Preflight failure falsely claims a DB exists'
! grep -q ' down --volumes' "$tmp/trace" || fail 'Preflight failure unexpectedly attempted cleanup'
: > "$tmp/trace"
reject env RESTORE_FAIL=1 "$cli" verify --identity "$identity" --cleanup
! grep -q ' down --volumes' "$tmp/trace" || fail 'Failed restore unexpectedly deleted volume'
: > "$tmp/trace"
reject env VOLUME_EXISTS=1 "$cli" verify --identity "$identity" --cleanup
! grep -q '^restore ' "$tmp/trace" || fail 'Collision should reject before restore'
: > "$tmp/trace"
reject "$cli" verify --identity "$tmp/missing-key"
! grep -q '^docker' "$tmp/trace" || fail 'Missing identity reached Docker'
chmod 644 "$identity"
reject "$cli" verify --identity "$identity"
chmod 600 "$identity"
: > "$tmp/trace"
chmod 644 "$archive"
reject "$cli" verify --identity "$identity"
chmod 600 "$archive"
ln -s "$archive" "$tmp/fixture/backups/pncp-latest.dump.age"
reject "$cli" list
rm "$tmp/fixture/backups/pncp-latest.dump.age"
reject "$cli" verify --unexpected
reject "$cli" status extra
reject "$cli" run extra
reject "$cli" verify --backup "$archive"
printf '%s\n' 'PASS: backupctl status/run/list/verify/cleanup, newest selection, file modes, symlink rejection, collision guard and failed-restore volume preservation.'
