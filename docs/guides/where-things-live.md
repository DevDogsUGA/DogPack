# Where things live

| Path | What it is |
| --- | --- |
| `lib/main.dart` | Start-up: reads the `--dart-define` values (a friendly error screen when `.env` is missing), starts Sentry if a DSN is set, initializes Supabase (which restores the stored session) and runs the app. |
| `lib/app.dart`, `lib/router.dart` | `MaterialApp.router` with the DogPack brand theme from `devdogsuga_sdk`, and the `go_router` routes. `gateRedirect` is the whole sign-in gate: a status in, a route out. |
| `lib/auth/` | `AuthController` (a `ChangeNotifier`, provided with `provider`) holds where the member stands: loading, signed out, needs onboarding, ready, or failed. `AuthGateway` is the seam to Supabase, so tests use a fake. |
| `lib/screens/`, `lib/widgets/` | One file per screen. New screens go under `/` in the router so they sit behind the gate. |
| `.env.example`, `.vscode/` | The app's public configuration, and the launch configuration that refuses to start with a secret in `.env`. |
| `supabase/dev-data.sql` | Fake classmates and sessions for your own database: `npx @devdogsuga/devtools@next dev-data`. |
| `lib/generated/` | supadart's output, one Dart model per table. Git-ignored; never hand-edit it, regenerate. |
| `android/`, `ios/` | The committed platform runners (`dev.dogpack`). There is no `web/`: the app does not target it. |
| `test/` | Flutter tests: the controller, the gate and its routes, the config. |
| `pubspec.yaml`, `pubspec.lock` | Dependencies. The lock file is committed on purpose: the generated-types hash covers the supadart version it resolves. |
| `supadart.yaml` | Config for the Dart model generator; see [Typed models](./typed-models.md). |
| `analysis_options.yaml` | The lint rules `flutter analyze` checks against. |
| `devtools.config.json` | What makes this a product repository for `devtools`: the product name, the pinned Supabase CLI, the schemas the types cover, where CI uploads the generated types. |
| `supabase/schemas/` | The schema tree: the declared shape of the database. The only place a table is defined. |
| `supabase/tests/` | The RLS suite (pgTAP). |
| `supabase/migrations/` | Hand-written migrations for destructive or data-moving changes only. Reviewed by DevOps. |
| `.github/workflows/` | CI. `ci.yaml` is the checks; `database.yaml` and `destructive-gate.yaml` call DevDogs' shared database workflows; `generated-types.yaml` uploads the models. |
| `.github/scripts/` | The scripts those workflows run. They are plain shell and Node, so you can run them. |
| `.github/CODEOWNERS` | Who reviews what. |

`supabase/` appears once the backend lands; until then the `database` check has
nothing to do.

## Where the schema lives

There is no app-side schema file to look for: the database is defined by
`supabase/schemas/` and nothing else, and the SQL a change runs is generated
from it. See [Schema change loop](./schema-change-loop.md).
