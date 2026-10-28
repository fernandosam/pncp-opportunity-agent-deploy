import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { checkServerIdentity } from 'node:tls';
const { Pool } = createRequire('/app/package.json')('pg');
const config = {connectionString:process.env.DATABASE_URL, ssl:{rejectUnauthorized:true,ca:process.env.DATABASE_CA_CERT,servername:'database'}};
const pool = new Pool(config);
try {
  const role = (await pool.query('select rolsuper,rolbypassrls from pg_roles where rolname=current_user')).rows[0];
  assert.equal(role.rolsuper,false); assert.equal(role.rolbypassrls,false);
  // Require the approved authentication/RLS baseline, not an exact migration count.
  // Later additive migrations must not invalidate this smoke test.
  const appliedMigrations = new Set((await pool.query('select name from schema_migrations')).rows.map(({name})=>name));
  assert.ok(appliedMigrations.has('015_auth_capability_rls.up.sql'), 'auth capability migration 015 is required');
  assert.equal(Number((await pool.query("select count(*) count from pg_class where relname='company_opportunities' and relrowsecurity and relforcerowsecurity")).rows[0].count),1);
  const tls = (await pool.query('select ssl from pg_stat_ssl where pid=pg_backend_pid()')).rows[0];
  assert.equal(tls.ssl,true);
  for (const ssl of [false,{rejectUnauthorized:true,ca:process.env.DATABASE_CA_CERT,checkServerIdentity:(_host,cert)=>checkServerIdentity('wrong-host',cert)}]) {
    const rejected = new Pool({...config,ssl,connectionTimeoutMillis:5000});
    try { await assert.rejects(rejected.query('select 1')); } finally { await rejected.end(); }
  }
  console.log('PASS: auth migration 015, non-superuser/NOBYPASSRLS, forced RLS, TLS and hostname verification.');
} finally { await pool.end(); }
