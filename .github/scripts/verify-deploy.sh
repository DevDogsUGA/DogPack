#!/usr/bin/env bash
# What a deployed DogPack backend must do for a visitor who is not signed in
# (the production deploy runs this against the project it just changed, and
# `functions-check.sh`'s stack can be checked the same way):
#
#   - PostgREST serves the `dogpack` schema (the publishable key is accepted;
#     a schema it does not serve answers 406),
#   - a signed-out request for a table gets an error, never rows,
#   - the member functions are not callable without a session,
#   - nothing else is exposed: `moderation`, `private` and `public` are not
#     served schemas,
#   - the Edge Functions are deployed and each refuses what it must:
#     `platform-moderation` an unsigned delivery, `report` and `enroll` a
#     request with no session.
#
# Environment: API_URL (https://<ref>.supabase.co), PUBLISHABLE_KEY.
set -euo pipefail

: "${API_URL:?API_URL is required}"
: "${PUBLISHABLE_KEY:?PUBLISHABLE_KEY is required}"
api=${API_URL%/}
body=$(mktemp)
trap 'rm -f "$body"' EXIT
fail() { echo "verify-deploy: $*" >&2; exit 1; }
status() { # status <profile> <method> <path> [json]
  curl -s -o "$body" -w '%{http_code}' -X "$2" \
    -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $PUBLISHABLE_KEY" \
    -H "Accept-Profile: $1" -H "Content-Profile: $1" -H 'Content-Type: application/json' \
    ${4:+--data "$4"} "$api/rest/v1/$3"
}
refused() { case "$1" in 401 | 403) return 0 ;; *) return 1 ;; esac }

# PostgREST needs a moment to reload its schema cache after a change. Probe a
# table, not the root: the root is the OpenAPI document, which only a secret key
# may read, so it answers 401 for every profile (served or not). For a table,
# `anon` has no access to the schema, so a served schema answers 401/403 and an
# unserved one 406.
for attempt in 1 2 3 4 5 6; do
  code=$(status dogpack GET 'enrollments?limit=0')
  if refused "$code" || [ "$code" = 200 ]; then break; fi
  echo "verify-deploy: the API answered $code, waiting (attempt $attempt)"
  sleep 10
done
refused "$code" || [ "$code" = 200 ] || fail "the API does not serve the dogpack schema ($code): $(head -c 300 "$body")"
code=$(status not_a_schema GET 'enrollments?limit=0')
[ "$code" = 406 ] || fail "a schema that does not exist answered $code, not 406: the check above proves nothing"
echo "ok - the API serves the dogpack schema"

for table in profiles enrollments sessions session_members blocks terms; do
  code=$(status dogpack GET "$table?select=*&limit=1")
  refused "$code" || fail "a signed-out GET of $table answered $code, not 401/403: $(head -c 300 "$body")"
done
echo "ok - a signed-out visitor is refused on every table"

for fn in complete_onboarding delete_my_data; do
  code=$(status dogpack POST "rpc/$fn" '{}')
  refused "$code" || fail "a signed-out call of $fn answered $code, not 401/403: $(head -c 300 "$body")"
done
echo "ok - the member functions need a session"

for schema in moderation private public; do
  # A table path, for the same reason as above: the root needs a secret key.
  code=$(status "$schema" GET 'enrollments?limit=0')
  case "$code" in 406 | 404 | 400) ;; *) fail "the $schema schema answered $code; only dogpack should be served" ;; esac
done
echo "ok - moderation, private and public are not served schemas"

fn() { # fn <name> [header...]: POST an empty JSON body, print the status
  local name=$1; shift
  curl -s -o "$body" -w '%{http_code}' -X POST -H "apikey: $PUBLISHABLE_KEY" -H 'Content-Type: application/json' "$@" --data '{}' "$api/functions/v1/$name"
}
code=$(fn platform-moderation)
[ "$code" = 401 ] || fail "platform-moderation answered an unsigned delivery with $code, not 401: $(head -c 300 "$body")"
echo "ok - platform-moderation refuses an unsigned delivery"
for name in report enroll; do
  code=$(fn "$name")
  [ "$code" = 401 ] || fail "$name answered a request with no session with $code, not 401: $(head -c 300 "$body")"
done
echo "ok - report and enroll need a session"
