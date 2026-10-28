#!/usr/bin/env bash
# Execute the application CI-equivalent quality sequence locally without GitHub Actions.
# No worker starts and no live application provider credentials are needed.
set -euo pipefail
cd "$(dirname "$0")/.."
die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ $# == 1 && $1 =~ ^[0-9a-f]{40}$ ]] || die 'Usage: bash scripts/check-app-local.sh <40-character application SHA>'
sha=$1
command -v git >/dev/null && command -v node >/dev/null && command -v pnpm >/dev/null || die 'git, Node 24 and pnpm 10 are required'
[[ $(node -p 'process.versions.node.split(".")[0]') == 24 ]] || die 'Node.js 24 is required by the application'
[[ $(pnpm --version) == 10.* ]] || die 'pnpm 10 is required by the application'
read_setting() {
  [[ -f .env ]] || return 0
  local value
  value=$(sed -n "s/^APP_SOURCE=//p" .env | tail -n 1)
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s' "$value"
}
app_source=${APP_SOURCE:-$(read_setting)}
app_source=${app_source:-../pncp-opportunity-agent}
[[ -e $app_source/.git ]] || die 'APP_SOURCE must point to an application Git checkout'
actual=$(git -C "$app_source" rev-parse HEAD) || die 'Cannot resolve application SHA'
[[ $actual == "$sha" ]] || die 'Application checkout SHA differs from requested SHA'
[[ -z $(git -C "$app_source" status --porcelain) ]] || die 'Application checkout is not clean'

cd "$app_source"
printf 'Local application quality validation for SHA %s\n' "$sha"
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm test
pnpm test:integration
pnpm build
pnpm audit --audit-level high
pnpm test:e2e
printf 'PASS: local lint, typecheck, unit, integration, build, audit and E2E on SHA %s\n' "$sha"
printf '%s\n' 'This is local evidence only. It does not satisfy the GitHub push-CI requirement of release:gate.'
