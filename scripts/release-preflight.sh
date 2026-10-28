#!/usr/bin/env bash
# Read-only cross-repository checks before the human V1 release gate.
# No builds, migrations, provider calls, worker activation or secret output.
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Usage: scripts/release-preflight.sh <approved 40-character application SHA>' >&2
  exit 2
fi
approved_sha=$1
cd "$(dirname "$0")/.."

die() { echo "FAIL: $1" >&2; exit 1; }
read_setting() {
  local key=$1 value
  value=$(sed -n "s/^${key}=//p" .env | tail -n 1)
  value=${value#\"}
  value=${value%\"}
  value=${value#\'}
  value=${value%\'}
  printf '%s' "$value"
}

[[ -f .env && -f .env.app && -f .env.worker && -f .env.database && -f .env.migrate ]] || die 'Docker environment is not initialized'
command -v git >/dev/null || die 'git is required'
command -v docker >/dev/null || die 'Docker Compose is required'
app_source=${APP_SOURCE:-$(read_setting APP_SOURCE)}
app_source=${app_source:-../pncp-opportunity-agent}
image_tag=${APP_IMAGE_TAG:-$(read_setting APP_IMAGE_TAG)}
app_url=${APP_URL:-$(read_setting APP_URL)}
[[ -n $image_tag && $image_tag == "$approved_sha" ]] || die 'APP_IMAGE_TAG must match the approved immutable application SHA'
[[ $app_url == https://* && $app_url != https://localhost* && $app_url != https://127.0.0.1* ]] || die 'Production APP_URL must be a public HTTPS origin'
[[ -d $app_source/.git ]] || die 'APP_SOURCE is not an application Git checkout'
actual_sha=$(git -C "$app_source" rev-parse HEAD) || die 'Cannot read application HEAD'
[[ $actual_sha == "$approved_sha" ]] || die 'Application checkout does not match approved SHA'
[[ -z $(git -C "$app_source" status --porcelain) ]] || die 'Application checkout has uncommitted or untracked changes'
[[ -z $(git status --porcelain) ]] || die 'Deployment checkout has uncommitted or untracked changes'
# --quiet validates Compose without printing interpolated secret environment values.
docker compose config --quiet || die 'Docker Compose configuration is invalid'
echo 'PASS: clean repositories, approved app SHA/image tag, public HTTPS origin, initialized environment, Compose syntax.'
echo 'Not checked: GitHub CI/billing, provider delivery, real E2E, backups, worker recovery or human approval (#25).'
