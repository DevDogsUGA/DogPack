-- "Delete my data", and the guard that keeps every new table honest.
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

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000d1', 'leaver@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000d2', 'friend@dogpack.devdogsuga.test');
insert into auth.identities (provider_id, user_id, identity_data, provider) values
  ('bbbbbbbb-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000d1', '{}', 'custom:devdogsuga');
insert into dogpack.terms ("term", "description", "classesBegin", "classesEnd", "dropAddEnds")
  values (202808, 'Open term', current_date - 5, current_date + 90, current_date + 5);
insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt") values
  ('00000000-0000-4000-8000-0000000000d1', 'Leaver', 'senior', 'CS', now()),
  ('00000000-0000-4000-8000-0000000000d2', 'Friend', 'junior', 'CS', now());
insert into dogpack.enrollments ("userId", "term", "course") values
  ('00000000-0000-4000-8000-0000000000d1', 202808, 'CSCI 1301'),
  ('00000000-0000-4000-8000-0000000000d1', 202808, 'MATH 2250'),
  ('00000000-0000-4000-8000-0000000000d2', 202808, 'CSCI 1301');
-- Leaver hosts one session (Friend joined it) and joined one of Friend's.
insert into dogpack.sessions ("id", "hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity") values
  ('55555555-5555-4555-8555-555555555551', '00000000-0000-4000-8000-0000000000d1', 202808, 'CSCI 1301', 'Mine', 'MLC', now() + interval '1 day', now() + interval '1 day 1 hour', 4),
  ('55555555-5555-4555-8555-555555555552', '00000000-0000-4000-8000-0000000000d2', 202808, 'CSCI 1301', 'Theirs', 'MLC', now() + interval '2 days', now() + interval '2 days 1 hour', 4);
insert into dogpack.session_members ("sessionId", "userId") values
  ('55555555-5555-4555-8555-555555555551', '00000000-0000-4000-8000-0000000000d2'),
  ('55555555-5555-4555-8555-555555555552', '00000000-0000-4000-8000-0000000000d1');
insert into dogpack.blocks ("blockerId", "blockedId") values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d2'),
  ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000d1');
-- A ban against Leaver must survive the deletion.
select moderation.apply_event('msg_ban', '{"type":"user.ban","timestamp":"2027-01-01T00:00:00Z","data":{"userId":"bbbbbbbb-0000-4000-8000-000000000001","reason":null,"reportId":null}}'::jsonb);
update auth.users set banned_until = null where id = '00000000-0000-4000-8000-0000000000d1';

select plan(12);

select tests.as_user('00000000-0000-4000-8000-0000000000d1');
select is(dogpack.delete_my_data(), '{"blocks":2,"profiles":1,"sessions":1,"enrollments":2,"memberships":1}'::jsonb, 'delete_my_data reports what it removed');
reset role;

select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000d1'), 0, 'the profile is gone');
select is((select count(*)::int from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000d1'), 0, 'the enrollments are gone');
select is((select count(*)::int from dogpack.sessions where "hostId" = '00000000-0000-4000-8000-0000000000d1'), 0, 'the hosted session is gone');
select is((select count(*)::int from dogpack.session_members where "userId" = '00000000-0000-4000-8000-0000000000d1'), 0, 'the membership in a friend''s session is gone');
select is((select "memberCount" from dogpack.sessions where id = '55555555-5555-4555-8555-555555555552'), 0, 'and the friend''s seat count followed');
select is((select count(*)::int from dogpack.blocks), 0, 'blocks in both directions are gone');
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000d2'), 1, 'the friend''s own data is untouched');
select is((select state from moderation.user_states where "platformUserId" = 'bbbbbbbb-0000-4000-8000-000000000001'), 'banned', 'a ban is not lifted by deleting your data');
select is((select count(*)::int from auth.users where id = '00000000-0000-4000-8000-0000000000d1'), 1, 'the sign-in account itself is kept (account deletion is the Store Release milestone)');

-- Every table in the app's schemas has row level security on; a new table that
-- forgets it fails here, before review. (Its policies still need their own tests.)
select is(
  (select coalesce(string_agg(n.nspname || '.' || c.relname, ', ' order by c.relname), '')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('dogpack', 'moderation', 'private') and c.relkind = 'r' and not c.relrowsecurity),
  '', 'every table in dogpack, moderation and private has row level security enabled');

-- And nothing in them is readable by anon.
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema in ('dogpack', 'moderation', 'private') and grantee in ('anon', 'PUBLIC')),
  0, 'anon and PUBLIC hold no privilege on any table in them');

select * from finish();
rollback;
