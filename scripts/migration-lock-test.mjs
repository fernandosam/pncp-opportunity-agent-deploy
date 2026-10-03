import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
const { Pool } = createRequire('/app/package.json')('pg');
const pool = new Pool({connectionString:process.env.DATABASE_URL,ssl:{rejectUnauthorized:true,ca:process.env.DATABASE_CA_CERT,servername:'database'}});
const client = await pool.connect();
function migrate() { return spawnSync(process.execPath,['node_modules/tsx/dist/cli.mjs','scripts/migrate.ts'],{cwd:'/app',env:process.env,encoding:'utf8',timeout:15000}); }
try {
  await client.query("select pg_advisory_lock(hashtext('pncp-schema-migrations'))");
  const blocked = migrate();
  assert.notEqual(blocked.status,0);
  assert.ok(blocked.stderr.includes('MIGRATION_ALREADY_RUNNING'));
  await client.query("select pg_advisory_unlock(hashtext('pncp-schema-migrations'))");
  assert.equal(migrate().status,0);
  console.log('PASS: concurrent migration refused; repeat succeeds after lock release.');
} finally { client.release(); await pool.end(); }
