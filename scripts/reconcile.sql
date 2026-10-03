-- Metadata/counts only. No source payloads, tokens, e-mails or passwords.
-- Consistent snapshot; this audit never changes data.
begin transaction isolation level repeatable read read only;
select json_build_object('check','schema','migrations',(select count(*) from schema_migrations),
 'public_tables',(select count(*) from pg_tables where schemaname='public'),
 'rls_tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relrowsecurity),
 'unvalidated_constraints',(select count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname='public' and not c.convalidated));
select json_build_object('check','runtime_role','superuser',rolsuper,'bypass_rls',rolbypassrls,
 'can_write_migration_journal',has_table_privilege('pncp_app','public.schema_migrations','INSERT,UPDATE,DELETE'))
from pg_roles where rolname='pncp_app';
select format('select json_build_object(''check'',''table_count'',''table'',%L,''rows'',count(*)) from public.%I;',tablename,tablename)
from pg_tables where schemaname='public' order by tablename
\gexec
select json_build_object('check','llm_budget','records',count(*),'unknown_cost_records',count(*) filter(where status in ('RESERVED','FAILED') and actual_cost_usd is null),
 'commitment_usd',coalesce(sum(case when status='SUCCEEDED' then actual_cost_usd when status='CANCELLED' then 0 else greatest(reserved_cost_usd,coalesce(actual_cost_usd,0)) end),0))
from llm_call_usage;
rollback;
