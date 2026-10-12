-- The add/drop deadline rule, and the other limits on adding a course.
--
--   * no adding for a term that is over;
--   * no adding after the term's full-term drop/add end (dogpack.terms
--     "dropAddEnds", Athens time), EXCEPT the one-time initial enrollment: a
--     member who has never finished onboarding (private.onboarded_users, which
--     delete_my_data does not clear, so the exception is used once) may enter their courses whenever
--     they join, because someone who finds DogPack in November still has to
--     say what they are taking;
--   * a term the cache has never heard of is refused, unless the member is
--     still onboarding, so the app works while the catalog is down. Such a row
--     is stored with catalogVerified = false.
--
-- Errors carry SQLSTATE PT4xx, which PostgREST turns into that HTTP status; the
-- message is the stable code the app switches on.
create function private.enrollments_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_term dogpack.terms%rowtype;
  v_onboarded boolean;
  v_today date := (now() at time zone 'America/New_York')::date;
begin
  if private.is_restricted(new."userId") then
    raise exception 'account_restricted' using errcode = 'PT403';
  end if;

  select exists (
    select 1 from private.onboarded_users o where o."userId" = new."userId"
  ) into v_onboarded;

  select * into v_term from dogpack.terms t where t."term" = new."term";

  if not found then
    if v_onboarded then
      raise exception 'unknown_term' using errcode = 'PT422';
    end if;
  else
    if v_term."classesEnd" is not null and v_today > v_term."classesEnd" then
      raise exception 'term_over' using errcode = 'PT422';
    end if;
    if v_onboarded and v_term."dropAddEnds" is not null and v_today > v_term."dropAddEnds" then
      raise exception 'enrollment_closed' using errcode = 'PT403';
    end if;
  end if;

  if (
    select count(*) from dogpack.enrollments e
    where e."userId" = new."userId" and e."term" = new."term"
  ) >= 12 then
    raise exception 'too_many_courses' using errcode = 'PT422';
  end if;

  return new;
end;
$$;

revoke all on function private.enrollments_guard() from public, anon, authenticated;
