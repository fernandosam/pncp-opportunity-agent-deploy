import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const files = ['.env.app', '.env.worker', '.env.database', '.env.migrate', '.env.backup'];
if (files.some(existsSync)) throw new Error('Refusing to overwrite existing runtime configuration');
const admin = randomBytes(32).toString('hex');
const runtime = randomBytes(32).toString('hex');
const feedback = randomBytes(48).toString('hex');
const ca = readFileSync('.secrets/database.crt', 'utf8').trim();
// Single-quoted Compose dotenv values preserve multiline PEM and literal $.
function save(file, data) {
  writeFileSync(file, Object.entries(data).map(([k,v]) => `${k}='${String(v).replaceAll("'", "\\'")}'`).join('\n')+'\n', {mode:0o600, flag:'wx'});
}
const common = {
  NODE_ENV:'production', APP_URL:'http://localhost:3000',
  DATABASE_URL:`postgresql://pncp_app:${runtime}@database:5432/pncp_opportunity_agent`,
  DATABASE_CA_CERT:ca, DATABASE_TLS_SERVER_NAME:'database',
  RESEND_API_KEY:'', RESEND_FROM:'PNCP Opportunity Agent <onboarding@resend.dev>',
  FEEDBACK_TOKEN_SECRET:feedback, FEEDBACK_TOKEN_PREVIOUS_SECRETS:'',
};
save('.env.app', common);
save('.env.worker', {...common,
  OPENAI_BASE_URL:'https://api.groq.com/openai/v1', OPENAI_API_KEY:'',
  OPENAI_MODEL:'openai/gpt-oss-120b', OPENAI_PROMPT_VERSION:'v3',
  OPENAI_MAX_COST_PER_CALL_USD:'0.034', WORKER_MAX_LLM_COST_USD_PER_DAY:'0.20',
  WORKER_COMPANY_IDS:'', WORKER_MAX_EVALUATIONS_PER_RUN:'4',
  PNCP_ENRICHMENT_ENABLED:'true', PNCP_PUBLICATION_FALLBACK_ENABLED:'false',
  PNCP_TIMEOUT_MS:'30000', WORKER_POLL_INTERVAL_MS:'5000',
});
save('.env.database', {POSTGRES_USER:'pncp_admin', POSTGRES_DB:'pncp_opportunity_agent', POSTGRES_PASSWORD:admin, PNCP_RUNTIME_PASSWORD:runtime});
save('.env.migrate', {...common, DATABASE_URL:`postgresql://pncp_admin:${admin}@database:5432/pncp_opportunity_agent`});
save('.env.backup', {PGHOST:'database', PGPORT:'5432', PGDATABASE:'pncp_opportunity_agent', PGUSER:'pncp_admin', PGPASSWORD:admin, PGSSLMODE:'verify-full', PGSSLROOTCERT:'/run/secrets/database.crt'});
