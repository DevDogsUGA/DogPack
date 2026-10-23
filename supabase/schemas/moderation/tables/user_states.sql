-- Platform users who are suspended or banned, keyed by their DEVDOGS user id
-- (the subject of their custom:devdogsuga identity), not by DogPack's own
-- auth id. A ban can arrive before the person ever signs in to DogPack, and
-- must still bite when they do; `private.is_restricted` joins the two ids at
-- check time. The row survives "delete my data" on purpose: deleting your
-- data does not lift a ban.
--
-- Account deletion (`user.delete`): the row stays with state 'deleted' and no
-- reason. It holds only the platform's own user id, which the platform has
-- already deleted, and it keeps a late or replayed message about that id from
-- being treated as a new person. The local auth user and everything DogPack
-- holds on it is removed by the platform-moderation function.
create table moderation.user_states (
  "platformUserId" uuid        primary key,
  "state"          text        not null,
  "reason"         text,
  "decidedAt"      timestamptz not null,
  constraint "user_states_state_valid" check ("state" in ('active', 'suspended', 'banned', 'deleted'))
);

alter table moderation.user_states enable row level security;

revoke all on table moderation.user_states from public, anon, authenticated;
grant select, insert, update on table moderation.user_states to service_role;

comment on table moderation.user_states is 'Suspended, banned and deleted platform users, keyed by the DevDogs user id.';
