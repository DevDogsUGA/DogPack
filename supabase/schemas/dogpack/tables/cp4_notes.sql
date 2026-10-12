-- throwaway checkpoint 4 table
create table dogpack.cp4_notes (
  "id" uuid primary key default gen_random_uuid(),
  "userId" uuid not null references auth.users (id) on delete cascade,
  "body" text not null,
  "createdAt" timestamptz not null default now()
);
alter table dogpack.cp4_notes enable row level security;
create policy "cp4_notes_owner" on dogpack.cp4_notes for all to authenticated
  using ("userId" = (select auth.uid())) with check ("userId" = (select auth.uid()));
grant select, insert, update, delete on dogpack.cp4_notes to authenticated;
grant select, insert, update, delete on table dogpack.cp4_notes to service_role;
