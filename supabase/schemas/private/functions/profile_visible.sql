-- May this viewer see this member's profile? Only through a session: the
-- member hosts a session the viewer can see, or the member joined a session the
-- viewer hosts or also joined. Not if either blocked the other, and not if the
-- member is suspended or banned.
create function private.profile_visible(p_viewer uuid, p_owner uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_viewer is null then
    return false;
  end if;
  if p_viewer = p_owner then
    return true;
  end if;
  if private.is_blocked_between(p_viewer, p_owner) or private.is_restricted(p_owner) then
    return false;
  end if;
  return exists (
      select 1 from dogpack.sessions s
      where s."hostId" = p_owner and private.session_visible(p_viewer, s)
    )
    or exists (
      select 1
      from dogpack.session_members m
      join dogpack.sessions s on s."id" = m."sessionId"
      where m."userId" = p_owner
        and s."quarantinedBy" is null
        and (s."hostId" = p_viewer or private.is_session_member(s."id", p_viewer))
    );
end;
$$;

revoke all on function private.profile_visible(uuid, uuid) from public, anon;
grant execute on function private.profile_visible(uuid, uuid) to authenticated, service_role;
