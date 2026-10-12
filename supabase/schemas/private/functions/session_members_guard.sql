-- Joining a session: the capacity trigger. It locks the session row, so two
-- joins for the last seat run one after the other, counts the members, and
-- raises `session_full` (PT409) when the host plus the members fill capacity.
-- The host counts as a seat, which is why the test is `1 + count >= capacity`.
--
-- It is SECURITY DEFINER because locking a row for update needs the update
-- policy, which only the host passes.
create function private.session_members_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session dogpack.sessions%rowtype;
  v_taken integer;
begin
  select * into v_session from dogpack.sessions s where s."id" = new."sessionId" for update;

  -- A session the joiner could not see is a session that does not exist.
  if not found
     or v_session."quarantinedBy" is not null
     or private.is_restricted(v_session."hostId")
     or private.is_blocked_between(new."userId", v_session."hostId") then
    raise exception 'session_unavailable' using errcode = 'PT404';
  end if;
  if v_session."hostId" = new."userId" then
    raise exception 'host_cannot_join' using errcode = 'PT409';
  end if;
  if v_session."status" <> 'scheduled' or v_session."endsAt" <= now() then
    raise exception 'session_closed' using errcode = 'PT409';
  end if;
  if not private.is_enrolled(new."userId", v_session."term", v_session."course") then
    raise exception 'not_enrolled' using errcode = 'PT403';
  end if;

  select count(*) into v_taken from dogpack.session_members m where m."sessionId" = new."sessionId";
  if 1 + v_taken >= v_session."capacity" then
    raise exception 'session_full' using errcode = 'PT409';
  end if;

  return new;
end;
$$;

revoke all on function private.session_members_guard() from public, anon, authenticated;
