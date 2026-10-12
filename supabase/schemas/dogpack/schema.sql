create schema if not exists "dogpack";
grant usage on schema "dogpack" to anon, authenticated, service_role;
alter default privileges in schema "dogpack" grant all on tables to anon, authenticated, service_role;
