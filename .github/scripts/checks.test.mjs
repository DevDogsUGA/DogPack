// The two Node checks that gate pull requests are themselves tested, so a
// regex change cannot quietly stop catching what it exists to catch.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const scripts = dirname(fileURLToPath(import.meta.url));

function run(script, args, cwd) {
  return spawnSync(process.execPath, [join(scripts, script), ...args], { cwd, encoding: "utf8" });
}

function envFile(contents) {
  const dir = mkdtempSync(join(tmpdir(), "dogpack-env-"));
  const file = join(dir, ".env.example");
  writeFileSync(file, contents);
  return { dir, file };
}

test("a public .env.example passes", () => {
  const { dir, file } = envFile(
    [
      "# Public values only.",
      "SUPABASE_URL=https://dogpack.supabase.co",
      "SUPABASE_PUBLISHABLE_KEY=sb_publishable_abc123",
      "",
    ].join("\n"),
  );
  assert.equal(run("check-env-example.mjs", [file], dir).status, 0);
});

test("a missing .env.example passes", () => {
  const dir = mkdtempSync(join(tmpdir(), "dogpack-env-"));
  assert.equal(run("check-env-example.mjs", [join(dir, ".env.example")], dir).status, 0);
});

for (const [name, line] of [
  ["a secret key by name", "SECRET_KEY=whatever"],
  ["a service-role key by name", "SUPABASE_SERVICE_ROLE_KEY=x"],
  ["a database URL by name", "DB_URL=postgres://localhost/db"],
  ["a Supabase secret key by value", "SOMETHING=sb_secret_abcdefghijklmnop"],
  ["a JWT by value", "SOMETHING=eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl"],
  ["a database URL with a password by value", "SOMETHING=postgresql://postgres:hunter2@db.example.com:5432/postgres"],
  ["a GitHub token by value", "SOMETHING=ghp_abcdefghijklmnopqrstuvwxyz0123456789"],
]) {
  test(`.env.example with ${name} fails`, () => {
    const { dir, file } = envFile(`${line}\n`);
    const result = run("check-env-example.mjs", [file], dir);
    assert.equal(result.status, 1, result.stdout + result.stderr);
  });
}

test("the Markdown link check flags a missing file and a missing heading", () => {
  const dir = mkdtempSync(join(tmpdir(), "dogpack-docs-"));
  mkdirSync(join(dir, "docs"));
  writeFileSync(join(dir, "docs", "a.md"), "# A\n\n## Real heading\n");
  writeFileSync(
    join(dir, "README.md"),
    [
      "[ok](docs/a.md)",
      "[ok heading](docs/a.md#real-heading)",
      "[external](https://example.com/x)",
      "`[in code](nope.md)`",
      "```",
      "[in fence](nope.md)",
      "```",
    ].join("\n"),
  );
  assert.equal(run("check-docs.mjs", [], dir).status, 0);

  writeFileSync(join(dir, "README.md"), "[gone](docs/b.md)\n");
  assert.equal(run("check-docs.mjs", [], dir).status, 1);

  writeFileSync(join(dir, "README.md"), "[bad](docs/a.md#no-such-heading)\n");
  assert.equal(run("check-docs.mjs", [], dir).status, 1);
});
