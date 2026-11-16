# Schema change loop

Every table DogPack has starts with this loop. You edit **SQL files** in
`supabase/schemas/`, and you never write a migration for an ordinary change:
the pipeline plans the migration from your files, a reviewer reads that exact
SQL, and the deploy applies it.

`your_table` below is a placeholder; swap in whatever you are building.

## 1. Edit the schema tree

```sql
-- supabase/schemas/dogpack/tables/your_table.sql
create table "dogpack"."your_table" (
  "id" uuid primary key default gen_random_uuid(),
  "userId" uuid not null references auth.users (id) on delete cascade,
  -- your columns
  "createdAt" timestamptz not null default now()
);

alter table "dogpack"."your_table" enable row level security;

-- Grants are explicit; nothing is granted by default. `authenticated` gets only
-- what members may do (RLS then narrows it). `service_role` is the Edge
-- Functions AND the key the model generator uses: without this line
-- `db sync` succeeds but no Dart model is generated for the table.
grant select, insert, update, delete on table "dogpack"."your_table" to authenticated;
grant select, insert, update, delete on table "dogpack"."your_table" to service_role;
```

Then write policies (below). A table with RLS enabled and **no policies at all**
denies everything, which is the safe failure mode while you decide what a policy
should say.

## 2. Apply it to your own database and regenerate the models

```bash
pnpm devtools db sync
```

`db sync` makes your development database match the tree. It never resets your
database. It then regenerates the Dart models; see [Typed models](./typed-models.md).

It also checks the database itself:

- Anything the tree defines but the database lacks, such as a table you dropped by
  hand, is recreated.
- Anything you added that the tree doesn't define, such as an experimental table,
  column or grant, is listed as a warning and left alone. `db sync --strict` fails
  on these instead.
- Anything defined differently in the database than in the tree, such as a changed
  column type or function body, is refused and left unchanged. Fix the tree to match,
  or start fresh with `pnpm devtools db sync --rebuild`, which wipes your local
  database, and then `pnpm devtools dev-data`.

## 3. Test the policies

Write a pgTAP file under `supabase/tests/` that asserts an **allow and a deny**
for every policy, and run it against your local stack:

```bash
supabase test db
```

A policy test that only checks the allow side passes just as happily when the
policy is missing entirely. The `database` check in CI runs the same suite
against an empty database built from the tree, and fails if there are tables and
no tests.

## 4. Open the pull request

CI plans the SQL your change runs and shows it in the job summary of
`destructive-gate / destructive-sql`, with the type changes in `database`.

Generated changes may only **add**. A change that drops a table or column,
changes a column's type, or drops a policy without re-creating it is
destructive. It needs either a hand-written `supabase/migrations/<timestamp>_<name>.sql`
(reviewed by DevOps) or the `allow-destructive` label, which only a DevOps member
can apply. The deploy asks a DevOps member to approve a destructive plan a
second time.

## Row Level Security

RLS is what protects your table. The app talks to PostgREST with the publishable
key, so a client that can reach one table can try every table; only each
table's own policies decide what a given user gets back.

### `auth.uid()`

Every request PostgREST serves runs as `anon` (no session) or `authenticated` (a
valid Supabase Auth JWT). `auth.uid()` reads the signed-in user's id out of the
JWT, and is `null` for `anon`. A policy that compares a row's owner column with
`auth.uid()` enforces "only my own rows" at the database instead of trusting the
client.

### Policy shapes

For an owner-scoped table, one `for all` policy with the same predicate in
`using` (which rows a query may see or touch) and `with check` (which rows a
write may produce):

```sql
create policy "users_own_rows" on "dogpack"."your_table"
  as permissive for all to "authenticated"
  using (auth.uid() = "userId")
  with check (auth.uid() = "userId");
```

Split it into one policy per command when the rule differs by operation. A table
with public reads and owner-only writes needs a `select` policy open to
`anon, authenticated` plus separate `insert`, `update` and `delete` policies:

```sql
create policy "public_read" on "dogpack"."your_table"
  for select to anon, authenticated using (true);

create policy "owner_write" on "dogpack"."your_table"
  for insert to authenticated with check (auth.uid() = "userId");
```

A restrictive policy (`as restrictive`) narrows what permissive policies
allowed, and it is how you close writes on rows only the server should write.
Restrictive policies **AND** together and with the permissive set, so a single
restrictive `for all using (false)` also blocks `select` and silently cancels a
public-read policy. Write one restrictive policy per command you mean to close.

See [Supabase's RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security)
for the mechanics beyond this.
