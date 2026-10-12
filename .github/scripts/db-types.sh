#!/usr/bin/env bash
# Generate the Dart models (lib/generated/) from the running local stack.
#
# supadart reads SUPABASE_URL and SUPABASE_API_KEY, and needs the SECRET key:
# it gets a 401 on the publishable one when it fetches the OpenAPI spec. The
# key is the throwaway one the local stack prints, never a real project's.
set -euo pipefail

supabase=${SUPABASE:-supabase}
status=$("$supabase" status -o env)
api_url=$(printf '%s\n' "$status" | sed -n 's/^API_URL="\(.*\)"$/\1/p')
secret_key=$(printf '%s\n' "$status" | sed -n 's/^SECRET_KEY="\(.*\)"$/\1/p')
if [ -z "$api_url" ] || [ -z "$secret_key" ]; then
  echo "The local stack is not running (supabase status printed no API_URL or SECRET_KEY)." >&2
  exit 1
fi

rm -rf lib/generated
SUPABASE_URL=$api_url SUPABASE_API_KEY=$secret_key dart run supadart
test -d lib/generated || { echo "supadart wrote no lib/generated/." >&2; exit 1; }
