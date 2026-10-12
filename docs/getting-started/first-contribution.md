# Your first contribution

A first change that touches nothing risky: edit some visible text or the theme
on the home screen, see it render, and open a pull request. It exercises your
Flutter install, your emulator and the repository's checks before you change
anything that talks to the database.

## Prerequisites

- The [Flutter SDK](https://docs.flutter.dev/get-started/install) on your `PATH`
  (`flutter --version`), and an Android emulator or a phone. iPhone users need a
  Mac to run the app from source.
- Git, and a fork of this repository if you are not on the DevDogs team.

## Set up

```bash
npx @devdogsuga/devtools@next setup
```

This writes `.env` from [`.env.example`](../../.env.example) with your own
Supabase project (a local Docker stack, or a hosted project of your own), applies
the schema, fetches the generated models and registers "Sign in with DevDogs" on
your project. `.env` holds public values only: it is compiled into the app.
Secrets (the database URL, the secret key) go to `.env.tooling`, which the app
never reads.

## Run it

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

In VS Code, the **DogPack** launch configuration does the same. It first runs
`node .github/scripts/check-env-example.mjs .env` and refuses to start if `.env`
holds a secret key or a database URL, because anything compiled into an APK can
be read back out of it.

On an Android emulator `127.0.0.1` is the emulator itself, so a local stack's URL
in `.env` should be `http://10.0.2.2:54321`.

The app opens on **Sign in with DevDogs**. Sign in once, then fill your database
with believable classmates and sessions:

```bash
npx @devdogsuga/devtools@next dev-data
```

It runs [`supabase/dev-data.sql`](../../supabase/dev-data.sql) as the member who
signed in last, refuses DogPack's production project, and is safe to run again.

## Make a UI-only change

`lib/screens/home_screen.dart` is the signed-in home. Change its text, or the
brand theme in `lib/app.dart`, and press `r` in the terminal for hot reload. If you change text a test looks for
(`test/gate_test.dart` finds `Study sessions will show up here.`), change the
assertion with it, or `flutter test` and the `flutter` check go red. The
sign-in gate is `gateRedirect` in `lib/router.dart`; read it before you add a
screen, because every new screen sits behind it.

## Check it

```bash
flutter analyze
flutter test
```

These are what the `flutter` check runs on your pull request. Neither needs a
database.

## Open a pull request

Branch from `main`, keep the commit focused (`type(scope): subject`, for example
`feat(onboarding): add the name step`), link the issue it closes, and open a
pull request against `main`. [CONTRIBUTING.md](../../CONTRIBUTING.md) has the
rest, including who reviews: `.github/CODEOWNERS` routes your pull request to the
DogPack leads.

When your work needs a new table, [Schema change loop](../guides/schema-change-loop.md)
is the next page.
