-- Who has ever finished onboarding. The add/drop deadline has one exception:
-- the initial enrollment, which happens once. delete_my_data removes the
-- profile (and with it onboardedAt), so the "has onboarded" fact lives here,
-- where deleting your data does not reset it. The row holds only the user id,
-- which the kept sign-in account already holds.
create table private.onboarded_users (
  "userId"      uuid        primary key references auth.users (id) on delete cascade,
  "onboardedAt" timestamptz not null default now()
);

alter table private.onboarded_users enable row level security;

revoke all on table private.onboarded_users from public, anon, authenticated;
grant select, insert on table private.onboarded_users to service_role;

comment on table private.onboarded_users is 'Users who finished onboarding once; survives delete_my_data so the initial-enrollment exception to the deadline is one-time.';
