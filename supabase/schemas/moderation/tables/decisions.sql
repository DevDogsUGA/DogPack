-- The newest decision applied to each item (`content:<type>:<ref>` or
-- `user:<platform user id>`). A message dated before it is stale: it is
-- acknowledged and ignored, so a late retry cannot undo a newer decision.
create table moderation.decisions (
  "itemKey"   text        primary key,
  "type"      text        not null,
  "decidedAt" timestamptz not null
);

alter table moderation.decisions enable row level security;

revoke all on table moderation.decisions from public, anon, authenticated;
grant select, insert, update on table moderation.decisions to service_role;

comment on table moderation.decisions is 'The last moderation decision applied to each item, for ordering.';
