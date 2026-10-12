#!/usr/bin/env bash
# The capacity trigger under contention: a session with one free seat, eight
# members joining at the same instant on eight connections. Exactly one may
# get the seat; the other seven must be told `session_full`. pgTAP runs in one
# transaction and cannot show this; two connections racing can.
#
# Runs against the local stack `db-check.sh` started. Everything it creates is
# deleted again, pass or fail.
#
# Environment:
#   DB_URL     the local database; default: from `supabase status -o env`
#   SUPABASE   the CLI to run; default `supabase`
set -euo pipefail

supabase=${SUPABASE:-supabase}
db_url=${DB_URL:-$("$supabase" status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')}
[ -n "$db_url" ] || { echo "No DB_URL: the local stack is not running." >&2; exit 1; }
psql_q() { psql "$db_url" -v ON_ERROR_STOP=1 -At "$@"; }

workers=8
prefix='00000000-0000-4000-8000-0000000a'   # + 4 hex digits
session='66666666-6666-4666-8666-666666666666'
out=$(mktemp -d)

cleanup() {
  psql_q -q <<SQL >/dev/null 2>&1 || true
delete from auth.users where id::text like '${prefix}%';
delete from dogpack.terms where "term" = 209908;
SQL
  rm -rf "$out"
}
trap cleanup EXIT

# Host 0000, the member who already holds one seat 0001, and the racers 0010+.
psql_q -q <<SQL
insert into dogpack.terms ("term", "description", "classesBegin", "classesEnd", "dropAddEnds")
  values (209908, 'Race term', current_date - 5, current_date + 90, current_date + 5);
insert into auth.users (id, email)
  select ('${prefix}' || lpad(to_hex(g), 4, '0'))::uuid, 'race' || g || '@dogpack.devdogsuga.test'
    from generate_series(0, 1) g
  union all
  select ('${prefix}' || lpad(to_hex(16 + g), 4, '0'))::uuid, 'race' || (16 + g) || '@dogpack.devdogsuga.test'
    from generate_series(1, ${workers}) g;
insert into dogpack.profiles ("userId", "displayName", "classYear", "major", "onboardedAt")
  select id, 'Racer', 'junior', 'CS', now() from auth.users where id::text like '${prefix}%';
insert into dogpack.enrollments ("userId", "term", "course")
  select id, 209908, 'CSCI 1301' from auth.users where id::text like '${prefix}%';
insert into dogpack.sessions ("id", "hostId", "term", "course", "title", "location", "startsAt", "endsAt", "capacity")
  values ('${session}', '${prefix}0000', 209908, 'CSCI 1301', 'Race', 'MLC', now() + interval '1 day', now() + interval '1 day 1 hour', 3);
insert into dogpack.session_members ("sessionId", "userId") values ('${session}', '${prefix}0001');
SQL

# Each racer waits on an advisory lock this script holds, so all eight start
# together instead of whenever their processes happen to launch.
holder_sql="select pg_advisory_lock(424242); select pg_sleep(3); select pg_advisory_unlock(424242);"
psql "$db_url" -q -At -c "$holder_sql" >/dev/null &
holder=$!
sleep 1

for i in $(seq 1 "$workers"); do
  uid="${prefix}$(printf '%04x' $((16 + i)))"
  (
    psql "$db_url" -q -At 2>"$out/err.$i" >"$out/out.$i" <<SQL || true
select pg_advisory_lock_shared(424242);
select set_config('request.jwt.claims', '{"sub":"$uid","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub', '$uid', false);
set role authenticated;
insert into dogpack.session_members ("sessionId") values ('${session}');
SQL
    # psql exits 1 on an error; the message is in err.$i
  ) &
done
wait "$holder" 2>/dev/null || true
wait

joined=$(psql_q -c "select count(*) from dogpack.session_members where \"sessionId\" = '${session}'")
full=$(cat "$out"/err.* 2>/dev/null | grep -c 'session_full' || true)
other=$(cat "$out"/err.* 2>/dev/null | grep -v 'session_full' | grep -c 'ERROR' || true)
count=$(psql_q -c "select \"memberCount\" from dogpack.sessions where \"id\" = '${session}'")

echo "capacity race: ${workers} racers, ${joined} members now (1 before), memberCount ${count}, session_full x${full}, other errors x${other}"
if [ "$joined" -ne 2 ] || [ "$count" -ne 2 ] || [ "$full" -ne $((workers - 1)) ] || [ "$other" -ne 0 ]; then
  echo "The capacity trigger let the session end up over or under capacity." >&2
  cat "$out"/err.* >&2 || true
  exit 1
fi
