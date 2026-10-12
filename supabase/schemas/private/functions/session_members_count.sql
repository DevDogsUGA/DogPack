-- Keeps dogpack.sessions."memberCount" equal to the number of joined members.
-- Runs after the insert or delete, under the row lock the guard took on join.
create function private.session_members_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session uuid := coalesce(new."sessionId", old."sessionId");
begin
  update dogpack.sessions s
     set "memberCount" = (select count(*) from dogpack.session_members m where m."sessionId" = v_session)
   where s."id" = v_session;
  return null;
end;
$$;

revoke all on function private.session_members_count() from public, anon, authenticated;
