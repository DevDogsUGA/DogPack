-- The read-only login the production deploy plans with before anyone approves
-- (the `preflight` environment's DB_URL). It is the same role the platform
-- uses, `migration_planner`: it can read the Supabase CLI's two ledgers and
-- nothing else, so the plan (which runs on `main`, before an approval) never
-- holds a credential that can read member data.
--
-- Run it once per hosted project, as the project's admin, before the first
-- deploy there:
--
--   psql "$ADMIN_URL" -v password="$PLANNER_PASSWORD" -f .github/scripts/planner-role.sql
--
-- The password is the one in the `preflight` DB_URL secret. Rolling it is
-- `alter role migration_planner password '...'` and a new secret.
--
-- A fresh project has no supabase_migrations schema until the first migration
-- runs, and the grants need it, so the CLI's own (idempotent) DDL for the two
-- ledgers is created first. The CLI uses `create ... if not exists` for the
-- same objects, so it carries on from them.
\set ON_ERROR_STOP on

create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text not null primary key);
alter table supabase_migrations.schema_migrations add column if not exists statements text[];
alter table supabase_migrations.schema_migrations add column if not exists name text;
alter table supabase_migrations.schema_migrations add column if not exists created_by text;
alter table supabase_migrations.schema_migrations add column if not exists idempotency_key text;
create unique index if not exists schema_migrations_idempotency_key_key
  on supabase_migrations.schema_migrations (idempotency_key);
create table if not exists supabase_migrations.seed_files (path text primary key, hash text not null);

select exists (select 1 from pg_roles where rolname = 'migration_planner') as present \gset
\if :present
  alter role migration_planner with login password :'password';
\else
  create role migration_planner with login password :'password' nosuperuser nocreatedb nocreaterole noinherit;
\endif

grant usage on schema supabase_migrations to migration_planner;
grant select on supabase_migrations.schema_migrations to migration_planner;
grant select on supabase_migrations.seed_files to migration_planner;
