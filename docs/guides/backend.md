# The backend

DogPack's backend is its own Supabase project (`dogpack.supabase.co`), separate
from the DevDogs platform's. Everything a signed-in member does goes through
tables and functions in the `dogpack` schema under Row Level Security; three Edge
Functions cover what SQL cannot do (calling out to the platform).

## The schema (`supabase/schemas/`)

| Schema | What is in it |
| --- | --- |
| `dogpack` | `profiles`, `enrollments`, `terms` (a cache of the catalog's term dates), `sessions`, `session_members`, `blocks`, and the functions `complete_onboarding()` and `delete_my_data()`. The only schema PostgREST serves. |
| `private` | Guards and policy helpers (`enrollments_guard`, `session_members_guard`, `is_restricted`, `session_visible` and the like). Not exposed to the API. |
| `moderation` | `events`, `decisions`, `user_states` and `apply_event()`, the receiver's transaction. Not exposed to the API. |

Rules worth knowing, each asserted by a pgTAP file under `supabase/tests/`:

- **Enrollment deadline.** A member cannot add a course for a term that is over,
  and cannot add one after the term's full-term drop/add end, with one exception:
  someone who has not finished onboarding may enter their courses whenever they
  join. A term the `terms` cache has never heard of is refused once onboarded.
  Twelve courses a term at most. The errors are `PT4xx` codes the app switches on.
- **Catalog validation.** The `enroll` function asks the platform's catalog API
  (`/catalog/v1`) whether the course exists in that term, fills `terms`, and
  inserts with `catalogVerified` set. If the catalog is down it falls back to a
  format check and stores the row unverified.
- **Capacity.** `sessions.capacity` counts every seat including the host's.
  `session_members_guard` locks the session row, so two joins for the last seat
  run one after the other, and the second gets `session_full`. `.github/scripts/capacity-race.sh`
  proves it with concurrent connections.
- **Delete my data.** `dogpack.delete_my_data()` removes the caller's profile,
  enrollments, hosted sessions, memberships and blocks and returns the counts.
  It does not delete the sign-in and does not lift a suspension.

## The moderation receiver

- `report` (member session): checks the member can see the content, then files a
  signed report with the platform's moderation API (`/moderation/v1/reports`).
- `platform-moderation` (platform signature): verifies the Standard Webhooks
  signature and calls `moderation.apply_event`, which is idempotent (a replayed
  id answers `duplicate`), order-safe (a message older than the last decision on
  the item answers `stale`) and atomic.
- A `content.hide` sets `quarantinedBy` on the session or profile; RLS then shows
  the row to its author only. `user.suspend` and `user.ban` make every policy treat
  the user as restricted. `content.restore` and `user.restore` undo them.
- `_shared/moderation/` is a vendored copy of `@devdogsuga/sdk/moderation`; see its
  README for why and how it is kept in step.

## Testing it

```bash
bash .github/scripts/db-check.sh            # needs BASE_SHA; schema, RLS suite, models
bash .github/scripts/functions-check.sh     # needs the stack from db-stack.sh up; Deno
deno test -A --no-lock supabase/functions/_shared
```

The `functions` job in `ci.yaml` runs the last two, with the platform's APIs
faked, then runs `devtools moderation samples` against `platform-moderation`.

## Deploying (maintainers)

DogPack has one project and no staging one, so `deploy.yaml` is production only.
It stays off until the repository variable `DOGPACK_DEPLOYS_PRODUCTION` is `true`.
Each job needs a `devops` approval of the `production` environment; a plan that
drops data also needs `production-destructive`. The `production` environment
holds:

| Kind | Name | What |
| --- | --- | --- |
| variable | `PROJECT_REF`, `API_URL`, `PUBLISHABLE_KEY` | The project and its public API values. |
| variable | `PLATFORM_API_URL`, `DEVDOGS_OAUTH_BASE_URL` | The platform's API and its Supabase auth URL. |
| secret | `DB_URL`, `SECRET_KEY`, `SUPABASE_ACCESS_TOKEN` | The project's credentials. |
| secret | `DEVDOGS_OAUTH_CLIENT_ID`, `DEVDOGS_OAUTH_CLIENT_SECRET` | The production OAuth client DogPack signs in with. |
| secret | `PLATFORM_MODERATION_SECRET` | The `whsec_` secret the platform shows once when the app is registered in the console under Apps Outside the Platform (or rotated in `/tools/oauth`). |

The `preflight` environment holds `DB_URL` for the read-only `migration_planner`
role (`.github/scripts/planner-role.sql`).
