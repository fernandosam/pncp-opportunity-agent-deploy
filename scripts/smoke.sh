#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose config --quiet
docker compose exec -T web node --input-type=module < scripts/smoke.mjs
curl --fail --silent --show-error "http://127.0.0.1:${WEB_PORT:-3000}/api/health"
echo
curl --fail --silent --show-error "http://127.0.0.1:${WEB_PORT:-3000}/api/ready"
echo
docker compose --profile worker run --rm -e NODE_ENV=test worker
