# Where things live

| Path | What it is |
| --- | --- |
| `lib/main.dart` | The app: Supabase initialization, the `--dart-define` values it reads, and the placeholder home screen. |
| `lib/generated/` | supadart's output, one Dart model per table. Git-ignored; never hand-edit it, regenerate. |
| `android/`, `ios/` | The committed platform runners (`dev.dogpack`). There is no `web/`: the app does not target it. |
| `test/` | Flutter tests. `widget_test.dart` is the smoke test. |
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
