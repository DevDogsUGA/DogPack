create function private.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from dogpack.blocks b
    where (b."blockerId" = p_a and b."blockedId" = p_b)
       or (b."blockerId" = p_b and b."blockedId" = p_a)
  );
end;
$$;

revoke all on function private.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function private.is_blocked_between(uuid, uuid) to authenticated, service_role;
