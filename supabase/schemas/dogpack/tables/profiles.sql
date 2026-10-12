-- One row per member. It exists from the first onboarding step (name and
-- year) and is `onboarded` once `onboardedAt` is set, which only
-- dogpack.complete_onboarding() can do: it checks the member picked a major
-- and at least one course.
create table dogpack.profiles (
  "userId"        uuid        primary key references auth.users (id) on delete cascade,
  "displayName"   text        not null,
  "classYear"     dogpack."classYear" not null,
  "major"         text,
  "onboardedAt"   timestamptz,
  -- Set by moderation.apply_event when a moderator hides the profile. Row
  -- level security then shows the row to its owner only.
  "quarantinedBy" text,
  "quarantinedAt" timestamptz,
  "createdAt"     timestamptz not null default now(),
  "updatedAt"     timestamptz not null default now(),
  constraint "profiles_displayName_length" check (char_length(btrim("displayName")) between 1 and 60),
  constraint "profiles_major_length" check ("major" is null or char_length(btrim("major")) between 1 and 80),
  constraint "profiles_onboarded_has_major" check ("onboardedAt" is null or "major" is not null)
);

alter table dogpack.profiles enable row level security;

-- A member reads their own profile, and the profile of anyone they share a
-- session with. A quarantined or restricted member's profile is theirs alone.
create policy "profiles_select" on dogpack.profiles
  for select to authenticated
  using (
    "userId" = (select auth.uid())
    or (
      "quarantinedBy" is null
      and private.profile_visible((select auth.uid()), "userId")
    )
  );

create policy "profiles_insert_own" on dogpack.profiles
  for insert to authenticated
  with check (
    "userId" = (select auth.uid())
    and not private.is_restricted((select auth.uid()))
  );

create policy "profiles_update_own" on dogpack.profiles
  for update to authenticated
  using ("userId" = (select auth.uid()))
  with check (
    "userId" = (select auth.uid())
    and not private.is_restricted((select auth.uid()))
  );

-- No client delete: dogpack.delete_my_data() removes a profile.

revoke all on table dogpack.profiles from public, anon, authenticated;
grant select on table dogpack.profiles to authenticated;
grant insert ("userId", "displayName", "classYear", "major") on table dogpack.profiles to authenticated;
grant update ("displayName", "classYear", "major") on table dogpack.profiles to authenticated;
grant select, insert, update, delete on table dogpack.profiles to service_role;

create trigger "profiles_touch" before update on dogpack.profiles
  for each row execute function private.touch_updated_at();

comment on table dogpack.profiles is 'A member''s profile. onboardedAt is set only by dogpack.complete_onboarding().';

create trigger "profiles_mark_onboarded" after insert or update of "onboardedAt" on dogpack.profiles
  for each row execute function private.profiles_mark_onboarded();
