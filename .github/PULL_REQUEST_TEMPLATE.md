## Summary

<!-- What does this change do, and why? -->

## Linked issue

Closes #

## Checklist

- [ ] `flutter analyze` and `flutter test` pass locally
- [ ] Docs updated if behavior changed
- [ ] Schema changes are edits to `supabase/schemas/` with an RLS test for the allow and the deny (no hand-written migration unless the change is destructive)
- [ ] No secret in the diff, `.env.example` or a `--dart-define`
