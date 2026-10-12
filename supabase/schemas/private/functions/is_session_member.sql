create function private.is_session_member(p_session uuid, p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from dogpack.session_members m
    where m."sessionId" = p_session and m."userId" = p_user
  );
end;
$$;

revoke all on function private.is_session_member(uuid, uuid) from public, anon;
grant execute on function private.is_session_member(uuid, uuid) to authenticated, service_role;
