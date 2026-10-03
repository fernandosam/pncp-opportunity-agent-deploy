#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose config --quiet
docker compose exec -T database psql -X -U pncp_admin -d pncp_opportunity_agent \
  -v ON_ERROR_STOP=1 -At < scripts/reconcile.sql
