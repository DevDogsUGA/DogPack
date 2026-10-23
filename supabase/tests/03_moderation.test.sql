-- The moderation receiver: moderation.apply_event (idempotent, order-safe,
-- atomic), quarantinedBy and what row level security does with it, and bans.
begin;
create extension if not exists pgtap with schema extensions;

create schema tests;
grant usage on schema tests to public;
create function tests.as_user(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
end $$;
grant execute on function tests.as_user(uuid) to public;

-- host (h), classmate (c), and the platform ids their DevDogs identities carry.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000f1', 'host@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000f2', 'classmate@dogpack.devdogsuga.test');
insert into auth.identities (provider_id, user_id, identity_data, provider) values
  ('aaaaaaaa-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000f1', '{"sub":"aaaaaaaa-0000-4000-8000-000000000001"}', 'custom:devdogsuga'),
  ('aaaaaaaa-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000f2', '{"sub":"aaaaaaaa-0000-4000-8000-000000000002"}', 'custom:devdogsuga');
insert into dogpack.terms ("term", "description", "classesBegin", "classesEnd", "dropAddEnds")
  values (202808, 'Open term', current_date - 5, current_date + 90, current_date + 5);
insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt") values
  ('00000000-0000-4000-8000-0000000000f1', 'Host', 'senior', 'CS', now()),
  ('00000000-0000-4000-8000-0000000000f2', 'Classmate', 'junior', 'CS', now());
insert into dogpack.enrollments ("userId", "term", "course") values
  ('00000000-0000-4000-8000-0000000000f1', 202808, 'CSCI 1301'),
  ('00000000-0000-4000-8000-0000000000f2', 202808, 'CSCI 1301');
insert into dogpack.sessions ("id", "hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity") values
  ('33333333-3333-4333-8333-333333333333', '00000000-0000-4000-8000-0000000000f1', 202808, 'CSCI 1301', 'Loops review', 'MLC', now() + interval '1 day', now() + interval '1 day 2 hours', 4);

select plan(58);

-- The function is for the service role only.
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select throws_ok($$select moderation.apply_event('msg_x', '{}'::jsonb)$$, '42501', null, 'a member cannot call apply_event');
select throws_ok($$select * from moderation.events$$, '42501', null, 'a member cannot read the moderation tables');
reset role;

-- A hide: quarantined, hidden from the classmate, still visible to the host.
select is(
  moderation.apply_event('msg_1', '{"type":"content.hide","timestamp":"2027-01-01T10:00:00Z","data":{"contentType":"session","contentRef":"33333333-3333-4333-8333-333333333333","reportId":null}}'::jsonb),
  'applied', 'a content.hide is applied');
select is((select "quarantinedBy" from dogpack.sessions where id = '33333333-3333-4333-8333-333333333333'), 'msg_1', 'the session is quarantined by that message id');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select is((select count(*)::int from dogpack.sessions), 0, 'a quarantined session is hidden from a classmate');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('33333333-3333-4333-8333-333333333333')$$, 'PT404', 'session_unavailable', 'and cannot be joined');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000f1');
select is((select count(*)::int from dogpack.sessions), 1, 'but its author still sees it');
update dogpack.sessions set "title" = 'Sneaky edit' where id = '33333333-3333-4333-8333-333333333333';
reset role;
select is((select "title" from dogpack.sessions where id = '33333333-3333-4333-8333-333333333333'), 'Loops review', 'the author cannot edit a quarantined session');

-- Idempotent.
select is(
  moderation.apply_event('msg_1', '{"type":"content.hide","timestamp":"2027-01-01T10:00:00Z","data":{"contentType":"session","contentRef":"33333333-3333-4333-8333-333333333333","reportId":null}}'::jsonb),
  'duplicate', 'a replay of the same webhook id is a duplicate');
select is((select count(*)::int from moderation.events), 1, 'and records nothing more');

-- Order-safe: a restore dated BEFORE the hide is stale, and the hide stands.
select is(
  moderation.apply_event('msg_2', '{"type":"content.restore","timestamp":"2027-01-01T09:59:00Z","data":{"contentType":"session","contentRef":"33333333-3333-4333-8333-333333333333","reportId":null}}'::jsonb),
  'stale', 'a restore older than the last decision is stale');
select is((select "quarantinedBy" from dogpack.sessions where id = '33333333-3333-4333-8333-333333333333'), 'msg_1', 'the session stays quarantined');
select is(
  moderation.apply_event('msg_2', '{"type":"content.restore","timestamp":"2027-01-01T09:59:00Z","data":{"contentType":"session","contentRef":"33333333-3333-4333-8333-333333333333","reportId":null}}'::jsonb),
  'duplicate', 'a stale message that is replayed is a duplicate, not stale twice');

-- A later restore clears it.
select is(
  moderation.apply_event('msg_3', '{"type":"content.restore","timestamp":"2027-01-01T11:00:00Z","data":{"contentType":"session","contentRef":"33333333-3333-4333-8333-333333333333","reportId":null}}'::jsonb),
  'applied', 'a later restore is applied');
select is((select "quarantinedBy" from dogpack.sessions where id = '33333333-3333-4333-8333-333333333333'), null, 'the session is visible again');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select is((select count(*)::int from dogpack.sessions), 1, 'including to the classmate');
reset role;

-- A profile can be quarantined too, and a message about something DogPack has no row for is recorded.
select is(
  moderation.apply_event('msg_4', '{"type":"content.remove","timestamp":"2027-01-02T10:00:00Z","data":{"contentType":"profile","contentRef":"00000000-0000-4000-8000-0000000000f1","reportId":null}}'::jsonb),
  'applied', 'a content.remove on a profile is applied');
select is((select "quarantinedBy" from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f1'), 'msg_4', 'the profile is quarantined');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f1'), 0, 'a quarantined profile is its owner''s alone');
reset role;
select is(
  moderation.apply_event('msg_5', '{"type":"content.hide","timestamp":"2027-01-02T10:00:00Z","data":{"contentType":"session","contentRef":"not-a-uuid","reportId":null}}'::jsonb),
  'applied', 'content DogPack has no row for is acknowledged');

-- Atomic: when the change fails, the message is not recorded, so the retry applies.
create function tests.fail_ban() returns trigger language plpgsql as $f$ begin raise exception 'simulated failure'; end $f$;
create trigger fail_ban before update on auth.users for each row execute function tests.fail_ban();
select throws_ok(
  $$select moderation.apply_event('msg_6', '{"type":"user.ban","timestamp":"2027-01-03T10:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000002","reason":"harassment","reportId":null}}'::jsonb)$$,
  'P0001', 'simulated failure', 'a failing apply raises');
select is((select count(*)::int from moderation.events where "id" = 'msg_6'), 0, 'and leaves no record');
select is((select count(*)::int from moderation.user_states), 0, 'and no user state');
drop trigger fail_ban on auth.users;
select is(
  moderation.apply_event('msg_6', '{"type":"user.ban","timestamp":"2027-01-03T10:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000002","reason":"harassment","reportId":null}}'::jsonb),
  'applied', 'so the platform''s retry is applied, not ignored as a duplicate');

-- Bans: the classmate cannot sign in, holds no sessions, and every write is refused.
select cmp_ok((select banned_until from auth.users where id = '00000000-0000-4000-8000-0000000000f2'), '>', now() + interval '50 years', 'a ban sets banned_until far ahead');
select is((select state from moderation.user_states where "platformUserId" = 'aaaaaaaa-0000-4000-8000-000000000002'), 'banned', 'the state is recorded by platform user id');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('33333333-3333-4333-8333-333333333333')$$, '42501', null, 'a banned member cannot join a session');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity") values (202808, 'CSCI 1301', 'Banned host', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 4)$$, '42501', null, 'or host one');
select throws_ok($$update dogpack.profiles set "displayName" = 'Still here' where "userId" = '00000000-0000-4000-8000-0000000000f2'$$, '42501', null, 'or edit their profile');
reset role;
select is((select "displayName" from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f2'), 'Classmate', 'which stays as it was');
select throws_ok($$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000f2', 202808, 'MATH 2250')$$, 'PT403', 'account_restricted', 'or add a course');

-- A restore older than the ban is stale; a later one lifts it.
select is(
  moderation.apply_event('msg_7', '{"type":"user.restore","timestamp":"2027-01-03T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000002","reason":null,"reportId":null}}'::jsonb),
  'stale', 'a user.restore older than the ban is stale');
select isnt((select banned_until from auth.users where id = '00000000-0000-4000-8000-0000000000f2'), null, 'and the ban stands');
select is(
  moderation.apply_event('msg_8', '{"type":"user.restore","timestamp":"2027-01-04T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000002","reason":null,"reportId":null}}'::jsonb),
  'applied', 'a later user.restore is applied');
select is((select banned_until from auth.users where id = '00000000-0000-4000-8000-0000000000f2'), null, 'it lifts the ban');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
update dogpack.profiles set "displayName" = 'Back again' where "userId" = '00000000-0000-4000-8000-0000000000f2';
reset role;
select is((select "displayName" from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f2'), 'Back again', 'and the member can write again');

-- A suspension: the host's sessions and profile disappear for others, and their sign-in sessions die.
insert into auth.sessions (id, user_id) values ('44444444-4444-4444-8444-444444444444', '00000000-0000-4000-8000-0000000000f1');
select is(
  moderation.apply_event('msg_9', '{"type":"user.suspend","timestamp":"2027-01-05T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000001","reason":"spam","reportId":null}}'::jsonb),
  'applied', 'a user.suspend is applied');
select is((select count(*)::int from auth.sessions where user_id = '00000000-0000-4000-8000-0000000000f1'), 0, 'the suspended member''s sign-in sessions are revoked');
select tests.as_user('00000000-0000-4000-8000-0000000000f2');
select is((select count(*)::int from dogpack.sessions), 0, 'their sessions are hidden from others');
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f1'), 0, 'and so is their profile');
reset role;

-- A ban can arrive before the person has ever signed in; it bites when they do.
select is(
  moderation.apply_event('msg_10', '{"type":"user.ban","timestamp":"2027-01-06T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000003","reason":null,"reportId":null}}'::jsonb),
  'applied', 'a ban for a platform user DogPack has not seen is recorded');
insert into auth.users (id, email) values ('00000000-0000-4000-8000-0000000000f3', 'late@dogpack.devdogsuga.test');
insert into auth.identities (provider_id, user_id, identity_data, provider) values
  ('aaaaaaaa-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000f3', '{}', 'custom:devdogsuga');
select is(private.is_restricted('00000000-0000-4000-8000-0000000000f3'), true, 'and they are restricted from their first session');

-- Account deletion (user.delete): lock the account out, record 'deleted', and let
-- the auth user's deletion (the Edge Function's admin API call, simulated here
-- by a delete on auth.users) cascade through every DogPack table.
insert into auth.users (id, email) values ('00000000-0000-4000-8000-0000000000f4', 'leaving@dogpack.devdogsuga.test');
insert into auth.identities (provider_id, user_id, identity_data, provider) values
  ('aaaaaaaa-0000-4000-8000-000000000004', '00000000-0000-4000-8000-0000000000f4', '{}', 'custom:devdogsuga');
insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt")
  values ('00000000-0000-4000-8000-0000000000f4', 'Leaving', 'senior', 'CS', now());
insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000f4', 202808, 'CSCI 1301');
insert into dogpack.sessions ("id", "hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity") values
  ('66666666-6666-4666-8666-666666666666', '00000000-0000-4000-8000-0000000000f4', 202808, 'CSCI 1301', 'Leaving host', 'MLC', now() + interval '2 days', now() + interval '2 days 2 hours', 4);
insert into dogpack.session_members ("sessionId", "userId") values ('66666666-6666-4666-8666-666666666666', '00000000-0000-4000-8000-0000000000f2');
insert into dogpack.blocks ("blockerId", "blockedId") values
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f4'),
  ('00000000-0000-4000-8000-0000000000f4', '00000000-0000-4000-8000-0000000000f2');

select is(
  moderation.apply_event('msg_12', '{"type":"user.delete","timestamp":"2027-01-07T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000004","reason":"gone","reportId":null}}'::jsonb),
  'applied', 'a user.delete is applied');
select is((select state from moderation.user_states where "platformUserId" = 'aaaaaaaa-0000-4000-8000-000000000004'), 'deleted', 'the state is recorded as deleted');
select is((select reason from moderation.user_states where "platformUserId" = 'aaaaaaaa-0000-4000-8000-000000000004'), null, 'with no free-text reason kept');
select isnt((select banned_until from auth.users where id = '00000000-0000-4000-8000-0000000000f4'), null, 'and the account is locked out until the auth user is removed');

-- The admin API's deleteUser. Nothing in DogPack may block it.
delete from auth.users where id = '00000000-0000-4000-8000-0000000000f4';
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f4'), 0, 'deleting the auth user removes the profile');
select is((select count(*)::int from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000f4'), 0, 'the enrollments');
select is((select count(*)::int from dogpack.sessions where "hostId" = '00000000-0000-4000-8000-0000000000f4'), 0, 'the sessions they hosted');
select is((select count(*)::int from dogpack.session_members where "sessionId" = '66666666-6666-4666-8666-666666666666'), 0, 'with their rosters');
select is((select count(*)::int from dogpack.blocks where "blockerId" = '00000000-0000-4000-8000-0000000000f4' or "blockedId" = '00000000-0000-4000-8000-0000000000f4'), 0, 'blocks to and from them');
select is((select count(*)::int from private.onboarded_users where "userId" = '00000000-0000-4000-8000-0000000000f4'), 0, 'and the onboarding marker');
select is((select count(*)::int from auth.identities where user_id = '00000000-0000-4000-8000-0000000000f4'), 0, 'and their DevDogs identity');
select is((select "displayName" from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000f2'), 'Back again', 'other members'' data is untouched');
select is(
  moderation.apply_event('msg_12', '{"type":"user.delete","timestamp":"2027-01-07T09:00:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000004","reason":"gone","reportId":null}}'::jsonb),
  'duplicate', 'a replayed user.delete is a duplicate');
select is(
  moderation.apply_event('msg_13', '{"type":"user.delete","timestamp":"2027-01-07T09:05:00Z","data":{"userId":"aaaaaaaa-0000-4000-8000-000000000099","reason":null,"reportId":null}}'::jsonb),
  'applied', 'a user.delete for a platform user DogPack never had is acknowledged');

-- Malformed messages are refused, and leave no trace.
select throws_ok($$select moderation.apply_event('msg_11', '{"type":"content.explode","timestamp":"2027-01-06T09:00:00Z","data":{}}'::jsonb)$$, 'P0001', null, 'an unknown message type raises');
select is((select count(*)::int from moderation.events where "id" = 'msg_11'), 0, 'and is not recorded');

select * from finish();
rollback;
