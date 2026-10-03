#!/bin/bash
set -euo pipefail
# Daily at 03:30 UTC, recalculated after each run/restart; failures do not expire backups.
recipient=$(cat /run/secrets/backup.recipient)
[[ "$recipient" == age1* ]] || { echo 'Configure the age recipient before scheduling.' >&2; exit 1; }
while true; do
  now=$(date -u +%s)
  next=$(date -u -d 'today 03:30' +%s)
  if (( next <= now )); then next=$(date -u -d 'tomorrow 03:30' +%s); fi
  sleep "$((next-now))"
  /usr/local/bin/pncp-backup || echo 'BACKUP_FAILED: inspect service; previous encrypted files retained.' >&2
done
