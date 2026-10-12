-- A cache of the catalog's terms: when each one ends and when adding courses
-- closes. The `enroll` Edge Function fills it from the platform's catalog API
-- (https://api.devdogsuga.org/catalog/v1/terms); the database cannot call out,
-- so this is how the add/drop deadline rule gets its dates. Members read it to
-- show the deadline. Nobody but the service role writes it.
create table dogpack.terms (
  "term"        integer     primary key,
  "description" text        not null,
  "classesBegin" date,
  "classesEnd"  date,
  "dropAddEnds" date,
  "fetchedAt"   timestamptz not null default now(),
  constraint "terms_term_format" check ("term" >= 200002 and "term" <= 299908 and "term" % 100 = any (array[2, 5, 8]))
);

alter table dogpack.terms enable row level security;

create policy "terms_read" on dogpack.terms
  for select to authenticated using (true);

revoke all on table dogpack.terms from public, anon, authenticated;
grant select on table dogpack.terms to authenticated;
grant select, insert, update on table dogpack.terms to service_role;

comment on table dogpack.terms is 'Cache of the catalog''s terms (end dates and the add/drop deadline), written by the enroll function.';
