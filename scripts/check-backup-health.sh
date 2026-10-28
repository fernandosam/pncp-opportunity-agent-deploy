#!/usr/bin/env bash
# Read-only local backup status. No identity/secret is needed and no file is decrypted.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
backup_dir=${1:-backups}
max_age_hours=${BACKUP_MAX_AGE_HOURS:-36}
[[ $max_age_hours =~ ^[1-9][0-9]{0,2}$ ]] && (( max_age_hours <= 168 )) || die 'BACKUP_MAX_AGE_HOURS must be 1..168'
[[ -d $backup_dir ]] || die 'Backup directory is absent'
command -v stat >/dev/null && command -v date >/dev/null || die 'GNU stat and date are required'

now=$(date -u +%s)
freshest=0
count=0
shopt -s nullglob
for file in "$backup_dir"/pncp-*.dump.age; do
  [[ -f $file ]] || continue
  [[ -s $file ]] || die 'An empty encrypted backup is present'
  mode=$(stat -c %a -- "$file")
  [[ $mode == 600 || $mode == 400 ]] || die 'Backup permissions must be 600 or 400'
  mtime=$(stat -c %Y -- "$file")
  (( mtime <= now + 300 )) || die 'Backup timestamp is in the future (check clock)'
  (( now - mtime < 7 * 86400 )) || die 'A backup exceeds the seven-day retention limit'
  if (( mtime > freshest )); then freshest=$mtime; fi
  (( ++count ))
done
(( count > 0 )) || die 'No non-empty encrypted backup exists'
age_seconds=$(( now - freshest ))
(( age_seconds <= max_age_hours * 3600 )) || die 'Newest encrypted backup is stale'
printf 'PASS: %d encrypted backup(s); latest age %d hour(s); permissions and seven-day retention checked.\n' "$count" "$(( age_seconds / 3600 ))"
printf '%s\n' 'NOTE: freshness is not decryptability; restore into an isolated database still requires a separate exercise.'
