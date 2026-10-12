create function private.is_enrolled(p_user uuid, p_term integer, p_course text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from dogpack.enrollments e
    where e."userId" = p_user and e."term" = p_term and e."course" = p_course
  );
end;
$$;

revoke all on function private.is_enrolled(uuid, integer, text) from public, anon;
grant execute on function private.is_enrolled(uuid, integer, text) to authenticated, service_role;
