-- The courses a member is taking in a term, keyed by course code (not CRN):
-- `CSCI 1301`. Students re-enter their courses each term.
--
-- Members cannot insert. The `enroll` Edge Function does, after it has asked
-- the catalog whether the course exists and is offered that term, so
-- `catalogVerified` says whether that check really ran or the catalog was down
-- and only the format was checked (the documented fallback). The add/drop
-- deadline is enforced here, by private.enrollments_guard(), whoever inserts:
-- no adding after the term's full-term drop/add end, except the one-time
-- initial enrollment while a member is still onboarding.
create table dogpack.enrollments (
  "id"              uuid        primary key default gen_random_uuid(),
  "userId"          uuid        not null references auth.users (id) on delete cascade,
  "term"            integer     not null,
  "course"          text        not null,
  "catalogVerified" boolean     not null default false,
  "createdAt"       timestamptz not null default now(),
  constraint "enrollments_term_format" check ("term" >= 200002 and "term" <= 299908 and "term" % 100 = any (array[2, 5, 8])),
  constraint "enrollments_course_format" check ("course" ~ '^[A-Z]{4} [0-9]{4}[A-Z]?$'),
  constraint "enrollments_unique" unique ("userId", "term", "course")
);

create index "enrollments_course_idx" on dogpack.enrollments ("term", "course");

alter table dogpack.enrollments enable row level security;

create policy "enrollments_select_own" on dogpack.enrollments
  for select to authenticated
  using ("userId" = (select auth.uid()));

-- Dropping a course is always allowed; only adding is under the deadline.
create policy "enrollments_delete_own" on dogpack.enrollments
  for delete to authenticated
  using ("userId" = (select auth.uid()));

revoke all on table dogpack.enrollments from public, anon, authenticated;
grant select, delete on table dogpack.enrollments to authenticated;
grant select, insert, update, delete on table dogpack.enrollments to service_role;

create trigger "enrollments_guard" before insert on dogpack.enrollments
  for each row execute function private.enrollments_guard();

comment on table dogpack.enrollments is 'Courses a member takes in a term. Inserted only by the enroll function; the deadline rule is a trigger.';
