#!/usr/bin/env bash
# A local Supabase stack at the schema tree, for CI.
#
#   db-stack.sh up     start the database, apply supabase/schemas/ to it, then
#                      start the rest of the stack
#   db-stack.sh down   remove the stack and its data
#
# Why the database starts alone first: PostgREST refuses to start when
# `[api] schemas` names a schema that does not exist yet, and on a fresh
# database it does not. So the tree is applied first, through the same
# command DevDogsUGA's deploy pipeline uses (`declarative sync --apply`,
# strict about coverage), and the API starts after, against a database that
# already has the schema. `supabase stop` keeps the data volume, so the
# second start comes up on what the first one built.
#
# The stack is the smallest one supadart and the RLS suite need: the database,
# auth, the REST API, storage (supadart reads the storage buckets too), and
# the gateway in front of them.
#
# Environment:
#   SUPABASE   the CLI to run; default `supabase`.
set -euo pipefail

supabase=${SUPABASE:-supabase}
excluded=studio,imgproxy,vector,logflare,mailpit,edge-runtime,realtime

case "${1:-}" in
  up)
    "$supabase" db start
    "$supabase" db schema declarative sync --apply --strict-coverage --name ci
    "$supabase" stop
    "$supabase" start -x "$excluded"
    ;;
  down)
    "$supabase" stop --no-backup || true
    ;;
  *)
    echo "usage: db-stack.sh up|down" >&2
    exit 2
    ;;
esac
