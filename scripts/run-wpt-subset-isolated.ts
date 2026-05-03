import { readFileSync } from "node:fs";

declare const Bun: {
  spawn(
    cmd: string[],
    options: {
      cwd: string;
      stdout: "pipe";
      stderr: "pipe";
      env: Record<string, string | undefined>;
    }
  ): {
    exited: Promise<number>;
    stdout: ReadableStream<Uint8Array>;
    stderr: ReadableStream<Uint8Array>;
    kill(): void;
  };
};

type ManifestEntry = {
  file: string;
  variant?: string;
  variants?: string[];
};

type Manifest = {
  tests: ManifestEntry[];
};

type Summary = {
  pass: number;
  fail: number;
  expectedFail: number;
  unexpectedPass: number;
};

function arg(name: string): string {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    throw new Error(`Missing argument ${name}`);
  }
  return process.argv[index + 1];
}

function optionalArg(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return undefined;
  }
  return process.argv[index + 1];
}

function optionalNumberArg(name: string): number | undefined {
  const value = optionalArg(name);
  if (value == null) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid numeric argument for ${name}: ${value}`);
  }
  return parsed;
}

function expandEntryVariants(entry: ManifestEntry): Array<string | undefined> {
  const single = entry.variant?.trim();
  const many = entry.variants?.map((variant) => variant.trim()).filter((variant) => variant.length > 0) ?? [];

  if (single && many.length > 0) {
    throw new Error(`Manifest entry for ${entry.file} cannot define both variant and variants.`);
  }

  if (single) {
    return [single];
  }

  if (many.length > 0) {
    return many;
  }

  return [undefined];
}

function parseSummary(output: string): Summary | null {
  const match = output.match(/SUMMARY\s+pass=(\d+)\s+fail=(\d+)\s+expected_fail=(\d+)\s+unexpected_pass=(\d+)/);
  if (!match) {
    return null;
  }

  return {
    pass: Number.parseInt(match[1], 10),
    fail: Number.parseInt(match[2], 10),
    expectedFail: Number.parseInt(match[3], 10),
    unexpectedPass: Number.parseInt(match[4], 10)
  };
}

const manifestPath = arg("--manifest");
const expectedPath = arg("--expected");
const wptRootPath = optionalArg("--wpt-root") ?? ".wpt-cache/web-platform-tests";
const entryTimeoutMs = optionalNumberArg("--entry-timeout-ms") ?? 1000;
const progressEvery = optionalNumberArg("--progress-every") ?? 10;
const startEntry = optionalNumberArg("--start-entry") ?? 0;
const entryCount = optionalNumberArg("--entry-count");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;

const expandedEntries: Array<{ entry: ManifestEntry; variant: string | undefined }> = [];
for (const entry of manifest.tests) {
  for (const variant of expandEntryVariants(entry)) {
    expandedEntries.push({ entry, variant });
  }
}

const selectedEntries = entryCount == null
  ? expandedEntries.slice(startEntry)
  : expandedEntries.slice(startEntry, startEntry + entryCount);

console.log(`RUN_WINDOW selected=${selectedEntries.length} start=${startEntry} total=${expandedEntries.length} isolated=true`);

let passed = 0;
let failed = 0;
let expectedFail = 0;
let unexpectedPass = 0;

for (let index = 0; index < selectedEntries.length; index += 1) {
  const absoluteIndex = startEntry + index;
  const current = selectedEntries[index];

  const commandArgs = [
    "run",
    "scripts/run-wpt-subset.ts",
    "--manifest",
    manifestPath,
    "--expected",
    expectedPath,
    "--wpt-root",
    wptRootPath,
    "--entry-timeout-ms",
    String(entryTimeoutMs),
    "--progress-every",
    "0",
    "--start-entry",
    String(absoluteIndex),
    "--entry-count",
    "1"
  ];

  const child = Bun.spawn(["bun", ...commandArgs], {
    cwd: process.cwd(),
    stdout: "pipe",
    stderr: "pipe",
    env: process.env
  });

  let timedOut = false;
  const timeoutHandle = setTimeout(() => {
    timedOut = true;
    child.kill();
  }, entryTimeoutMs + 250);

  const exitCode = await child.exited;
  clearTimeout(timeoutHandle);

  const stdout = await new Response(child.stdout).text();
  const stderr = await new Response(child.stderr).text();
  const combined = `${stdout}\n${stderr}`;

  if (timedOut) {
    failed += 1;
    console.log(`FAIL ${current.entry.file} :: __timeout__ :: timed out after ${entryTimeoutMs}ms`);
  } else {
    const summary = parseSummary(combined);
    if (summary) {
      passed += summary.pass;
      failed += summary.fail;
      expectedFail += summary.expectedFail;
      unexpectedPass += summary.unexpectedPass;
    } else if (exitCode !== 0) {
      failed += 1;
      const lastLine = combined.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).slice(-1)[0] ?? "unknown";
      console.log(`FAIL ${current.entry.file} :: __entry__ :: ${lastLine}`);
    }

    if (exitCode !== 0) {
      const interesting = combined
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.startsWith("FAIL ") || line.startsWith("EXPECTED_FAIL ") || line.startsWith("UNEXPECTED_PASS "));
      for (const line of interesting) {
        console.log(line);
      }
    }
  }

  const processed = index + 1;
  if (progressEvery > 0 && (processed % progressEvery === 0 || processed === selectedEntries.length)) {
    console.log(`PROGRESS entries=${processed}/${selectedEntries.length} absolute=${absoluteIndex + 1}/${expandedEntries.length} file=${current.entry.file}`);
  }
}

const unexpectedFail = failed - expectedFail;
console.log(`SUMMARY pass=${passed} fail=${failed} expected_fail=${expectedFail} unexpected_pass=${unexpectedPass}`);

if (unexpectedFail > 0 || unexpectedPass > 0) {
  process.exit(1);
}
