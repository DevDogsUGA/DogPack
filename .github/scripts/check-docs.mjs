/**
 * Every relative link in the Markdown of this repository points at a file that
 * exists (and, for `#fragment` links, at a heading that exists).
 *
 * No dependencies: Node alone. Runs from the repository root.
 *
 *   node .github/scripts/check-docs.mjs
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const root = process.cwd();
const skip = new Set([".git", "node_modules", ".dart_tool", "build", "ios", "android"]);

/** @param {string} dir @returns {string[]} */
function markdownFiles(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...markdownFiles(path));
    else if (entry.name.endsWith(".md")) found.push(path);
  }
  return found;
}

/** GitHub's heading anchors: lowercase, punctuation dropped, spaces to hyphens. */
function anchorsOf(text) {
  const anchors = new Set();
  let inFence = false;
  for (const line of text.split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;
    const heading = !inFence && /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    if (!heading) continue;
    anchors.add(
      heading[1]
        .toLowerCase()
        .replace(/`/g, "")
        .replace(/[^\p{L}\p{N}\s-]/gu, "")
        .trim()
        .replace(/\s/g, "-"),
    );
  }
  return anchors;
}

const problems = [];
for (const file of markdownFiles(root)) {
  const text = readFileSync(file, "utf8");
  // Links inside code fences are examples, not links.
  const prose = text.replace(/```[\s\S]*?```/g, "").replace(/`[^`\n]*`/g, "");
  for (const match of prose.matchAll(/\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
    const target = match[1];
    if (/^([a-z][a-z0-9+.-]*:|\/\/)/i.test(target)) continue;
    const [pathPart, fragment] = target.split("#");
    const destination = pathPart === "" ? file : resolve(dirname(file), pathPart);
    const shown = `${relative(root, file)}: (${target})`;
    if (!existsSync(destination)) {
      problems.push(`${shown} does not exist`);
      continue;
    }
    if (fragment && statSync(destination).isFile() && destination.endsWith(".md")) {
      if (!anchorsOf(readFileSync(destination, "utf8")).has(fragment.toLowerCase())) {
        problems.push(`${shown} has no heading #${fragment}`);
      }
    }
  }
}

if (problems.length > 0) {
  console.error(`${problems.length} broken link(s):\n${problems.map((p) => `  ${p}`).join("\n")}`);
  process.exit(1);
}
console.log("Every relative link in the Markdown resolves.");
