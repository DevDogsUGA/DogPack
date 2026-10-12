-- Has this member finished onboarding? The one marker hosting, joining and
-- discovering a session all read: the profile's onboardedAt. delete_my_data
-- removes the profile, so a member who deleted their data onboards again before
-- they host, join or discover anything. (private.onboarded_users is a different
-- fact, "has ever onboarded", and only enrollments_guard reads it.)
create function private.is_onboarded(p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from dogpack.profiles p
    where p."userId" = p_user and p."onboardedAt" is not null
  );
end;
$$;

revoke all on function private.is_onboarded(uuid) from public, anon;
grant execute on function private.is_onboarded(uuid) to authenticated, service_role;
