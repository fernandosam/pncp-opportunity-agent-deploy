#!/bin/sh
set -eu
# Root only copies the private key; the official entrypoint drops to postgres.
install -d -m 750 -o postgres -g postgres /run/pncp-tls
install -m 644 -o postgres -g postgres /run/secrets/database.crt /run/pncp-tls/server.crt
install -m 600 -o postgres -g postgres /run/secrets/database.key /run/pncp-tls/server.key
exec /usr/local/bin/docker-entrypoint.sh "$@"
