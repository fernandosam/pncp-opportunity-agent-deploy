#!/usr/bin/env bash
# Execute the application CI-equivalent quality sequence locally without GitHub Actions.
# Tests run under CI placeholders; provider credentials from the host are not inherited.
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

# Match .github/workflows/ci.yml placeholders, never inherit production credentials.
# CI=1 prevents Playwright from reusing a server on localhost:3100.
# Do not set NODE_ENV: Next sets it based on build/dev command.
ci_env=(
  env -i "PATH=$PATH" "HOME=$HOME" "LANG=${LANG:-C.UTF-8}" "CI=1"
  "NEXT_TELEMETRY_DISABLED=1"
  "APP_URL=http://localhost:3000"
  "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pncp_opportunity_agent"
  "OPENAI_BASE_URL=https://api.groq.com/openai/v1"
  "OPENAI_API_KEY=gsk_ci_placeholder" "OPENAI_MODEL=openai/gpt-oss-120b"
  "OPENAI_PROMPT_VERSION=v3" "OPENAI_MAX_COST_PER_CALL_USD=0.05"
  "WORKER_MAX_LLM_COST_USD_PER_DAY=1.00"
  "RESEND_API_KEY=re_ci_placeholder"
  "RESEND_FROM=PNCP Opportunity Agent <briefing@example.com>"
  "FEEDBACK_TOKEN_SECRET=ci-placeholder-secret-with-at-least-32-characters"
  "WORKER_COMPANY_IDS=company-ci"
)
cd "$app_source"
printf 'Local application quality validation for SHA %s (CI placeholders, no real credentials)\n' "$sha"
"${ci_env[@]}" pnpm install --frozen-lockfile
"${ci_env[@]}" pnpm lint
"${ci_env[@]}" pnpm typecheck
"${ci_env[@]}" pnpm test
"${ci_env[@]}" pnpm test:integration
"${ci_env[@]}" pnpm build
"${ci_env[@]}" pnpm audit --audit-level high
"${ci_env[@]}" pnpm exec playwright install chromium
"${ci_env[@]}" pnpm test:e2e
printf 'PASS: local lint, typecheck, unit, integration, build, audit, Chromium and E2E on SHA %s\n' "$sha"
printf '%s\n' 'Local evidence only: final production gate still requires GitHub push-CI on exactly this SHA.'
