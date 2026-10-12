-- Fake study-group data for a development database. Run it with
--
--   npx @devdogsuga/devtools@next dev-data
--
-- after you have signed in to the app once. devtools runs this file in one
-- transaction as the postgres role, on the local stack or your own project
-- only (it refuses DogPack's production project), and sets
--
--   devtools.member_id   the auth.users id of the member who signed in last
--
-- Re-running is safe: the fake members (@devdata.dogpack.devdogsuga.test) are
-- removed first, and their sessions go with them.
--
-- What you get, for up to three of your courses in your latest term:
--   * an open session with seats left (a classmate hosts it)
--   * a full session (host plus two members, capacity 3)
--   * a session that ended yesterday
--   * a session you host, and one you have joined (once you are onboarded)
-- If you have no courses yet, you are enrolled in three so there is something
-- to show. Hosting and joining need a finished onboarding; until then you only
-- see the classmates' sessions.
do $$
declare
  v_member uuid := current_setting('devtools.member_id')::uuid;
  v_term integer;
  v_courses text[];
  v_default_courses text[] := array['CSCI 1301', 'MATH 2250', 'ENGL 1102'];
  v_hosts uuid[] := array[
    '00000000-0000-4000-8000-00000000d001',
    '00000000-0000-4000-8000-00000000d002',
    '00000000-0000-4000-8000-00000000d003',
    '00000000-0000-4000-8000-00000000d004'
  ];
  v_names text[] := array['Ava Chen', 'Marcus Reed', 'Priya Nair', 'Jordan Ellis'];
  v_years text[] := array['sophomore', 'junior', 'senior', 'freshman'];
  v_course text;
  v_session uuid;
  v_day date := (now() at time zone 'America/New_York')::date;
  i integer;
  n integer := 0;
begin
  if not exists (select 1 from auth.users where id = v_member) then
    raise exception 'devtools.member_id % is not a user in this database', v_member;
  end if;

  -- Last run's fake members, and with them their profiles, enrollments,
  -- sessions and memberships.
  delete from auth.users where email like '%@devdata.dogpack.devdogsuga.test';
  -- ...and the one session it gave you to host.
  delete from dogpack.sessions where "hostId" = v_member and "description" = 'Seeded by dev-data.';

  select e."term" into v_term
    from dogpack.enrollments e where e."userId" = v_member
    order by e."term" desc limit 1;
  if v_term is null then
    v_term := extract(year from v_day)::integer * 100 + case
      when extract(month from v_day) <= 5 then 2
      when extract(month from v_day) <= 7 then 5
      else 8 end;
    insert into dogpack.profiles ("userId", "displayName", "classYear")
      values (v_member, 'Dev Member', 'junior')
      on conflict ("userId") do nothing;
    insert into dogpack.enrollments ("userId", "term", "course")
      select v_member, v_term, c from unnest(v_default_courses) c
      on conflict do nothing;
  end if;

  select array_agg(course order by course) into v_courses from (
    select e."course" from dogpack.enrollments e
    where e."userId" = v_member and e."term" = v_term
    order by e."course" limit 3
  ) c;

  -- Four classmates, enrolled in the member's courses. Enrollment comes before
  -- onboardedAt on purpose: the deadline rule lets a member who is still
  -- onboarding add their first courses.
  for i in 1..4 loop
    insert into auth.users (id, email)
      values (v_hosts[i], 'host' || i || '@devdata.dogpack.devdogsuga.test');
    insert into dogpack.profiles ("userId", "displayName", "classYear", "major")
      values (v_hosts[i], v_names[i], v_years[i]::dogpack."classYear", 'Computer Science');
    insert into dogpack.enrollments ("userId", "term", "course")
      select v_hosts[i], v_term, c from unnest(v_courses) c;
    update dogpack.profiles set "onboardedAt" = now() where "userId" = v_hosts[i];
  end loop;

  foreach v_course in array v_courses loop
    n := n + 1;

    -- Open: three seats of six taken.
    insert into dogpack.sessions ("hostId", "term", "course", "title", "description", "location", "startsAt", "endsAt", "capacity")
      values (v_hosts[1], v_term, v_course, v_course || ' problem set review',
              'Bring your questions; we will work through the set together.',
              'Main Library, 3rd floor study room ' || n,
              now() + make_interval(days => n, hours => 2), now() + make_interval(days => n, hours => 4), 6)
      returning "id" into v_session;
    insert into dogpack.session_members ("sessionId", "userId") values (v_session, v_hosts[2]), (v_session, v_hosts[3]);

    -- Full: the host and two members fill all three seats.
    insert into dogpack.sessions ("hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity")
      values (v_hosts[2], v_term, v_course, v_course || ' exam cram', 'Miller Learning Center, room ' || (100 + n),
              now() + make_interval(days => n + 1, hours => 5), now() + make_interval(days => n + 1, hours => 7), 3)
      returning "id" into v_session;
    insert into dogpack.session_members ("sessionId", "userId") values (v_session, v_hosts[3]), (v_session, v_hosts[4]);

    -- Past: ended yesterday. A new session cannot start in the past, so it is
    -- moved there afterwards (this file runs as postgres, which the guard allows).
    insert into dogpack.sessions ("hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity")
      values (v_hosts[1], v_term, v_course, v_course || ' homework help', 'Zell B. Miller Learning Center lobby',
              now() + interval '1 day', now() + interval '1 day 2 hours', 5)
      returning "id" into v_session;
    insert into dogpack.session_members ("sessionId", "userId") values (v_session, v_hosts[4]);
    update dogpack.sessions
       set "startsAt" = now() - interval '1 day 2 hours', "endsAt" = now() - interval '1 day'
     where "id" = v_session;
  end loop;

  -- The member hosts one session and joins one, once they are onboarded (a
  -- member who is not cannot host).
  if not exists (select 1 from dogpack.profiles p where p."userId" = v_member and p."onboardedAt" is not null) then
    raise notice 'You have not finished onboarding, so you host and join nothing yet. Run dev-data again afterwards.';
    return;
  end if;
  insert into dogpack.sessions ("hostId", "term", "course", "title", "description", "location", "startsAt", "endsAt", "capacity")
    values (v_member, v_term, v_courses[1], v_courses[1] || ' study group', 'Seeded by dev-data.',
            'Tate Student Center, second floor', now() + interval '3 days 1 hour', now() + interval '3 days 3 hours', 5);
  insert into dogpack.session_members ("sessionId", "userId")
    select s."id", v_member from dogpack.sessions s
    where s."hostId" = v_hosts[1] and s."course" = v_courses[1] and s."status" = 'scheduled' and s."endsAt" > now()
    order by s."startsAt" limit 1;
end $$;
