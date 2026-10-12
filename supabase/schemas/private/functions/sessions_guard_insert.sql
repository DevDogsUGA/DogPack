-- Creating a session: the host must have finished onboarding, be enrolled in
-- the session's course that term, and the session must be in the future. At
-- most ten upcoming sessions per host, so one account cannot flood Discover.
create function private.sessions_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from dogpack.profiles p
    where p."userId" = new."hostId" and p."onboardedAt" is not null
  ) then
    raise exception 'onboarding_required' using errcode = 'PT403';
  end if;
  if not private.is_enrolled(new."hostId", new."term", new."course") then
    raise exception 'not_enrolled' using errcode = 'PT403';
  end if;
  if new."startsAt" <= now() then
    raise exception 'starts_in_past' using errcode = 'PT422';
  end if;
  if (
    select count(*) from dogpack.sessions s
    where s."hostId" = new."hostId" and s."status" = 'scheduled' and s."endsAt" > now()
  ) >= 10 then
    raise exception 'too_many_sessions' using errcode = 'PT422';
  end if;

  -- A new session is scheduled, empty and unmoderated whatever the client sent.
  new."status" := 'scheduled';
  new."cancelledAt" := null;
  new."memberCount" := 0;
  new."quarantinedBy" := null;
  new."quarantinedAt" := null;
  return new;
end;
$$;

revoke all on function private.sessions_guard_insert() from public, anon, authenticated;
