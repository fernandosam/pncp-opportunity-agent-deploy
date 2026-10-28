#!/usr/bin/env bash
# Pre-activation Docker inspection: never starts a worker or sends provider requests.
set -euo pipefail
cd "$(dirname "$0")/.."
die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ $# == 0 ]] || die 'Usage: bash scripts/check-stack-readonly.sh'
command -v docker >/dev/null || die 'Docker is not installed'
docker compose config --quiet || die 'Invalid Compose configuration'

for service in database web; do
  container_id=$(docker compose ps -q "$service")
  [[ -n $container_id ]] || die "$service container is not running"
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")
  [[ $health == healthy ]] || die "$service health is not healthy"
done

worker_id=$(docker compose ps -a -q worker)
if [[ -n $worker_id ]]; then
  running=$(docker inspect --format '{{.State.Running}}' "$worker_id")
  [[ $running == false ]] || die 'Worker is active: do not run pre-activation checks as proof of a disabled worker'
fi

# Node runs inside the existing web container. Only SELECT queries and local requests.
docker compose exec -T web node --input-type=module < scripts/smoke.mjs || die 'PostgreSQL/TLS/RLS smoke failed'
docker compose exec -T web node --input-type=module <<'NODE' || die 'Local HTTP health/readiness failed'
for (const [path, expected] of [['/api/health', 'ok'], ['/api/ready', 'ready']]) {
  const response = await fetch('http://127.0.0.1:3000' + path, {
    redirect: 'manual', signal: AbortSignal.timeout(7000),
  });
  if (response.status !== 200 || !response.headers.get('cache-control')?.includes('no-store')) {
    throw new Error(path + ' must return HTTP 200 and no-store');
  }
  const body = await response.json();
  if (body.status !== expected || body.component !== 'web') {
    throw new Error(path + ' returned unexpected health status');
  }
  console.log('PASS: local ' + path + ' is healthy with no-store');
}
NODE
printf '%s\n' 'PASS: database/web healthy; worker stopped; migration 015, RLS, TLS and HTTP readiness verified.'
printf '%s\n' 'NOT VERIFIED: real provider delivery, real browser accessibility, backup restore, worker recovery, approved production deployment.'
