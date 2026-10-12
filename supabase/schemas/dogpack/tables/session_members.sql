-- Who joined a session (the host is not a row here: the host holds a seat by
-- hosting). Joining is a plain insert. The BEFORE INSERT trigger locks the
-- session row, counts, and raises `session_full` (SQLSTATE PT409) when the
-- host plus the members already fill `capacity`, so two people racing for
-- the last seat cannot both get it.
create table dogpack.session_members (
  "sessionId" uuid        not null references dogpack.sessions (id) on delete cascade,
  "userId"    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  "joinedAt"  timestamptz not null default now(),
  primary key ("sessionId", "userId")
);

create index "session_members_user_idx" on dogpack.session_members ("userId");

alter table dogpack.session_members enable row level security;

create policy "session_members_select" on dogpack.session_members
  for select to authenticated
  using (
    "userId" = (select auth.uid())
    or private.is_session_host("sessionId", (select auth.uid()))
    or private.is_session_member("sessionId", (select auth.uid()))
  );

create policy "session_members_insert_own" on dogpack.session_members
  for insert to authenticated
  with check (
    "userId" = (select auth.uid())
    and not private.is_restricted((select auth.uid()))
  );

-- Leaving is a delete of your own row.
create policy "session_members_delete_own" on dogpack.session_members
  for delete to authenticated
  using ("userId" = (select auth.uid()));

revoke all on table dogpack.session_members from public, anon, authenticated;
grant select, delete on table dogpack.session_members to authenticated;
grant insert ("sessionId", "userId") on table dogpack.session_members to authenticated;
grant select, insert, update, delete on table dogpack.session_members to service_role;

create trigger "session_members_guard" before insert on dogpack.session_members
  for each row execute function private.session_members_guard();
create trigger "session_members_count" after insert or delete on dogpack.session_members
  for each row execute function private.session_members_count();

comment on table dogpack.session_members is 'Members who joined a session. The host is not a row; the capacity trigger counts the host as a seat.';
