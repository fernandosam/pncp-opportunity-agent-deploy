#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo 'Usage: restore-isolated.sh pncp-restore-NAME BACKUP.age IDENTITY_FILE' >&2; exit 1; }
project=$1
[[ "$project" =~ ^pncp-restore-[a-z0-9-]+$ ]] || { echo 'An isolated pncp-restore-* project is required.' >&2; exit 1; }
umask 077
exec 9>".secrets/$project.lock"
flock -n 9 || { echo 'Restore already in progress for this project.' >&2; exit 1; }
backup=$(realpath "$2"); identity=$(realpath "$3")
[[ -s "$backup" && -s "$identity" && "$backup" == *.age ]] || { echo 'Encrypted backup and identity required.' >&2; exit 1; }
# No --volumes deletion, no source database connection, no plaintext dump file.
docker compose -p "$project" up -d --wait database
count=$(docker compose -p "$project" exec -T database psql -U pncp_admin -d pncp_opportunity_agent -Atc "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p','S','v','m') and n.nspname not in ('pg_catalog','information_schema') and n.nspname not like 'pg_toast%';")
[[ "$count" == 0 ]] || { echo 'Restore refused: target already contains user objects.' >&2; exit 1; }
docker compose -p "$project" --profile maintenance run --rm --no-deps -T \
  --entrypoint age -v "$backup:/restore/backup.age:ro" -v "$identity:/restore/identity:ro" \
  backup --decrypt --identity /restore/identity /restore/backup.age \
  | docker compose -p "$project" exec -T database pg_restore \
    --username pncp_admin --dbname pncp_opportunity_agent --no-owner --no-acl \
    --clean --if-exists --single-transaction --exit-on-error
docker compose -p "$project" --profile maintenance run --rm migrate
echo 'Restore completed in isolated project. Volumes retained; source unchanged.'
