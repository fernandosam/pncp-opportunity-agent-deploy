import { createRequire } from 'node:module';
const { Pool } = createRequire('/app/package.json')('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: true, ca: process.env.DATABASE_CA_CERT, servername: 'database' } });
try {
  await pool.query(`
    grant connect on database pncp_opportunity_agent to pncp_app;
    grant usage on schema public to pncp_app;
    grant select, insert, update, delete on all tables in schema public to pncp_app;
    grant usage, select on all sequences in schema public to pncp_app;
    revoke insert, update, delete on schema_migrations from pncp_app;
    grant select on schema_migrations to pncp_app;
    alter default privileges for role pncp_admin in schema public grant select, insert, update, delete on tables to pncp_app;
    alter default privileges for role pncp_admin in schema public grant usage, select on sequences to pncp_app;
    create schema if not exists pgboss authorization pncp_app;
    alter schema pgboss owner to pncp_app;
    do $$ declare object record; begin
      for object in select c.relname, c.relkind from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='pgboss' and c.relkind in ('r','p','S') loop
        execute format('alter %s pgboss.%I owner to pncp_app', case when object.relkind='S' then 'sequence' else 'table' end, object.relname);
      end loop;
    end $$;
    revoke create on schema public from public;
  `);
  console.log('Runtime grants applied; application is not superuser and does not bypass RLS.');
} finally { await pool.end(); }
