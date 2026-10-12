# Typed models

`supabase gen types` has no Dart target, so DogPack gets its typed models from
the community [supadart](https://pub.dev/packages/supadart) generator. The
models are **never committed**: `lib/generated/` is git-ignored. You get them
one of two ways.

## Generate them from your database

```bash
npx @devdogsuga/devtools@next db sync    # make your dev database match supabase/schemas/
npx @devdogsuga/devtools@next db types   # run supadart against it
```

`db sync` regenerates the models after it changes your database. Under the hood
this is `dart run supadart`, which reads `supadart.yaml` (`output: lib/generated/`,
`separated: true`) and writes one Dart model per table.

## Download the ones CI built

```bash
npx @devdogsuga/devtools@next db types --download
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

## The default-schema constraint

supadart can only read PostgREST's **default** schema: it requests `/rest/v1/`
with no `Accept-Profile` header and offers no way to name a schema. In
`supabase/config.toml` the app's schema therefore goes **first** under
`[api] schemas`, which makes it the default profile. The ordering is neither
alphabetical nor arbitrary: do not tidy it.

## It is a no-op until there are tables

With an empty schema tree there is nothing to generate. Once the first tables
land in `supabase/schemas/`, the models regenerate from the database every time:
the schema is always the source, the Dart is always output.
