# Vendored moderation protocol

`signing.ts`, `messages.ts` and `client.ts` are copies of
`@devdogsuga/sdk/moderation` (DevDogsUGA `packages/sdk/src/moderation`, commit
`7ce11faa`), with `.js` import specifiers changed to `.ts` because Deno resolves
files, not compiled output.

They are copies, not an import, because a deployed Edge Function
bundles an npm import with the package's whole dependency tree (the SDK also
carries Sentry, QR and Next helpers), and these three files are all it needs.
The code is the contract the platform signs with, so it must not
drift: `.github/scripts/check-vendored.mjs` (run by `validate`) compares the three
files with DevDogsUGA's source at the pinned commit and warns when main has
moved on, and `devtools moderation samples` (run by CI
against these functions) fails if the two sides disagree about a signature.

Re-vendoring: copy the three files from the source at the new commit, change
`.js` specifiers to `.ts`, keep the header and move the commit in it.
