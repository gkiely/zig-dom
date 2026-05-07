import { spawnSync } from "node:child_process";

type RunResult = {
  realSeconds: number;
  passCount: number;
  failCount: number;
};

type TimingRange = {
  max: number;
};

const strictTiming = process.argv.includes("--strict-timing");
const testFile = "../youneedawiki/src/elements/Buttons/Edit.test.tsx";
const rootDir = "../youneedawiki";
const expectedPass = 7;
const expectedFail = 0;

const coldRange: TimingRange = { max: 0.4 };
const warmRange: TimingRange = {  max: 0.16 };

const ANSI_YELLOW = "\x1b[33m";
const ANSI_RESET = "\x1b[0m";
const WARNING_ICON = "⚠";

function formatWarning(message: string): string {
  return `${ANSI_YELLOW}${WARNING_ICON} ${message}${ANSI_RESET}`;
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

function checkSummary(result: RunResult, runName: string): void {
  if (result.passCount !== expectedPass || result.failCount !== expectedFail) {
    throw new Error(
      `${runName} expected pass=${expectedPass} fail=${expectedFail}, got pass=${result.passCount} fail=${result.failCount}`
    );
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

function runTimedGuard(runName: string): RunResult {
  const output = run(
    "/usr/bin/time",
    ["-p", "zig-out/bin/zig-dom", "test", "--root", rootDir, testFile],
    runName
  );
  return parseRunOutput(output);
}

function main(): void {
  run("zig", ["build", "-Doptimize=ReleaseFast", "--summary", "none"], "ReleaseFast build");

  const cold = runTimedGuard("Edit.test.tsx perf run 1 (cold-ish)");
  const warm = runTimedGuard("Edit.test.tsx perf run 2 (immediate repeat)");

  checkSummary(cold, "Run 1");
  checkSummary(warm, "Run 2");

  const warnings: string[] = [];

  const coldTiming = checkTiming(cold, coldRange, "Run 1");
  const warmTiming = checkTiming(warm, warmRange, "Run 2");

  if (coldTiming.regressionWarning) {
    warnings.push(coldTiming.regressionWarning);
  }
  if (warmTiming.regressionWarning) {
    warnings.push(warmTiming.regressionWarning);
  }

  console.log("\nPerf guard summary:");
  console.log(`- run1 real=${cold.realSeconds.toFixed(2)}s pass=${cold.passCount} fail=${cold.failCount}`);
  console.log(`- run2 real=${warm.realSeconds.toFixed(2)}s pass=${warm.passCount} fail=${warm.failCount}`);

  if (warnings.length === 0) {
    console.log("- no slower-than-baseline regression detected");
    return;
  }

  for (const warning of warnings) {
    console.warn(formatWarning(warning));
  }

  if (strictTiming) {
    throw new Error("Timing baseline check failed with --strict-timing.");
  }

  console.warn(formatWarning("Timing baseline warnings were detected. Investigate before continuing with additional milestones."));
}

main();
