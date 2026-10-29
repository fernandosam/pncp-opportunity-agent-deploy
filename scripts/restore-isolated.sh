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
# Fail before creating a PostgreSQL volume if the age identity cannot decrypt
# this archive. The PGDMP header is checked and the entire authenticated stream
# is consumed; decrypted data is never saved to disk or printed to the host.
# Image postgres:18-alpine + age + bash already contains all required tools.
if ! docker compose -p "$project" --profile maintenance run --rm --no-deps -T \
  --entrypoint bash -v "$backup:/restore/backup.age:ro" -v "$identity:/restore/identity:ro" \
  backup -o pipefail -c \
  'age --decrypt --identity /restore/identity /restore/backup.age | { IFS= read -r -N 5 magic && [[ "$magic" == PGDMP ]] && cat >/dev/null; }' \
  >/dev/null; then
  echo 'FAIL: Backup preflight: age identity did not decrypt a complete PostgreSQL custom-format archive. No isolated database was started.' >&2
  echo 'Use the original AGE-SECRET-KEY-1 private identity matching backup.recipient (not a .dump.age file, public age1... recipient, or recipient-encrypted key).' >&2
  exit 42
fi
printf '%s\n' 'PASS: backup decrypted and PGDMP header authenticated; starting isolated PostgreSQL restore.'
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
# Post-restore metadata verification (not tenant payloads or credentials).
# Require auth migration 015, forced RLS for every public tenant table and a restricted runtime role.
verified=$(docker compose -p "$project" exec -T database psql -v ON_ERROR_STOP=1 \
  -U pncp_admin -d pncp_opportunity_agent -Atc "
  select case when
    exists (select 1 from public.schema_migrations where name='015_auth_capability_rls.up.sql')
    and exists (select 1 from pg_roles where rolname='pncp_app' and not rolsuper and not rolbypassrls)
    and exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname='company_opportunities' and c.relrowsecurity and c.relforcerowsecurity)
    and not exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      join pg_attribute a on a.attrelid=c.oid and a.attname='company_id' and a.attnum>0 and not a.attisdropped
      where n.nspname='public' and c.relkind in ('r','p') and (not c.relrowsecurity or not c.relforcerowsecurity)
    )
  then 'ok' else 'fail' end;")
[[ "$verified" == ok ]] || { echo 'Restore postflight failed: migration 015, forced tenant RLS or least-privilege role missing.' >&2; exit 1; }
echo 'Restore completed in isolated project. Migration 015, forced tenant RLS and runtime privileges verified; volumes retained and source unchanged.'
