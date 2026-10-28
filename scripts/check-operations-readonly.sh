#!/usr/bin/env bash
# Read-only checks for an already provisioned Docker host. Does not start any service.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ $# == 0 ]] || die 'Usage: bash scripts/check-operations-readonly.sh'
for binary in docker openssl stat; do
  command -v "$binary" >/dev/null || die "Missing prerequisite: $binary"
done
[[ -d .secrets && -f .secrets/database.crt && -s .secrets/database.key ]] || die 'PostgreSQL TLS certificate or private key missing'
[[ $(stat -c %a .secrets) == 700 ]] || die 'Secrets directory must have mode 700'
[[ $(stat -c %a .secrets/database.key) == 600 ]] || die 'Database private key must have mode 600'
# The generated certificate is self-signed, includes SAN DNS:database and acts as the local trust anchor.
openssl verify -CAfile .secrets/database.crt -verify_hostname database .secrets/database.crt >/dev/null 2>&1 || die 'Database TLS certificate is invalid or hostname does not match'
openssl x509 -in .secrets/database.crt -checkend $((30 * 86400)) -noout >/dev/null 2>&1 || die 'Database TLS certificate expires within 30 days'
printf '%s\n' 'PASS: PostgreSQL certificate chain, database hostname, 30-day expiry margin and key permissions.'

docker compose --profile backups config --quiet || die 'Compose configuration invalid'
scheduler=$(docker compose --profile backups ps -q backup-scheduler) || die 'Cannot inspect backup scheduler'
[[ -n $scheduler ]] || die 'Backup scheduler container is not running'
running=$(docker inspect --format '{{.State.Running}}' "$scheduler") || die 'Cannot inspect backup scheduler runtime state'
[[ $running == true ]] || die 'Backup scheduler container is stopped'
printf '%s\n' 'PASS: scheduled encrypted backup container is running.'

bash scripts/check-backup-health.sh || die 'Backup freshness, permissions or seven-day retention failed'
printf '%s\n' 'PASS: scheduled backups and TLS certificate operational checks completed.'
printf '%s\n' 'NOT VERIFIED: backup decryptability, restore time, external copy durability, alerts delivery or real data retention.'
