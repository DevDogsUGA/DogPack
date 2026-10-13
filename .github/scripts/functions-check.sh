#!/usr/bin/env bash
# The Edge Functions against a running local stack, with the platform's APIs
# faked (supabase/functions/_e2e). Starts nothing it does not stop again.
#
# Expects the stack `db-stack.sh up` made (database, auth, REST, gateway).
# `supabase functions serve` runs the functions in the edge runtime container;
# the fake platform runs on this host and the functions reach it through
# host.docker.internal.
#
# Environment:
#   SUPABASE   the CLI to run; default `supabase`
#   FAKE_PLATFORM_PORT   default 8799
#   DEVTOOLS   how to run devtools; default `pnpm dlx @devdogsuga/devtools@next`
set -euo pipefail

supabase=${SUPABASE:-supabase}
port=${FAKE_PLATFORM_PORT:-8799}
devtools=${DEVTOOLS:-pnpm dlx @devdogsuga/devtools@next}
secret="whsec_$(head -c 24 /dev/urandom | base64 | tr -d '=+/\n')"
client_id="dogpack-ci-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
env_file=$(mktemp)
log=$(mktemp)
serve_pid=''

cleanup() {
  [ -n "$serve_pid" ] && kill "$serve_pid" 2>/dev/null || true
  rm -f "$env_file"
  echo "--- functions serve log (tail) ---"; tail -n 40 "$log" || true
  rm -f "$log"
}
trap cleanup EXIT

eval "$("$supabase" status -o env | sed -n 's/^\([A-Z_]*\)=\(".*"\)$/export \1=\2/p')"

cat >"$env_file" <<ENV
PLATFORM_MODERATION_SECRET=$secret
DEVDOGS_OAUTH_CLIENT_ID=$client_id
PLATFORM_API_URL=http://host.docker.internal:$port
CATALOG_URL=http://host.docker.internal:$port/catalog/v1
ENV

"$supabase" functions serve --env-file "$env_file" >"$log" 2>&1 &
serve_pid=$!

for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/functions/v1/platform-moderation" -H "apikey: $PUBLISHABLE_KEY" || true)
  [ "$code" = 401 ] && break
  sleep 2
done
[ "$code" = 401 ] || { echo "platform-moderation did not come up (last status $code)" >&2; exit 1; }

cd supabase/functions/_e2e
PLATFORM_MODERATION_SECRET=$secret DEVDOGS_OAUTH_CLIENT_ID=$client_id FAKE_PLATFORM_PORT=$port \
  API_URL=$API_URL SECRET_KEY=$SECRET_KEY PUBLISHABLE_KEY=$PUBLISHABLE_KEY DB_URL=$DB_URL \
  deno test -A --no-lock functions_test.ts

# The platform's own conformance sequence (signed, replayed, stale, restored)
# against the function the way a deployed platform would reach it.
cd - >/dev/null
echo "--- devtools moderation samples ---"
# shellcheck disable=SC2086
$devtools moderation samples --to "$API_URL/functions/v1/platform-moderation" --secret "$secret"
