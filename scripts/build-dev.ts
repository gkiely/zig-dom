import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join, sep } from "node:path";

const downstreamRoot = "../youneedawiki";
const searchRoots = ["tests/runner", downstreamRoot];

type TestTarget = {
  root: string | null;
  file: string;
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

function resolveTestFile(input: string): TestTarget {
  if (existsSync(input)) return targetForPath(input);

  const downstreamPath = join(downstreamRoot, input);
  if (existsSync(downstreamPath)) return targetForPath(downstreamPath);

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
  if (matches.length > 1) {
    throw new Error(`Ambiguous .test file "${input}". Matches:\n${matches.map((file) => `- ${file}`).join("\n")}`);
  }

  return targetForPath(matches[0]!);
}

function run(args: string[], timeoutMs: number): void {
  const result = spawnSync("zig", args, {
    encoding: "utf8",
    stdio: "inherit",
    timeout: timeoutMs
  });

  if (result.error && 'code' in result.error && result.error.code === "ETIMEDOUT") {
    console.error(`build:dev timed out after ${(timeoutMs / 1000).toFixed(1)}s. Increase with --timeout <seconds>.`);
    process.exit(124);
  }
  if (result.error) throw result.error;
  process.exit(result.status ?? 1);
}

const { input, runnerArgs, timeoutMs } = splitArgs();
const testArgs = input
  ? (() => {
      const target = resolveTestFile(input);
      return target.root ? [...runnerArgs, "--root", target.root, target.file] : [...runnerArgs, target.file];
    })()
  : [...runnerArgs, ...defaultTests()];

run(["build", "test", "run", "-Doptimize=Debug", "--summary", "none", "--", "test", ...testArgs], timeoutMs);
