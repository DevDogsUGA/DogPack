-- Is this DogPack user a suspended or banned DevDogs user? The moderation
-- state is keyed by the DevDogs user id, which is the subject of the user's
-- custom:devdogsuga identity.
create function private.is_restricted(p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from auth.identities i
    join moderation.user_states s on s."platformUserId"::text = i.provider_id
    where i.user_id = p_user
      and i.provider = 'custom:devdogsuga'
      and s."state" <> 'active'
  );
end;
$$;

revoke all on function private.is_restricted(uuid) from public, anon;
grant execute on function private.is_restricted(uuid) to authenticated, service_role;
