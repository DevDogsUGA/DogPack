-- Platform users who are suspended or banned, keyed by their DEVDOGS user id
-- (the subject of their custom:devdogsuga identity), not by DogPack's own
-- auth id. A ban can arrive before the person ever signs in to DogPack, and
-- must still bite when they do; `private.is_restricted` joins the two ids at
-- check time. The row survives "delete my data" on purpose: deleting your
-- data does not lift a ban.
create table moderation.user_states (
  "platformUserId" uuid        primary key,
  "state"          text        not null,
  "reason"         text,
  "decidedAt"      timestamptz not null,
  constraint "user_states_state_valid" check ("state" in ('active', 'suspended', 'banned'))
);

alter table moderation.user_states enable row level security;

revoke all on table moderation.user_states from public, anon, authenticated;
grant select, insert, update on table moderation.user_states to service_role;

comment on table moderation.user_states is 'Suspended and banned platform users, keyed by the DevDogs user id.';
