import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join, relative, sep } from "node:path";

type RunResult = {
  realSeconds: number;
  passCount: number;
  failCount: number;
};

type TimingRange = {
  max: number;
};

type PerfTarget = {
  label: string;
  testFile: string;
  expectedPass: number | null;
  expectedFail: number;
  timing: {
    cold: TimingRange;
    warm: TimingRange;
  } | null;
};

function parseNumberFlag(name: string, defaultValue: number): number {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) return defaultValue;
  const parsed = Number.parseInt(process.argv[index + 1] ?? "", 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return defaultValue;
  return parsed;
}

function parseStringFlag(name: string): string | null {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) return null;
  return process.argv[index + 1] ?? null;
}

function positionalArgs(): string[] {
  const args: string[] = [];
  const flagsWithValues = new Set(["--runs", "--file"]);

  for (let index = 2; index < process.argv.length; index += 1) {
    const arg = process.argv[index]!;
    if (flagsWithValues.has(arg)) {
      index += 1;
      continue;
    }
    if (arg.startsWith("--")) continue;
    args.push(arg);
  }

  return args;
}

const runCount = parseNumberFlag("--runs", 2);
const rootDir = "../youneedawiki";

const ANSI_YELLOW = "\x1b[33m";
const ANSI_RESET = "\x1b[0m";
const WARNING_ICON = "⚠";

function formatWarning(message: string): string {
  return `${ANSI_YELLOW}${WARNING_ICON} ${message}${ANSI_RESET}`;
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

function resolveTestFile(input: string): string {
  if (existsSync(input)) return input;

  const rooted = join(rootDir, input);
  if (existsSync(rooted)) return rooted;

  const normalizedInput = input.toLowerCase();
  const pathLikeInput = normalizedInput.includes("/") || normalizedInput.includes("\\");
  const matches = listTestFiles(rootDir)
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
    throw new Error(`Could not find downstream test file matching "${input}" under ${rootDir}.`);
  }
  if (matches.length > 1) {
    throw new Error(`Ambiguous downstream test file "${input}". Matches:\n${matches.map((file) => `- ${file}`).join("\n")}`);
  }

  return matches[0]!;
}

function targetFromArgs(): PerfTarget {
  const input = parseStringFlag("--file") ?? positionalArgs()[0] ?? null;
  if (!input) {
    return {
      label: "Edit.test.tsx",
      testFile: "../youneedawiki/src/elements/Buttons/Edit.test.tsx",
      expectedPass: 7,
      expectedFail: 0,
      timing: {
        cold: { max: 1 },
        warm: { max: 0.15 }
      }
    };
  }

  const testFile = resolveTestFile(input);
  return {
    label: relative(rootDir, testFile) || testFile,
    testFile,
    expectedPass: null,
    expectedFail: 0,
    timing: null
  };
}

function run(command: string, args: string[], label: string): string {
  console.log(`\n--- ${label} ---`);
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["inherit", "pipe", "pipe"]
  });

  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const code = result.status ?? 1;
    throw new Error(`${label} failed with exit code ${code}`);
  }

  return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
}

function parseRunOutput(output: string): RunResult {
  const passFail = /pass=(\d+)[\s\S]*?fail=(\d+)/.exec(output);
  if (!passFail) {
    throw new Error("Could not parse pass/fail summary from test output.");
  }

  const realMatch = /^real\s+([0-9]+(?:\.[0-9]+)?)$/m.exec(output);
  if (!realMatch) {
    throw new Error("Could not parse '/usr/bin/time -p' real seconds from test output.");
  }

  return {
    realSeconds: Number.parseFloat(realMatch[1] ?? "NaN"),
    passCount: Number.parseInt(passFail[1] ?? "", 10),
    failCount: Number.parseInt(passFail[2] ?? "", 10)
  };
}

function checkSummary(result: RunResult, runName: string, target: PerfTarget): void {
  if (target.expectedPass !== null && result.passCount !== target.expectedPass) {
    throw new Error(
      `${runName} expected pass=${target.expectedPass}, got pass=${result.passCount}`
    );
  }
  if (result.failCount !== target.expectedFail) {
    throw new Error(`${runName} expected fail=${target.expectedFail}, got fail=${result.failCount}`);
  }
}

type TimingCheck = {
  regressionWarning: string | null;
};

function checkTiming(result: RunResult, range: TimingRange, runName: string): TimingCheck {
  if (result.realSeconds > range.max) {
    return {
      regressionWarning: `${runName} real=${result.realSeconds.toFixed(2)}s slower than baseline max ${range.max.toFixed(2)}s`
    };
  }

  return {
    regressionWarning: null
  };
}

function runTimedGuard(runName: string, target: PerfTarget): RunResult {
  const output = run(
    "/usr/bin/time",
    ["-p", "zig-out/bin/zig-dom", "test", "--root", rootDir, target.testFile],
    runName
  );
  return parseRunOutput(output);
}

function main(): void {
  const target = targetFromArgs();

  run("zig", ["build", "-Doptimize=ReleaseFast", "--summary", "none"], "ReleaseFast build");

  const runs: RunResult[] = [];
  for (let index = 0; index < runCount; index += 1) {
    const runName =
      index === 0
        ? `${target.label} perf run 1 (cold-ish)`
        : `${target.label} perf run ${index + 1} (immediate repeat)`;
    runs.push(runTimedGuard(runName, target));
  }

  for (let index = 0; index < runs.length; index += 1) {
    checkSummary(runs[index]!, `Run ${index + 1}`, target);
  }

  const warnings: string[] = [];

  if (target.timing) {
    for (let index = 0; index < runs.length; index += 1) {
      const range = index === 0 ? target.timing.cold : target.timing.warm;
      const check = checkTiming(runs[index]!, range, `Run ${index + 1}`);
      if (check.regressionWarning) {
        warnings.push(check.regressionWarning);
      }
    }
  }

  console.log("\nPerf guard summary:");
  runs.forEach((result, index) => {
    console.log(`- run${index + 1} real=${result.realSeconds.toFixed(2)}s pass=${result.passCount} fail=${result.failCount}`);
  });

  if (!target.timing) {
    console.log("- timing baseline skipped for custom target");
    return;
  }

  if (warnings.length === 0) {
    console.log("- no slower-than-baseline regression detected");
    return;
  }

  for (const warning of warnings) {
    console.warn(formatWarning(warning));
  }

  console.warn(formatWarning("Timing baseline warnings were detected. Investigate before continuing with additional milestones."));
}

main();
