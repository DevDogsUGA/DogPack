-- Profiles, onboarding and enrollments: the allow and the deny of each policy,
-- the add/drop deadline rule, and the one-time initial-enrollment exception.
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
create function tests.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;
grant execute on function tests.as_anon() to public;

-- Two members: alice finished onboarding, bob is mid-onboarding.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'alice@dogpack.devdogsuga.test'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@dogpack.devdogsuga.test');

-- Terms: an open one (deadline ahead), a closed one (deadline passed, term not
-- over), a finished one.
insert into dogpack.terms ("term", "description", "classesBegin", "classesEnd", "dropAddEnds") values
  (202808, 'Open term', current_date - 5, current_date + 90, current_date + 5),
  (202708, 'Closed term', current_date - 40, current_date + 60, current_date - 30),
  (202605, 'Finished term', current_date - 200, current_date - 100, current_date - 190);

insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt") values
  ('00000000-0000-4000-8000-0000000000a1', 'Alice', 'junior', 'Computer Science', now());
insert into dogpack.profiles ("userId", "displayName", "classYear") values
  ('00000000-0000-4000-8000-0000000000b1', 'Bob', 'sophomore');

select plan(31);

-- Anonymous visitors see nothing and write nothing.
select tests.as_anon();
select throws_ok($$select * from dogpack.profiles$$, '42501', null, 'anon cannot read profiles');
select throws_ok($$select * from dogpack.enrollments$$, '42501', null, 'anon cannot read enrollments');
select throws_ok($$select * from dogpack.terms$$, '42501', null, 'anon cannot read terms');
reset role;

-- Terms: a member reads them, cannot write them.
select tests.as_user('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from dogpack.terms), 3, 'a member reads the cached terms');
select throws_ok($$insert into dogpack.terms ("term", "description") values (202602, 'x')$$, '42501', null, 'a member cannot write terms');

-- Enrollments are not inserted by members at all (the enroll function does it).
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202808, 'CSCI 1301')$$,
  '42501', null, 'a member cannot insert an enrollment directly');
reset role;

-- The service role inserts; the trigger holds the rule whoever inserts.
insert into dogpack.enrollments ("userId", "term", "course", "catalogVerified") values
  ('00000000-0000-4000-8000-0000000000a1', 202808, 'CSCI 1301', true);
select pass('before the deadline an onboarded member can add a course');

select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202708, 'MATH 2250')$$,
  'PT403', 'enrollment_closed', 'after the term''s drop/add end an onboarded member cannot add a course');
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202605, 'MATH 2250')$$,
  'PT422', 'term_over', 'a finished term takes no enrollments');
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202902, 'MATH 2250')$$,
  'PT422', 'unknown_term', 'an onboarded member cannot add to a term the catalog never listed');
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202808, 'csci1301')$$,
  '23514', null, 'the course code format is checked');
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000a1', 202808, 'CSCI 1301')$$,
  '23505', null, 'a course is entered once per term');

-- The one-time initial enrollment: Bob is still onboarding, so the closed term
-- takes his courses, and so does a term the cache does not know.
insert into dogpack.enrollments ("userId", "term", "course") values
  ('00000000-0000-4000-8000-0000000000b1', 202708, 'MATH 2250');
select pass('a member who is still onboarding can add a course after the deadline');
insert into dogpack.enrollments ("userId", "term", "course") values
  ('00000000-0000-4000-8000-0000000000b1', 202902, 'MATH 2250');
select pass('and to a term the catalog cache does not know (the catalog-down fallback)');
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000b1', 202605, 'MATH 2250')$$,
  'PT422', 'term_over', 'but not to a term that is over');

-- Twelve courses a term at most.
insert into dogpack.enrollments ("userId", "term", "course")
  select '00000000-0000-4000-8000-0000000000b1', 202808, 'CSCI ' || (2000 + g)::text from generate_series(1, 12) g;
select throws_ok(
  $$insert into dogpack.enrollments ("userId", "term", "course") values ('00000000-0000-4000-8000-0000000000b1', 202808, 'CSCI 3000')$$,
  'PT422', 'too_many_courses', 'a thirteenth course in a term is refused');

-- Reading and dropping: own rows only.
select tests.as_user('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from dogpack.enrollments), 1, 'a member sees only their own enrollments');
select is((select count(*)::int from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000b1'), 0, 'and none of another member''s');
delete from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000b1';
reset role;
select is((select count(*)::int from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000b1'), 14, 'a member cannot drop another member''s course (the delete matched no row)');
select tests.as_user('00000000-0000-4000-8000-0000000000a1');
delete from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000a1' and "term" = 202808;
reset role;
select is((select count(*)::int from dogpack.enrollments where "userId" = '00000000-0000-4000-8000-0000000000a1'), 0, 'a member can drop their own course, even past the deadline');

-- Profiles: write your own, and only the columns you may.
select tests.as_user('00000000-0000-4000-8000-0000000000b1');
update dogpack.profiles set "major" = 'Math', "displayName" = 'Bobby' where "userId" = '00000000-0000-4000-8000-0000000000b1';
select is((select "major" from dogpack.profiles where "userId" = '00000000-0000-4000-8000-0000000000b1'), 'Math', 'a member edits their own profile');
select throws_ok($$update dogpack.profiles set "onboardedAt" = now() where "userId" = '00000000-0000-4000-8000-0000000000b1'$$, '42501', null, 'a member cannot stamp onboardedAt themselves');
select throws_ok($$update dogpack.profiles set "quarantinedBy" = null where "userId" = '00000000-0000-4000-8000-0000000000b1'$$, '42501', null, 'a member cannot touch quarantinedBy');
select throws_ok($$insert into dogpack.profiles ("userId", "displayName", "classYear") values ('00000000-0000-4000-8000-0000000000a1', 'Evil', 'senior')$$, '42501', null, 'a member cannot create a profile for someone else');
select is((select count(*)::int from dogpack.profiles), 1, 'a member sees only their own profile when they share no session');
select throws_ok($$delete from dogpack.profiles$$, '42501', null, 'a member cannot delete a profile row (delete_my_data does it)');
reset role;

-- complete_onboarding: needs a major and a course, and is idempotent.
select tests.as_user('00000000-0000-4000-8000-0000000000b1');
select is((select dogpack.complete_onboarding() is not null), true, 'a profile with a major and a course completes onboarding');
select is((select dogpack.complete_onboarding() = dogpack.complete_onboarding()), true, 'completing twice keeps the first time');
reset role;
insert into auth.users (id, email) values ('00000000-0000-4000-8000-0000000000c1', 'cara@dogpack.devdogsuga.test');
insert into dogpack.profiles ("userId", "displayName", "classYear") values ('00000000-0000-4000-8000-0000000000c1', 'Cara', 'senior');
select tests.as_user('00000000-0000-4000-8000-0000000000c1');
select throws_ok($$select dogpack.complete_onboarding()$$, 'PT422', 'profile_incomplete', 'onboarding needs a major');
reset role;
update dogpack.profiles set "major" = 'Art' where "userId" = '00000000-0000-4000-8000-0000000000c1';
select tests.as_user('00000000-0000-4000-8000-0000000000c1');
select throws_ok($$select dogpack.complete_onboarding()$$, 'PT422', 'no_courses', 'and at least one course');
reset role;
select tests.as_anon();
select throws_ok($$select dogpack.complete_onboarding()$$, '42501', null, 'anon cannot call it');

select * from finish();
rollback;
