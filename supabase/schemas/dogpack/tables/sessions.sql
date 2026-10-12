-- A study session a member hosts for one of their courses. `capacity` counts
-- every seat INCLUDING the host's: capacity 4 is the host and three others.
-- `memberCount` is the number of joined members (not the host), kept by
-- private.session_members_count() so a card can show seats without being
-- allowed to read the roster.
create table dogpack.sessions (
  "id"            uuid        primary key default gen_random_uuid(),
  "hostId"        uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  "term"          integer     not null,
  "course"        text        not null,
  "title"         text        not null,
  "description"   text        not null default '',
  "location"      text        not null,
  "startsAt"      timestamptz not null,
  "endsAt"        timestamptz not null,
  "capacity"      integer     not null,
  "memberCount"   integer     not null default 0,
  "status"        dogpack."sessionStatus" not null default 'scheduled',
  "cancelledAt"   timestamptz,
  -- Set by moderation.apply_event when a moderator hides the session. Row
  -- level security then shows the row to its host only.
  "quarantinedBy" text,
  "quarantinedAt" timestamptz,
  "createdAt"     timestamptz not null default now(),
  "updatedAt"     timestamptz not null default now(),
  constraint "sessions_term_format" check ("term" >= 200002 and "term" <= 299908 and "term" % 100 = any (array[2, 5, 8])),
  constraint "sessions_course_format" check ("course" ~ '^[A-Z]{4} [0-9]{4}[A-Z]?$'),
  constraint "sessions_title_length" check (char_length(btrim("title")) between 1 and 80),
  constraint "sessions_description_length" check (char_length("description") <= 1000),
  constraint "sessions_location_length" check (char_length(btrim("location")) between 1 and 120),
  constraint "sessions_time_order" check ("endsAt" > "startsAt" and "endsAt" - "startsAt" <= interval '12 hours'),
  constraint "sessions_capacity_range" check ("capacity" between 2 and 50),
  constraint "sessions_member_count_fits" check ("memberCount" >= 0 and "memberCount" + 1 <= "capacity"),
  constraint "sessions_cancelled_consistent" check (("status" = 'cancelled') = ("cancelledAt" is not null))
);

create index "sessions_discover_idx" on dogpack.sessions ("term", "course", "startsAt")
  where "status" = 'scheduled';
create index "sessions_host_idx" on dogpack.sessions ("hostId");

alter table dogpack.sessions enable row level security;

create policy "sessions_select" on dogpack.sessions
  for select to authenticated
  using (private.session_visible((select auth.uid()), sessions));

create policy "sessions_insert_own" on dogpack.sessions
  for insert to authenticated
  with check (
    "hostId" = (select auth.uid())
    and not private.is_restricted((select auth.uid()))
  );

create policy "sessions_update_own" on dogpack.sessions
  for update to authenticated
  using ("hostId" = (select auth.uid()) and "quarantinedBy" is null)
  with check (
    "hostId" = (select auth.uid())
    and not private.is_restricted((select auth.uid()))
  );

-- A client may choose the id, so a retry after a dropped connection is the same
-- insert and not a second session. No client delete: a host cancels, and the row stays for the members who
-- joined. dogpack.delete_my_data() removes a member's sessions.

revoke all on table dogpack.sessions from public, anon, authenticated;
grant select on table dogpack.sessions to authenticated;
grant insert ("id", "hostId", "term", "course", "title", "description", "location", "startsAt", "endsAt", "capacity")
  on table dogpack.sessions to authenticated;
grant update ("title", "description", "location", "startsAt", "endsAt", "capacity", "status")
  on table dogpack.sessions to authenticated;
grant select, insert, update, delete on table dogpack.sessions to service_role;

create trigger "sessions_guard_insert" before insert on dogpack.sessions
  for each row execute function private.sessions_guard_insert();
create trigger "sessions_guard_update" before update on dogpack.sessions
  for each row execute function private.sessions_guard_update();

comment on table dogpack.sessions is 'Study sessions. capacity includes the host''s seat; memberCount excludes it.';
