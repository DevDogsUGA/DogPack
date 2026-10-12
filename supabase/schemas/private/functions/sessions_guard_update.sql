-- Editing and cancelling. The course and term are fixed once a session exists
-- (members joined for that course), a cancelled session cannot be edited, and
-- capacity cannot drop below the seats already taken. Cancelling stamps
-- cancelledAt. Only the columns a host may change are granted to clients;
-- this guards the rules the grants cannot express.
--
-- SECURITY INVOKER on purpose: it applies to a member's own update
-- (current_user is `authenticated`) and stands aside for the privileged paths
-- that also update this table (moderation.apply_event quarantining a session,
-- the member counter, delete-my-data), which run as their owner.
create function private.sessions_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new."term" <> old."term" or new."course" <> old."course" or new."hostId" <> old."hostId" then
    raise exception 'immutable_column' using errcode = 'PT422';
  end if;
  if old."status" = 'cancelled' then
    raise exception 'session_cancelled' using errcode = 'PT409';
  end if;
  if new."endsAt" <= now() and new."status" = 'scheduled' then
    raise exception 'session_over' using errcode = 'PT409';
  end if;
  if new."capacity" < 1 + old."memberCount" then
    raise exception 'capacity_below_members' using errcode = 'PT422';
  end if;
  if new."startsAt" <> old."startsAt" and new."startsAt" <= now() then
    raise exception 'starts_in_past' using errcode = 'PT422';
  end if;

  if new."status" = 'cancelled' then
    new."cancelledAt" := now();
  end if;

  -- Whatever the client sent for these, they stay as they were.
  new."memberCount" := old."memberCount";
  new."quarantinedBy" := old."quarantinedBy";
  new."quarantinedAt" := old."quarantinedAt";
  return new;
end;
$$;

revoke all on function private.sessions_guard_update() from public, anon, authenticated;
