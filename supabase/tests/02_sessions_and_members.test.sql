-- Sessions and joining: who creates, who sees, who edits, the capacity trigger
-- (the host counts as a seat), blocks.
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

-- host (h), two classmates (m1, m2), a member of a different course (x) and an
-- onboarding member (n).
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000e1', 'host@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000e2', 'm1@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000e3', 'm2@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000e4', 'x@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000e5', 'n@dogpack.devdogsuga.test');
insert into dogpack.terms ("term", "description", "classesBegin", "classesEnd", "dropAddEnds")
  values (202808, 'Open term', current_date - 5, current_date + 90, current_date + 5);
insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt") values
  ('00000000-0000-4000-8000-0000000000e1', 'Host', 'senior', 'CS', now()),
  ('00000000-0000-4000-8000-0000000000e2', 'Mia', 'junior', 'CS', now()),
  ('00000000-0000-4000-8000-0000000000e3', 'Max', 'junior', 'CS', now()),
  ('00000000-0000-4000-8000-0000000000e4', 'Xan', 'junior', 'Art', now());
insert into dogpack.profiles ("userId", "displayName", "classYear") values
  ('00000000-0000-4000-8000-0000000000e5', 'Nia', 'junior');
insert into dogpack.enrollments ("userId", "term", "course") values
  ('00000000-0000-4000-8000-0000000000e1', 202808, 'CSCI 1301'),
  ('00000000-0000-4000-8000-0000000000e2', 202808, 'CSCI 1301'),
  ('00000000-0000-4000-8000-0000000000e3', 202808, 'CSCI 1301'),
  ('00000000-0000-4000-8000-0000000000e4', 202808, 'ARTS 1100'),
  ('00000000-0000-4000-8000-0000000000e5', 202808, 'CSCI 1301');

select plan(48);

-- Creating a session.
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
insert into dogpack.sessions ("id", "term", "course", "title", "location", "startsAt", "endsAt", "capacity")
  values ('11111111-1111-4111-8111-111111111111', 202808, 'CSCI 1301', 'Loops review', 'MLC 3rd floor', now() + interval '1 day', now() + interval '1 day 2 hours', 3);
select pass('an onboarded member creates a session for a course they take');
select is((select "hostId" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), '00000000-0000-4000-8000-0000000000e1'::uuid, 'hostId defaults to the caller');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity") values (202808, 'ARTS 1100', 'Nope', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 4)$$,
  'PT403', 'not_enrolled', 'a session needs a course the host takes');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity") values (202808, 'CSCI 1301', 'Past', 'x', now() - interval '1 hour', now() + interval '1 hour', 4)$$,
  'PT422', 'starts_in_past', 'a session cannot start in the past');
select throws_ok($$insert into dogpack.sessions ("hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity") values ('00000000-0000-4000-8000-0000000000e2', 202808, 'CSCI 1301', 'Forged', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 4)$$,
  '42501', null, 'a member cannot host as someone else');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity") values (202808, 'CSCI 1301', 'Solo', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 1)$$,
  '23514', null, 'capacity is at least two seats (the host and one more)');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity", "memberCount") values (202808, 'CSCI 1301', 'Cheat', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 4, 3)$$,
  '42501', null, 'memberCount is not writable by a member');
reset role;

-- Not onboarded: no sessions.
select tests.as_user('00000000-0000-4000-8000-0000000000e5');
select throws_ok($$insert into dogpack.sessions ("term", "course", "title", "location", "startsAt", "endsAt", "capacity") values (202808, 'CSCI 1301', 'Early', 'x', now() + interval '1 day', now() + interval '1 day 1 hour', 4)$$,
  'PT403', 'onboarding_required', 'a member who has not finished onboarding cannot host');
reset role;

-- Not onboarded: the session is not discoverable and cannot be joined, even
-- though they are enrolled in the course (a late course added under the
-- onboarding exception must not open sessions).
select tests.as_user('00000000-0000-4000-8000-0000000000e5');
select is((select count(*)::int from dogpack.sessions), 0, 'a member who has not finished onboarding does not see the session');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$,
  'PT403', 'onboarding_required', 'a member who has not finished onboarding cannot join');
reset role;
select is((select count(*)::int from dogpack.session_members where "userId" = '00000000-0000-4000-8000-0000000000e5'), 0, 'and no membership row exists');

-- Who sees it.
select tests.as_user('00000000-0000-4000-8000-0000000000e2');
select is((select count(*)::int from dogpack.sessions), 1, 'a classmate sees the session');
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000e1'), 1, 'and the host''s profile through it');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e4');
select is((select count(*)::int from dogpack.sessions), 0, 'a member of another course does not see it');
select is((select count(*)::int from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000e1'), 0, 'nor the host''s profile');
reset role;

-- Capacity 3 = host + two members. The host holds a seat.
select tests.as_user('00000000-0000-4000-8000-0000000000e2');
insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111');
select pass('the first classmate joins');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$, '23505', null, 'joining twice is a duplicate key');
select throws_ok($$insert into dogpack.session_members ("sessionId", "userId") values ('11111111-1111-4111-8111-111111111111', '00000000-0000-4000-8000-0000000000e3')$$, '42501', null, 'a member cannot enrol another member in a session');
-- A forged userId is refused before the guard says anything about the session or
-- the other member: not onboarding_required, not_enrolled or session_unavailable.
select throws_ok($$insert into dogpack.session_members ("sessionId", "userId") values ('11111111-1111-4111-8111-111111111111', '00000000-0000-4000-8000-0000000000e5')$$, '42501', null, 'a forged userId for a member who has not onboarded gets 42501, not onboarding_required');
select throws_ok($$insert into dogpack.session_members ("sessionId", "userId") values ('11111111-1111-4111-8111-111111111111', '00000000-0000-4000-8000-0000000000e4')$$, '42501', null, 'a forged userId for a member of another course gets 42501, not not_enrolled');
select throws_ok($$insert into dogpack.session_members ("sessionId", "userId") values ('99999999-9999-4999-8999-999999999999', '00000000-0000-4000-8000-0000000000e3')$$, '42501', null, 'and a forged userId on a session that does not exist gets 42501, not session_unavailable');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e4');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$, 'PT403', 'not_enrolled', 'a member of another course cannot join');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$, 'PT409', 'host_cannot_join', 'the host does not join their own session');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e3');
insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111');
select pass('the second classmate takes the last seat');
select is((select "memberCount" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 2, 'memberCount counts the two members, not the host');
reset role;
-- A third, otherwise eligible, member finds it full.
insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000e4', 202808, 'CSCI 1301');
select tests.as_user('00000000-0000-4000-8000-0000000000e4');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$, 'PT409', 'session_full', 'host + 2 members fill capacity 3: the next join is session_full');
reset role;

-- Leaving frees the seat.
select tests.as_user('00000000-0000-4000-8000-0000000000e3');
delete from dogpack.session_members where "sessionId" = '11111111-1111-4111-8111-111111111111';
reset role;
select is((select "memberCount" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 1, 'leaving lowers memberCount');
select tests.as_user('00000000-0000-4000-8000-0000000000e4');
insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111');
select pass('and the freed seat can be taken');
reset role;

-- A member cannot remove someone else.
select tests.as_user('00000000-0000-4000-8000-0000000000e2');
delete from dogpack.session_members where "userId" = '00000000-0000-4000-8000-0000000000e4';
reset role;
select is((select count(*)::int from dogpack.session_members where "userId" = '00000000-0000-4000-8000-0000000000e4'), 1, 'nor remove another member (the delete matched nothing)');

-- The roster: members and the host see it; a classmate who has not joined does not.
select tests.as_user('00000000-0000-4000-8000-0000000000e5');
select is((select count(*)::int from dogpack.session_members), 0, 'a classmate who has not joined cannot read the roster');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
select is((select count(*)::int from dogpack.session_members), 2, 'the host reads the roster');
select is((select count(*)::int from dogpack.profiles), 3, 'and sees the profiles of the members who joined, besides their own');
reset role;

-- Editing.
select tests.as_user('00000000-0000-4000-8000-0000000000e2');
update dogpack.sessions set "title" = 'Hijacked' where id = '11111111-1111-4111-8111-111111111111';
reset role;
select is((select "title" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 'Loops review', 'a member cannot edit someone else''s session');
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
update dogpack.sessions set "title" = 'Loops and arrays', "location" = 'Zoom' where id = '11111111-1111-4111-8111-111111111111';
select is((select "title" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 'Loops and arrays', 'the host edits their session');
select throws_ok($$update dogpack.sessions set "capacity" = 2 where id = '11111111-1111-4111-8111-111111111111'$$, 'PT422', 'capacity_below_members', 'capacity cannot drop below the seats taken');
select throws_ok($$update dogpack.sessions set "course" = 'MATH 2250' where id = '11111111-1111-4111-8111-111111111111'$$, '42501', null, 'the course cannot be changed');
select throws_ok($$update dogpack.sessions set "memberCount" = 0 where id = '11111111-1111-4111-8111-111111111111'$$, '42501', null, 'memberCount cannot be edited');
update dogpack.sessions set "capacity" = 5 where id = '11111111-1111-4111-8111-111111111111';
select is((select "capacity" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 5, 'capacity can grow');

-- Cancelling keeps the row for the people who joined.
update dogpack.sessions set "status" = 'cancelled' where id = '11111111-1111-4111-8111-111111111111';
select isnt((select "cancelledAt" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), null, 'cancelling stamps cancelledAt');
select throws_ok($$update dogpack.sessions set "title" = 'Again' where id = '11111111-1111-4111-8111-111111111111'$$, 'PT409', 'session_cancelled', 'a cancelled session is final');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e2');
select is((select "status"::text from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 'cancelled', 'a member who joined still sees the cancelled session');
delete from dogpack.session_members where "userId" = '00000000-0000-4000-8000-0000000000e2';
reset role;
select is((select "memberCount" from dogpack.sessions where id = '11111111-1111-4111-8111-111111111111'), 1, 'and can leave it');
select tests.as_user('00000000-0000-4000-8000-0000000000e3');
select is((select count(*)::int from dogpack.sessions), 0, 'a classmate who never joined no longer sees it');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('11111111-1111-4111-8111-111111111111')$$, 'PT409', 'session_closed', 'and cannot join a cancelled session');
reset role;

-- Blocks.
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
insert into dogpack.sessions ("id", "term", "course", "title", "location", "startsAt", "endsAt", "capacity")
  values ('22222222-2222-4222-8222-222222222222', 202808, 'CSCI 1301', 'Second', 'Library', now() + interval '2 days', now() + interval '2 days 1 hour', 4);
reset role;
-- service_role (the platform's own code) may add a member on their behalf.
set local role service_role;
insert into dogpack.session_members ("sessionId", "userId") values ('22222222-2222-4222-8222-222222222222', '00000000-0000-4000-8000-0000000000e2');
reset role;
select is((select count(*)::int from dogpack.session_members where "sessionId" = '22222222-2222-4222-8222-222222222222' and "userId" = '00000000-0000-4000-8000-0000000000e2'), 1, 'service_role can add a member with an explicit userId');
select tests.as_user('00000000-0000-4000-8000-0000000000e3');
insert into dogpack.blocks ("blockedId") values ('00000000-0000-4000-8000-0000000000e1');
select is((select count(*)::int from dogpack.sessions), 0, 'blocking a host hides their sessions from the blocker');
select throws_ok($$insert into dogpack.session_members ("sessionId") values ('22222222-2222-4222-8222-222222222222')$$, 'PT404', 'session_unavailable', 'and refuses the blocker''s join');
reset role;
select tests.as_user('00000000-0000-4000-8000-0000000000e1');
select is((select count(*)::int from dogpack.blocks), 0, 'the person blocked cannot see the block');
reset role;

select * from finish();
rollback;
