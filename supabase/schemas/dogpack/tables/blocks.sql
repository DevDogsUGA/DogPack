-- A member blocks another: neither sees the other's sessions or profile, and
-- neither can join the other's sessions. One row is enough for both
-- directions (private.is_blocked_between looks both ways).
create table dogpack.blocks (
  "blockerId" uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  "blockedId" uuid        not null references auth.users (id) on delete cascade,
  "createdAt" timestamptz not null default now(),
  primary key ("blockerId", "blockedId"),
  constraint "blocks_not_self" check ("blockerId" <> "blockedId")
);

create index "blocks_blocked_idx" on dogpack.blocks ("blockedId");

alter table dogpack.blocks enable row level security;

-- Only the blocker sees the row: the person blocked is never told.
create policy "blocks_select_own" on dogpack.blocks
  for select to authenticated
  using ("blockerId" = (select auth.uid()));

create policy "blocks_insert_own" on dogpack.blocks
  for insert to authenticated
  with check ("blockerId" = (select auth.uid()));

create policy "blocks_delete_own" on dogpack.blocks
  for delete to authenticated
  using ("blockerId" = (select auth.uid()));

revoke all on table dogpack.blocks from public, anon, authenticated;
grant select, delete on table dogpack.blocks to authenticated;
grant insert ("blockerId", "blockedId") on table dogpack.blocks to authenticated;
grant select, insert, update, delete on table dogpack.blocks to service_role;

comment on table dogpack.blocks is 'Member-to-member blocks. Only the blocker can read their rows.';
