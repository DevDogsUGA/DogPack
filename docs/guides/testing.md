# Testing

```bash
flutter analyze
flutter test
```

Neither needs a database or a Supabase stack. `test/widget_test.dart` is a smoke
test: it pumps the app and asserts the placeholder renders. `analysis_options.yaml`
layers `prefer_const_constructors` on top of `flutter_lints`.

## What CI runs

`.github/workflows/ci.yaml` runs on every pull request and in the merge queue.
Each job reports a check by the same name:

| Check | What it does |
| --- | --- |
| `validate` | Lints the workflows (actionlint), checks that every relative link in the Markdown resolves, and checks that `.env.example` (once it exists) holds public values only. |
| `flutter` | `flutter pub get`, `flutter analyze`, `flutter test`. |
| `android` | Builds the debug APK, boots it on an Android emulator and checks that the app starts and stays up. The screenshot is attached to the run. |
| `database` | Applies `supabase/schemas/` to an empty local database, runs the RLS suite, runs `supabase/dev-data.sql` twice, generates the Dart models and posts the type changes in the job summary. With no schema yet it passes and says so. |
| `destructive-gate / destructive-sql`, `destructive-gate / destructive-gate` | Plan the SQL your change runs, show it in the job summary, and block a change that drops or rewrites data unless a DevOps member labels the pull request `allow-destructive`. |

## The RLS suite

Policies are tested with [pgTAP](https://pgtap.org/) under `supabase/tests/`. Every
table needs a test for the allow **and** the deny: a test that only checks the
allow side passes just as happily when the policy is missing. The `database`
check fails when `supabase/schemas/` has SQL and `supabase/tests/` has none. Run
it locally against your own stack with `supabase test db`.

## Running the emulator job yourself

The `android` check builds with `flutter build apk --debug` and installs the APK
on an x86_64 emulator image. To do the same by hand, start any emulator and run
`flutter run --dart-define-from-file=.env`; the job only adds the assertion that the process is still alive
after start-up.
