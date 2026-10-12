-- Finishes onboarding: stamps profiles."onboardedAt". A member cannot set that
-- column themselves (it is not in their column grants), so "onboarded" means
-- the database checked: a profile with a name, a year and a major, and at
-- least one course. Idempotent. After this, adding a course is under the
-- add/drop deadline.
create function dogpack.complete_onboarding()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_profile dogpack.profiles%rowtype;
begin
  if v_user is null then
    raise exception 'not_signed_in' using errcode = 'PT401';
  end if;
  if private.is_restricted(v_user) then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  select * into v_profile from dogpack.profiles p where p."userId" = v_user;
  if not found or v_profile."major" is null then
    raise exception 'profile_incomplete' using errcode = 'PT422';
  end if;
  if not exists (select 1 from dogpack.enrollments e where e."userId" = v_user) then
    raise exception 'no_courses' using errcode = 'PT422';
  end if;

  update dogpack.profiles p
     set "onboardedAt" = coalesce(p."onboardedAt", now())
   where p."userId" = v_user
  returning p."onboardedAt" into v_profile."onboardedAt";

  return v_profile."onboardedAt";
end;
$$;

revoke all on function dogpack.complete_onboarding() from public, anon;
grant execute on function dogpack.complete_onboarding() to authenticated;
-- pin check
