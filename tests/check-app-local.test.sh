#!/usr/bin/env bash
# Offline contract test: validates environment isolation and failure propagation.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/deploy/scripts" "$work/app" "$work/bin"
cp "$root/scripts/check-app-local.sh" "$work/deploy/scripts/"
printf 'APP_SOURCE=../app\n' > "$work/deploy/.env"
git -C "$work/app" init -q
git -C "$work/app" -c user.name=Fixture -c user.email=fixture@example.test commit --allow-empty -qm fixture
sha=$(git -C "$work/app" rev-parse HEAD)
cat > "$work/bin/node" <<'NODE'
#!/usr/bin/env bash
if [[ $1 == -p ]]; then printf '24\n'; else exit 99; fi
NODE
cat > "$work/bin/pnpm" <<'PNPM'
#!/usr/bin/env bash
if [[ $1 == --version ]]; then printf '10.13.1\n'; exit; fi
printf '%s\tCI=%s\tKEY=%s\tGROQ=%s\tDB=%s\tOTHER=%s\tURL=%s\n' "$*" "${CI-unset}" "${RESEND_API_KEY-unset}" "${OPENAI_API_KEY-unset}" "${DATABASE_URL-unset}" "${SENSITIVE_TEST_SECRET-unset}" "${OPENAI_BASE_URL-unset}" >> '__LOG__'
if [[ $1 == audit && -f '__FAIL__' ]]; then exit 3; fi
PNPM
sed -i "s|__LOG__|$work/log|g; s|__FAIL__|$work/fail-audit|g" "$work/bin/pnpm"
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
expect_ok() { "$@" >/dev/null || fail "command unexpectedly failed: $*"; }
expect_bad() { if "$@" >/dev/null 2>&1; then fail "command unexpectedly passed: $*"; fi; }
# Poison the parent environment: none of these actual values may be seen by tests.
export SENSITIVE_TEST_SECRET=REAL_TOKEN RESEND_API_KEY=REAL_RESEND OPENAI_API_KEY=REAL_GROQ
export DATABASE_URL='postgresql://production:secret@prod/db' OPENAI_BASE_URL=https://attacker.invalid/v1
expect_ok bash "$work/deploy/scripts/check-app-local.sh" "$sha"
[[ $(wc -l < "$work/log") == 9 ]] || fail 'Expected 9 pnpm operations'
[[ $(grep -c 'CI=1' "$work/log") == 9 ]] || fail 'CI flag missing'
[[ $(grep -c 'KEY=re_ci_placeholder' "$work/log") == 9 ]] || fail 'Resend placeholder missing'
[[ $(grep -c 'GROQ=gsk_ci_placeholder' "$work/log") == 9 ]] || fail 'Groq placeholder missing'
[[ $(grep -c 'OTHER=unset' "$work/log") == 9 ]] || fail 'Inherited unrelated secret'
[[ $(grep -c 'URL=https://api.groq.com/openai/v1' "$work/log") == 9 ]] || fail 'Unexpected Groq endpoint'
[[ $(grep -c 'DB=postgresql://postgres:postgres@localhost:5432/pncp_opportunity_agent' "$work/log") == 9 ]] || fail 'Inherited database URL'
grep -q '^exec playwright install chromium' "$work/log" || fail 'Chromium installer missing'
tail -n 1 "$work/log" | grep -q '^test:e2e' || fail 'E2E must run last'
expect_bad bash "$work/deploy/scripts/check-app-local.sh" "$(printf '0%.0s' {1..40})"
touch "$work/app/untracked"
expect_bad bash "$work/deploy/scripts/check-app-local.sh" "$sha"
rm "$work/app/untracked"
: > "$work/fail-audit"
: > "$work/log"
expect_bad bash "$work/deploy/scripts/check-app-local.sh" "$sha"
[[ $(wc -l < "$work/log") == 7 ]] || fail 'Audit failure did not stop pipeline'
rm "$work/fail-audit"
expect_bad bash "$work/deploy/scripts/check-app-local.sh" invalid
printf '%s\n' 'PASS: nine local CI operations, isolated env/credentials, Chromium, SHA and failure propagation.'
