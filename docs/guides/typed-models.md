# Typed models

`supabase gen types` has no Dart target, so DogPack gets its typed models from
the community [supadart](https://pub.dev/packages/supadart) generator. The
models are **never committed**: `lib/generated/` is git-ignored. You get them
one of two ways.

## Generate them from your database

```bash
pnpm devtools db sync    # make your dev database match supabase/schemas/
pnpm devtools db types   # run supadart against it
```

`db sync` regenerates the models after it changes your database. Under the hood
this is `dart run supadart`, which reads `supadart.yaml` (`output: lib/generated/`,
`separated: true`) and writes one Dart model per table.

## Download the ones CI built

```bash
pnpm devtools db types --download
```

CI uploads a `dogpack-types-<hash>.tgz` asset to the rolling
[`generated-types` release](https://github.com/DevDogsUGA/DogPack/releases/tag/generated-types)
on every change to the schema. The hash covers the sorted paths and
LF-normalized contents of `supabase/schemas/`, plus the generator version (the
supadart version `pubspec.lock` resolves). If there is no asset for your exact
checkout, the command says so and points you at `devtools setup`.

## supadart needs the secret key

supadart fetches the OpenAPI spec from PostgREST, and a publishable key gets a
`401`. So generation needs your project's **secret** key. That is a tooling
credential: it lives in the git-ignored `.env.tooling`, and it never becomes a
`--dart-define`, because anything compiled into an APK can be read back out of it.

> [!IMPORTANT]
> Every `--dart-define` value must be public. `.env.example` is checked in CI
> (`validate`) for keys that name a secret and values that look like one.

## A table needs a `service_role` grant to get a model

The generator reads PostgREST's spec as `service_role`, and the spec lists only
the tables that role can select. A table with no
`grant ... on table "dogpack"."x" to service_role` is silently skipped: no
`x.dart`, no error. Every table in `supabase/schemas/dogpack/tables/` carries
that grant; copy it.

## The schema and its enums

supadart reads the schema named under `schemas:` in `supadart.yaml` (`dogpack`),
which must be exposed under `[api] schemas` in `supabase/config.toml`. It reads
the Postgres enums (`classYear`, `sessionStatus`) from the database, so a new
enum needs no entry in the config. Older supadart (1.x) could only read the
`public` schema and generated code that did not compile for enums elsewhere,
which is why `pubspec.yaml` requires 2.x.

## It is a no-op until there are tables

With an empty schema tree there is nothing to generate. Once the first tables
land in `supabase/schemas/`, the models regenerate from the database every time:
the schema is always the source, the Dart is always output.
