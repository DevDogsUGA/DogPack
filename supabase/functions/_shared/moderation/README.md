# Vendored moderation protocol

`signing.ts`, `messages.ts` and `client.ts` are copies of
`@devdogsuga/sdk/moderation` (DevDogsUGA `packages/sdk/src/moderation`, commit
`7ce11faa`), with `.js` import specifiers changed to `.ts` because Deno resolves
files, not compiled output.

They are copies, not an import, because `@devdogsuga/sdk` had no published
prerelease when DogPack's backend was written (npm held only the `0.0.0`
placeholder). The code is the contract the platform signs with, so it must not
drift: `.github/scripts/check-vendored.mjs` compares the three files with the
published package once it exists, and `devtools moderation samples` (run by CI
against these functions) fails if the two sides disagree about a signature.

When `@devdogsuga/sdk` has a `next` release: delete this folder, import
`npm:@devdogsuga/sdk@next/moderation` in the three functions, and delete
`check-vendored.mjs`.
