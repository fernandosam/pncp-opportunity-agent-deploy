#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -s .secrets/backup.recipient ]] || { echo 'Configure the public age recipient first.' >&2; exit 1; }
docker compose --profile maintenance run --rm backup
