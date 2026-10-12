/**
 * `.env.example` ships in the app: its keys become `--dart-define` values
 * compiled into the binary, and anything compiled in can be read back out of
 * the APK. So it holds public values only (Q27). This rejects a key that
 * names a secret and a value that looks like one.
 *
 *   node .github/scripts/check-env-example.mjs [path]
 *
 * A repository with no `.env.example` yet passes.
 */
import { existsSync, readFileSync } from "node:fs";

const file = process.argv[2] ?? ".env.example";
if (!existsSync(file)) {
  console.log(`${file} does not exist yet: nothing to check.`);
  process.exit(0);
}

// Keys that are public by name: Supabase's publishable key is meant to ship.
const PUBLIC_KEY = /(^|_)PUBLISHABLE(_|$)|(^|_)ANON(_|$)/;
const SECRET_KEY = /SECRET|PRIVATE|SERVICE_?ROLE|PASSWORD|PASSWD|TOKEN|CREDENTIAL|DB_URL|DATABASE_URL|API_?KEY|SIGNING/i;
const SECRET_VALUE = [
  [/^sb_secret_/, "a Supabase secret key"],
  [/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/, "a JWT (a service-role key is one)"],
  [/^postgres(ql)?:\/\/[^:]+:[^@]+@/, "a database URL with a password"],
  [/^(ghp|gho|ghs|github_pat)_/, "a GitHub token"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"],
  [/^AKIA[0-9A-Z]{16}$/, "an AWS access key"],
];

const problems = [];
const lines = readFileSync(file, "utf8").split("\n");
lines.forEach((raw, index) => {
  const line = raw.trim();
  if (line === "" || line.startsWith("#")) return;
  const eq = line.indexOf("=");
  if (eq === -1) {
    problems.push(`${file}:${index + 1}: not KEY=value`);
    return;
  }
  const key = line.slice(0, eq).replace(/^export\s+/, "").trim();
  const value = line.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
  if (SECRET_KEY.test(key) && !PUBLIC_KEY.test(key)) {
    problems.push(`${file}:${index + 1}: ${key} is named like a secret. Secrets live in .env.tooling, never in the app's defines.`);
  }
  for (const [pattern, what] of SECRET_VALUE) {
    if (pattern.test(value)) problems.push(`${file}:${index + 1}: ${key} holds ${what}.`);
  }
});

if (problems.length > 0) {
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log(`${file} holds public values only.`);
