import { writeFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const failureFile = join(root, "examples", "bun-react-smoke", "failures.md");

const result = Bun.spawnSync(["bun", "test", "tests/integration/react/render.test.tsx"], {
  cwd: root,
  stdout: "pipe",
  stderr: "pipe"
});

const output = `${result.stdout.toString()}\n${result.stderr.toString()}`;

if (result.exitCode === 0) {
  const success = [
    "# React Smoke Failures",
    "",
    "No missing APIs detected in the current smoke test run.",
    ""
  ].join("\n");
  writeFileSync(failureFile, success);
  console.log("React smoke passed");
  process.exit(0);
}

const missing = new Set<string>();
for (const match of output.matchAll(/(?:TypeError|ReferenceError):\s*([A-Za-z0-9_$.]+)/g)) {
  missing.add(match[1]);
}
for (const match of output.matchAll(/Cannot read properties of .*?\(reading '([^']+)'\)/g)) {
  missing.add(match[1]);
}

const stackLines = output
  .split("\n")
  .filter((line) => /TypeError|ReferenceError|at\s+/.test(line))
  .slice(0, 20);

const report = [
  "# React Smoke Failures",
  "",
  "## Missing APIs",
  ...Array.from(missing).sort().map((name) => `- ${name}`),
  "",
  "## Representative Stack",
  "```text",
  ...stackLines,
  "```",
  ""
].join("\n");

writeFileSync(failureFile, report);
console.error("React smoke failed. Missing API summary written to examples/bun-react-smoke/failures.md");
console.error(output);
process.exit(result.exitCode || 1);
