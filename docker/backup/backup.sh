#!/bin/bash
set -euo pipefail
umask 077
recipient=$(cat /run/secrets/backup.recipient)
[[ "$recipient" == age1* ]] || { echo 'A valid age recipient is required.' >&2; exit 1; }
mkdir -p /backups
temporary=$(mktemp "/backups/pncp-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX.dump.age.tmp")
file=${temporary%.tmp}
trap 'rm -f "$temporary"' EXIT
pg_dump --format=custom --no-owner --no-acl | age --recipient "$recipient" > "$temporary"
sync -f "$temporary"
mv --no-clobber "$temporary" "$file"
[[ ! -e "$temporary" ]] || { echo 'Backup filename collision; previous archive preserved.' >&2; exit 1; }
# Expunge only after a new encrypted backup has been committed.
find /backups -maxdepth 1 -type f -name 'pncp-*.dump.age' -mtime +6 -delete
printf 'Encrypted backup completed: %s\n' "${file##*/}"
