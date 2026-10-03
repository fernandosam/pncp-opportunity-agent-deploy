# Deployment repository

Application source lives in sibling `../pncp-opportunity-agent`. Do not duplicate domain logic or application migrations here.

- Never commit `.env*` except `.env.example`, `.secrets`, dumps, tokens or real payloads. Private files use mode 600 and secret directories mode 700.
- Never print rendered `docker compose config`; use `config --quiet`.
- Production, billing, destructive volume operations, restoration over a populated database and schema changes require explicit human authorization.
- Worker is opt-in. Do not enable it or call real LLM/email providers as part of tests.
- PostgreSQL 18 uses a volume at `/var/lib/postgresql`; do not change the major version or PGDATA without a migration/rollback plan.
- Preserve unknown-cost reservations and native claims/idempotency when importing historical data. Never change prompt/profile/source keys just to replay failed calls.
- Use isolated Compose project names/volumes for tests and restore rehearsals. `down` must never include `--volumes` on a real deployment.
