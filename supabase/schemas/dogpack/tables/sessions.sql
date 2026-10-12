create table "dogpack"."sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "hostId" uuid not null references auth.users (id) on delete cascade,
  "title" text not null,
  "capacity" integer not null default 4,
  "createdAt" timestamptz not null default now()
);
alter table "dogpack"."sessions" enable row level security;
create policy "host_all" on "dogpack"."sessions" for all to authenticated
  using (auth.uid() = "hostId") with check (auth.uid() = "hostId");
