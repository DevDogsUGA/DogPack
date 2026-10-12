-- Helpers, trigger functions and the checks row level security calls. Not in
-- `[api] schemas`, so none of it is reachable as an RPC: a member cannot ask
-- "is this user banned" or "is this user enrolled in that course" about anyone
-- but themselves, which is all the policies ask.
create schema if not exists private;

grant usage on schema private to authenticated, service_role;
