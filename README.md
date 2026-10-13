# DogPack

DogPack is DevDogs' app for finding and forming study groups with other UGA
students: onboarding with your courses, creating and joining sessions, and a
discover feed of what is happening in your classes. It is built by DevDogs
members, one small issue at a time.

- **App:** Flutter, Android and iOS (`dev.dogpack`). No web build.
- **Backend:** its own Supabase project. Access is Row Level Security all the way
  down, and the schema is plain SQL in `supabase/schemas/`.
- **Sign-in:** "Sign in with DevDogs", through the DevDogs platform.

The app is at the skeleton stage: the repository, CI and docs are in place and
the features arrive milestone by milestone (below).

## Contribute

1. Read [Your first contribution](docs/getting-started/first-contribution.md).
2. Pick an issue labelled [`good first issue`](https://github.com/DevDogsUGA/DogPack/labels/good%20first%20issue).
   Each takes under an hour, names the file it touches and states how to check it.
   Setup is one command, `pnpm devtools setup` (the same one DogDays uses).
3. Open a pull request. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules; the DogPack
   leads review.

Stuck, or something in the docs is wrong? Ask in the club Discord instead of
guessing.

## Roadmap

Work is grouped into [milestones](https://github.com/DevDogsUGA/DogPack/milestones),
one per feature. The dates are the weeks the feature is due.

| Milestone | Due |
| --- | --- |
| Polish (branded sign-in, states, accessibility, empty states, copy) | rolling |
| Onboarding + Enrollments | Oct 26 |
| Profile (view and edit, enrollment changes, delete my data) | Nov 2 |
| Sessions: create, edit, cancel | Nov 2 |
| Discover + Join/Leave | Nov 9 |
| Report & Block | Nov 16 |
| Complete (runbook, handoff) | Dec 2 |
| Store Release (stretch) | |

Future milestones, sliced when a spring group picks them up: Reminders, Session
Chat, Live Updates, Profile Photos, Find a Time, CRN Enrollments, Offline Cache.

## Documentation

- [Docs index](docs/index.md): how the pieces fit
- [Where things live](docs/guides/where-things-live.md)
- [Testing](docs/guides/testing.md): what CI checks
- [Schema change loop](docs/guides/schema-change-loop.md): adding a table, with RLS
- [Typed models](docs/guides/typed-models.md): the generated Dart models

## License

[BSD 3-Clause](LICENSE).
