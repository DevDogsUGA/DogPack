# Contributing to DogPack

Start with [Your first contribution](docs/getting-started/first-contribution.md),
then pick an issue from the [milestones](https://github.com/DevDogsUGA/DogPack/milestones).

## Before you open a pull request

- Keep it small and focused on one change. Link the issue it closes.
- Commit messages read `type(scope): subject`, for example
  `feat(onboarding): add the name step`.
- `flutter analyze` and `flutter test` pass locally.
- Changed behavior means changed docs.
- A table, column or policy change is an edit to `supabase/schemas/*.sql`, with an
  RLS test that asserts the allow **and** the deny. Do not write a migration for it;
  see [Schema change loop](docs/guides/schema-change-loop.md).
- Never put a secret in the repository, `.env.example` or a `--dart-define`.
  Anything compiled into the app can be read back out of it.

## Review

Pull requests need one approval from the code owners in
[`.github/CODEOWNERS`](.github/CODEOWNERS): the DogPack leads for the app, and
DevOps for workflows and anything under `supabase/`. Merges are squash merges
through the merge queue.

## Checks

| Check | Meaning |
| --- | --- |
| `validate` | workflow lint, Markdown links, `.env.example` is public-only |
| `flutter` | analyze and test |
| `android` | the debug APK builds and starts on an emulator |
| `database` | the schema tree applies, the RLS suite passes, the types generate |
| `destructive-gate / ...` | the SQL your change runs, and the gate on data-dropping changes |

Stuck, or something is wrong with the docs? Ask in the club Discord.
