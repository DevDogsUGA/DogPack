-- Records the first time a profile is onboarded in private.onboarded_users.
create function private.profiles_mark_onboarded()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."onboardedAt" is not null then
    insert into private.onboarded_users ("userId", "onboardedAt")
    values (new."userId", new."onboardedAt")
    on conflict ("userId") do nothing;
  end if;
  return new;
end;
$$;

revoke all on function private.profiles_mark_onboarded() from public, anon, authenticated;
