-- Every message the receiver has accepted, by its webhook id. A row here is
-- what makes a replay a duplicate. It is written in the same transaction as
-- the change it records (moderation.apply_event), so a failed apply leaves no
-- row and the platform's retry is applied, not ignored.
create table moderation.events (
  "id"         text        primary key,
  "type"       text        not null,
  "itemKey"    text        not null,
  "decidedAt"  timestamptz not null,
  "outcome"    text        not null default 'applied',
  "payload"    jsonb       not null,
  "receivedAt" timestamptz not null default now(),
  constraint "events_outcome_valid" check ("outcome" in ('applied', 'stale'))
);

alter table moderation.events enable row level security;

revoke all on table moderation.events from public, anon, authenticated;
grant select, insert, update on table moderation.events to service_role;

comment on table moderation.events is 'Moderation messages received from the platform, keyed by webhook id.';
