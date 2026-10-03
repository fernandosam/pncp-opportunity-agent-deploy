#!/bin/sh
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=runtime_password="$PNCP_RUNTIME_PASSWORD" <<'SQL'
select format('create role pncp_app login nosuperuser nocreatedb nocreaterole nobypassrls password %L', :'runtime_password') \gexec
create schema pgboss authorization pncp_app;
revoke create on schema public from public;
SQL
# TCP clients must negotiate TLS. Unix sockets remain local to this container.
sed -i '/^host /s/^host /hostssl /' "$PGDATA/pg_hba.conf"
printf '\nhostnossl all all all reject\n' >> "$PGDATA/pg_hba.conf"
