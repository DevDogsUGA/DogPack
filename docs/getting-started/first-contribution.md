# Your first contribution

A first change that touches nothing risky: edit some visible text or the theme
on the home screen, see it render, and open a pull request. It exercises your
Flutter install, your emulator and the repository's checks before you touch
anything that talks to Supabase.

## Prerequisites

- The [Flutter SDK](https://docs.flutter.dev/get-started/install) on your `PATH`
  (`flutter --version`), and an Android emulator or a phone. iPhone users need a
  Mac to run the app from source.
- Git, and a fork of this repository if you are not on the DevDogs team.

## Make a UI-only change

Open `lib/main.dart`. `StudyGroupFinderApp` is the whole app today: a
`MaterialApp` with a Material 3 theme (`colorSchemeSeed: const Color(0xFFBA0C2F)`)
and a `Scaffold` whose body is a centred `Text`. Change the label, or try a
different `colorSchemeSeed`. Nothing here touches Supabase, so there is nothing
to break.

## Run it

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=http://localhost:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=placeholder
```

The app initializes the Supabase client at start-up, which needs *a* URL and key
but makes no request, so the placeholders are enough for a UI change. Press `r`
in the terminal for hot reload.

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
