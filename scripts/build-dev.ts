import { spawn } from "node:child_process";
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

async function run(args: string[], timeoutMs: number, label: string): Promise<number> {
  const child = spawn("zig", args, {
    detached: true,
    stdio: "inherit"
  });

  return await new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        process.kill(-child.pid!, "SIGTERM");
      } catch {}
      setTimeout(() => {
        try {
          process.kill(-child.pid!, "SIGKILL");
        } catch {}
      }, 500).unref();
      console.error(`build:dev timed out after ${(timeoutMs / 1000).toFixed(1)}s. Increase with --timeout <seconds>.`);
      resolve(124);
    }, timeoutMs);

    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });

    child.on("exit", (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(code ?? (signal ? 1 : 0));
    });
  });
}

const { input, runnerArgs, timeoutMs } = splitArgs();
const testArgGroups: { label: string; args: string[] }[] = input
  ? (() => {
      const groups = resolveTestFiles(input);
      return groups.map((group) => {
        const label = group.root ? `${group.files.length} downstream test file${group.files.length === 1 ? "" : "s"}` : `${group.files.length} local test file${group.files.length === 1 ? "" : "s"}`;
        return {
          label,
          args: group.root ? [...runnerArgs, "--root", group.root, ...group.files] : [...runnerArgs, ...group.files]
        };
      });
    })()
  : [{ label: "default development validation", args: [...runnerArgs, ...defaultTests()] }];

let exitCode = 0;
for (const group of testArgGroups) {
  const result = await run(["build", "test", "run", "-Doptimize=Debug", "--summary", "none", "--", "test", ...group.args], timeoutMs, group.label);
  if (result === 124) process.exit(124);
  if (result !== 0) exitCode = result;
}
process.exit(exitCode);
