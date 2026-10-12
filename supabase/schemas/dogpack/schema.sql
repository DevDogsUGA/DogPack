-- The app's schema, and the only one PostgREST serves (`[api] schemas` in
-- config.toml). Everything a signed-in member does goes through tables and
-- functions here, under row level security; see docs/guides/backend.md.
create schema if not exists dogpack;

-- `anon` gets no usage on purpose: nothing in DogPack is readable before
-- sign-in. `authenticated` is a member with a session; `service_role` is the
-- Edge Functions.
grant usage on schema dogpack to authenticated, service_role;
