# DogPack

DogPack is DevDogs' app for finding and forming study groups with other UGA
students. It is a Flutter app for **Android and iOS** (there is no web build),
with its own Supabase project behind it. Sign-in is "Sign in with DevDogs": the
DevDogs platform is the identity provider, so nobody makes a DogPack password.

> [!TIP]
> New here? Start with [Your first contribution](./getting-started/first-contribution.md).
> The work is tracked as [GitHub issues](https://github.com/DevDogsUGA/DogPack/issues),
> grouped into [milestones](https://github.com/DevDogsUGA/DogPack/milestones) by feature.

## How the pieces fit

```
Flutter client (Android / iOS)
  --dart-define values (public only)
  --> supabase_flutter --> DogPack's own Supabase project, over HTTP
        - PostgREST: the app's tables, guarded by Row Level Security
        - Auth: the "Sign in with DevDogs" provider (OAuth against the platform)
  <-- Dart models generated from the schema (supadart)
```

- **The database is the source of truth for access.** The app talks to Supabase
  over HTTP with the publishable key, so Row Level Security is the only thing
  between a client and every row. See [Schema change loop](./guides/schema-change-loop.md).
- **Schema changes are SQL files.** Contributors edit `supabase/schemas/*.sql`
  and never write migrations; the pipeline plans the migration, a person reads
  it, and the deploy applies exactly that SQL.
- **Dart models are generated, not committed.** See [Typed models](./guides/typed-models.md).
- **Sign-in goes through the platform's OAuth server.** The app never holds a user
  store of its own.

## Glossary

- **DogPack**: this app. Its Android and iOS ID is `dev.dogpack`, and the
  sign-in callback is `dev.dogpack://login-callback`.
- **Schema tree**: `supabase/schemas/`, the declared shape of the database.
- **supadart**: the community Dart generator for typed models; see
  [Typed models](./guides/typed-models.md).
- **`--dart-define`**: how configuration (the Supabase URL and publishable key)
  reaches the compiled app.
- **generated-types release**: the rolling GitHub release where CI keeps the
  models for every schema version, so you can download instead of generating.

## Where to go next

- [Where things live](./guides/where-things-live.md): a map of the repository
- [Testing](./guides/testing.md): `flutter analyze`, `flutter test`, and what CI runs
- [Schema change loop](./guides/schema-change-loop.md): adding a table, with RLS
- [Typed models](./guides/typed-models.md): how the Dart models are made
