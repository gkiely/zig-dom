import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join, sep } from "node:path";

const downstreamRoot = "../youneedawiki";
const searchRoots = ["tests/runner", downstreamRoot];

type TestTarget = {
  root: string | null;
  file: string;
};

type TestTargetGroup = {
  root: string | null;
  files: string[];
};

function parsePositiveSeconds(value: string | undefined): number | null {
  const parsed = Number.parseFloat(value ?? "");
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function splitArgs(): { input: string | null; runnerArgs: string[]; timeoutMs: number } {
  const args = process.argv.slice(2);
  const runnerArgs: string[] = [];
  let input: string | null = null;
  let timeoutMs = 10_000;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]!;
    if (arg === "--timeout") {
      const timeoutSeconds = parsePositiveSeconds(args[index + 1]);
      if (timeoutSeconds === null) {
        throw new Error("--timeout must be a positive number of seconds.");
      }
      timeoutMs = timeoutSeconds * 1000;
      index += 1;
      continue;
    }

    if (arg.startsWith("--timeout=")) {
      const timeoutSeconds = parsePositiveSeconds(arg.slice("--timeout=".length));
      if (timeoutSeconds === null) {
        throw new Error("--timeout must be a positive number of seconds.");
      }
      timeoutMs = timeoutSeconds * 1000;
      continue;
    }

    if (!arg.startsWith("--") && input === null) {
      input = arg;
      continue;
    }

    runnerArgs.push(arg);
  }

  return { input, runnerArgs, timeoutMs };
}

function listTestFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;

    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listTestFiles(path));
      continue;
    }

    if (/\.test\.[cm]?[tj]sx?$/.test(entry.name)) {
      files.push(path);
    }
  }
  return files;
}

function defaultTests(): string[] {
  const nativeDomTests = listTestFiles("tests/runner")
    .filter((file) => {
      const basename = file.split(sep).at(-1) ?? "";
      return basename.startsWith("native-dom-") && basename.endsWith(".test.js");
    })
    .sort();

  return [
    ...nativeDomTests,
    "tests/runner/dom-auto-plain.test.ts",
    "tests/runner/dom-auto-tsx.test.tsx",
    "tests/runner/mock-spy.test.ts",
    "tests/runner/plugin-onload.test.ts",
    "tests/runner/testing-library-role.test.js"
  ];
}

function targetForPath(path: string): TestTarget {
  return {
    root: path.startsWith(`${downstreamRoot}/`) ? downstreamRoot : null,
    file: path
  };
}

function groupTargets(targets: TestTarget[]): TestTargetGroup[] {
  const groups: TestTargetGroup[] = [];
  for (const target of targets) {
    let group = groups.find((candidate) => candidate.root === target.root);
    if (!group) {
      group = { root: target.root, files: [] };
      groups.push(group);
    }
    group.files.push(target.file);
  }
  return groups;
}

function resolveTestFiles(input: string): TestTargetGroup[] {
  if (existsSync(input)) return groupTargets([targetForPath(input)]);

  const downstreamPath = join(downstreamRoot, input);
  if (existsSync(downstreamPath)) return groupTargets([targetForPath(downstreamPath)]);

  const normalizedInput = input.toLowerCase();
  const pathLikeInput = normalizedInput.includes("/") || normalizedInput.includes("\\");
  const matches = searchRoots
    .flatMap(listTestFiles)
    .filter((file) => {
      const normalized = file.toLowerCase();
      const basename = file.split(sep).at(-1)?.toLowerCase() ?? "";
      if (pathLikeInput) {
        return normalized.includes(normalizedInput);
      }
      return basename.startsWith(normalizedInput);
    })
    .sort();

  if (matches.length === 0) {
    throw new Error(`Could not find .test file matching "${input}".`);
  }

  return groupTargets(matches.map(targetForPath));
}

function run(args: string[], timeoutMs: number): number {
  const result = spawnSync("zig", args, {
    encoding: "utf8",
    stdio: "inherit",
    timeout: timeoutMs
  });

  if (result.error && 'code' in result.error && result.error.code === "ETIMEDOUT") {
    console.error(`build:dev timed out after ${(timeoutMs / 1000).toFixed(1)}s. Increase with --timeout <seconds>.`);
    return 124;
  }
  if (result.error) throw result.error;
  return result.status ?? 1;
}

const { input, runnerArgs, timeoutMs } = splitArgs();
const testArgGroups = input
  ? (() => {
      const groups = resolveTestFiles(input);
      if (groups.length > 1) {
        const matches = groups.flatMap((group) => group.files).map((file) => `- ${file}`).join("\n");
        throw new Error(`Matched tests from multiple roots. Use a more specific token.\n${matches}`);
      }
      const group = groups[0]!;
      return [group.root ? [...runnerArgs, "--root", group.root, ...group.files] : [...runnerArgs, ...group.files]];
    })()
  : [[...runnerArgs, ...defaultTests()]];

let exitCode = 0;
for (const testArgs of testArgGroups) {
  const result = run(["build", "test", "run", "-Doptimize=Debug", "--summary", "none", "--", "test", ...testArgs], timeoutMs);
  if (result !== 0) exitCode = result;
}
process.exit(exitCode);
