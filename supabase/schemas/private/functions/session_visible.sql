-- May this viewer see this session? The host always sees their own, even a
-- quarantined one ("hidden from everyone but its author"). Everyone else sees
-- it unless it is quarantined, its host is suspended or banned, or either side
-- blocked the other; then a member who joined keeps seeing it (including after
-- a cancel), and a member enrolled in its course sees it while it is upcoming,
-- provided they finished onboarding (the same check hosting and joining use, so
-- courses added under the one-time onboarding exception expose no sessions).
create function private.session_visible(p_viewer uuid, p_session dogpack.sessions)
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
  if p_session."hostId" = p_viewer then
    return true;
  end if;
  if p_session."quarantinedBy" is not null then
    return false;
  end if;
  if private.is_restricted(p_session."hostId")
     or private.is_blocked_between(p_viewer, p_session."hostId") then
    return false;
  end if;
  if private.is_session_member(p_session."id", p_viewer) then
    return true;
  end if;
  return p_session."status" = 'scheduled'
    and p_session."endsAt" > now()
    and private.is_onboarded(p_viewer)
    and private.is_enrolled(p_viewer, p_session."term", p_session."course");
end;
$$;

revoke all on function private.session_visible(uuid, dogpack.sessions) from public, anon;
grant execute on function private.session_visible(uuid, dogpack.sessions) to authenticated, service_role;
