// The moderation protocol in supabase/functions/_shared/moderation is a copy of
// DevDogsUGA's packages/sdk/src/moderation (README.md there says why). The
// platform signs with that code, so a copy that drifts is a receiver that
// rejects real deliveries. This compares each copy with the source at the
// commit its header names, and says whether the source has moved on since.
//
//   node .github/scripts/check-vendored.mjs [--offline]
//
// Differences allowed: the header comment, and `.js` import specifiers written
// `.ts` for Deno. Anything else fails. A network failure is a warning, not a
// failure (the check must not be flaky), unless --offline is not given and the
// comparison itself found a difference.
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const dir = join(root, "supabase/functions/_shared/moderation");
const files = readdirSync(dir).filter((f) => f.endsWith(".ts"));

/** Strip the leading `// VENDORED ...` comment lines; return the pinned commit too. */
export function split(copy) {
  const lines = copy.split("\n");
  let i = 0;
  while (i < lines.length && lines[i].startsWith("//")) i++;
  const header = lines.slice(0, i).join("\n");
  const sha = /DevDogsUGA ([0-9a-f]{7,40})/.exec(header)?.[1] ?? null;
  return { sha, body: lines.slice(i).join("\n") };
}

/** What the source must look like once its specifiers are written for Deno. */
export function forDeno(source) {
  return source.replace(/(from\s+["']\.\/[^"']+)\.js(["'])/g, "$1.ts$2");
}

async function fetchSource(ref, name) {
  const url = `https://raw.githubusercontent.com/DevDogsUGA/DevDogsUGA/${ref}/packages/sdk/src/moderation/${name}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return await response.text();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let failed = false;
  let unreachable = false;
  for (const name of files) {
    const { sha, body } = split(readFileSync(join(dir, name), "utf8"));
    if (!sha) {
      console.error(`${name}: the header names no DevDogsUGA commit`);
      failed = true;
      continue;
    }
    try {
      const pinned = forDeno(await fetchSource(sha, name));
      if (pinned.trimEnd() !== body.trimEnd()) {
        console.error(`${name}: differs from packages/sdk/src/moderation/${name} at ${sha}`);
        failed = true;
        continue;
      }
      console.log(`ok - ${name} matches DevDogsUGA ${sha}`);
      const head = forDeno(await fetchSource("main", name)).trimEnd();
      if (head !== body.trimEnd()) {
        console.warn(`::warning::${name}: DevDogsUGA main has changed this file since ${sha}; re-vendor it and move the pin.`);
      }
    } catch (error) {
      unreachable = true;
      console.warn(`::warning::${name}: could not compare (${error.message})`);
    }
  }
  if (failed) process.exit(1);
  if (unreachable) console.warn("Some copies could not be compared; not a failure.");
}
