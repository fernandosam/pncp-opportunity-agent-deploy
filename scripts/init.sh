#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p .secrets
chmod 700 .secrets
mkdir .secrets/init.lock 2>/dev/null || { echo 'Initialization already in progress.' >&2; exit 1; }
trap 'rmdir .secrets/init.lock' EXIT
for file in .env.app .env.worker .env.database .env.migrate .env.backup .secrets/database.key; do
  [[ ! -e "$file" ]] || { echo 'Already initialized; refusing to rotate existing secrets.' >&2; exit 1; }
done
mkdir -p .secrets backups
chmod 700 .secrets backups
[[ -f .env ]] || cp .env.example .env
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
  -subj '/CN=database' -addext 'subjectAltName=DNS:database' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -keyout .secrets/database.key -out .secrets/database.crt 2>/dev/null
# Bootstrap tooling runs in Docker, not a host Node/pnpm installation.
docker run --rm --user "$(id -u):$(id -g)" --volume "$PWD:/deployment" \
  --workdir /deployment node:24-bookworm-slim node scripts/init.mjs
chmod 600 .env .env.app .env.worker .env.database .env.migrate .env.backup .secrets/*
echo 'Initialized isolated Docker environment. API keys remain empty; worker remains opt-in.'
