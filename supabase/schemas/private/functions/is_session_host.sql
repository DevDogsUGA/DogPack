create function private.is_session_host(p_session uuid, p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from dogpack.sessions s
    where s."id" = p_session and s."hostId" = p_user
  );
end;
$$;

revoke all on function private.is_session_host(uuid, uuid) from public, anon;
grant execute on function private.is_session_host(uuid, uuid) to authenticated, service_role;
