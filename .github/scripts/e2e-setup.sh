#!/usr/bin/env bash
# The end-to-end setup check: do what docs/getting-started/first-contribution.md
# tells a new member to do, then what they do next, against a local Docker
# Supabase stack.
#
#   pnpm install, `pnpm devtools setup --local`, `devtools doctor`,
#   `flutter pub get`, `flutter analyze` with lib/generated present,
#   `flutter test`, and `devtools dev-data` for a seeded user.
#
# Which devtools runs:
#   (default)         `pnpm devtools`, i.e. @devdogsuga/devtools@next, exactly
#                     as the docs say (the nightly workflow, e2e-setup.yaml).
#   DEVTOOLS_TARBALL  a `pnpm pack` of a devtools build, so DevDogsUGA's CI can
#                     check a change before it publishes to @next.
#
# Sign in with DevDogs: when DEVDOGS_OAUTH_CLIENT_ID and
# DEVDOGS_OAUTH_CLIENT_SECRET are set (the test client; see e2e-setup.yaml),
# setup registers the provider with them. Otherwise setup runs with
# --skip-oauth.
set -euo pipefail

devtools() {
  if [ -n "${DEVTOOLS_TARBALL:-}" ]; then
    pnpm --config.ignore-scripts=true dlx "$DEVTOOLS_TARBALL" "$@"
  else
    pnpm devtools "$@"
  fi
}

step() { printf '\n==> %s\n' "$*"; }

step "flutter doctor (first use downloads the engine artifacts; setup needs them)"
flutter doctor || true

step "pnpm install"
pnpm install --frozen-lockfile

step "devtools setup (local Docker stack)"
oauth=(--skip-oauth)
if [ -n "${DEVDOGS_OAUTH_CLIENT_ID:-}" ] && [ -n "${DEVDOGS_OAUTH_CLIENT_SECRET:-}" ]; then
  oauth=()
fi
devtools setup --local "${oauth[@]}" </dev/null

step "devtools doctor"
devtools doctor </dev/null

if [ ${#oauth[@]} -eq 0 ]; then
  # Setup registered custom:devdogsuga on the local stack from the test client.
  # STUB: the scripted sign-in (a *.devdogsuga.test account on the staging
  # platform, then the token exchange, then an assertion that auth.identities
  # has a custom:devdogsuga row) is written once the test client exists.
  step "sign in with DevDogs (stub: registered, sign-in not scripted yet)"
fi

step "lib/generated is present"
test -n "$(ls lib/generated 2>/dev/null)" || { echo "lib/generated is empty after setup." >&2; exit 1; }

step "flutter pub get"
flutter pub get

step "flutter analyze"
flutter analyze

step "flutter test"
flutter test

step "dev-data for a seeded user"
# `dev-data` seeds as the member who signed in last. There is no browser here,
# so create the member the way sign-in would have, through the local stack's
# admin API, and name them with --member.
eval "$(pnpm --config.ignore-scripts=true dlx "supabase@$(node -p "require('./devtools.config.json').supabase.version")" status -o env 2>/dev/null | grep -E '^(API_URL|SERVICE_ROLE_KEY)=')"
email="e2e@seed.devdogsuga.test"
curl -fsS -X POST "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$email\",\"email_confirm\":true}" >/dev/null
devtools dev-data --member "$email" </dev/null
# Running it again must also work (the docs say it is safe to).
devtools dev-data --member "$email" </dev/null

step "all steps passed"
