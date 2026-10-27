-- The moderation receiver's state: which platform messages were applied, the
-- last decision per item, and which platform users are suspended, banned or deleted.
-- Not exposed over the API. Only `moderation.apply_event` writes it, and only
-- the `platform-moderation` Edge Function calls that.
create schema if not exists moderation;

grant usage on schema moderation to service_role;
