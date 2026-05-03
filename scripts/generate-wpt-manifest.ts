import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";

type Manifest = {
  tests: Array<{
    file: string;
  }>;
};

type ExpectedMap = {
  expectedFailures: Array<{
    file: string;
    subtest: string;
    reason: string;
    owner: string;
  }>;
};

function parseArgs() {
  let wptRoot = ".wpt-cache/web-platform-tests";
  let outManifest = "";
  let outExpected = "";
  let maxCount: number | null = null;
  let requireHarness = true;
  const dirs: string[] = [];
  const excludes: string[] = [];

  for (let index = 2; index < process.argv.length; index += 1) {
    const token = process.argv[index];

    if (token === "--wpt-root") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --wpt-root");
      }
      wptRoot = value;
      index += 1;
      continue;
    }

    if (token === "--dir") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --dir");
      }
      dirs.push(...value.split(",").map((entry) => entry.trim()).filter((entry) => entry.length > 0));
      index += 1;
      continue;
    }

    if (token === "--out-manifest") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --out-manifest");
      }
      outManifest = value;
      index += 1;
      continue;
    }

    if (token === "--out-expected") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --out-expected");
      }
      outExpected = value;
      index += 1;
      continue;
    }

    if (token === "--max") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --max");
      }

      const parsed = Number.parseInt(value, 10);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`Invalid --max value: ${value}`);
      }

      maxCount = parsed;
      index += 1;
      continue;
    }

    if (token === "--allow-no-harness") {
      requireHarness = false;
      continue;
    }

    if (token === "--exclude") {
      const value = process.argv[index + 1];
      if (!value) {
        throw new Error("Missing value for --exclude");
      }

      excludes.push(...value.split(",").map((entry) => entry.trim()).filter((entry) => entry.length > 0));
      index += 1;
      continue;
    }

    throw new Error(`Unknown argument: ${token}`);
  }

  if (!outManifest) {
    throw new Error("Missing required --out-manifest argument");
  }

  if (dirs.length === 0) {
    throw new Error("Missing at least one --dir argument");
  }

  return {
    wptRoot,
    dirs,
    outManifest,
    outExpected,
    maxCount,
    requireHarness,
    excludes
  };
}

function toPosix(path: string): string {
  return path.replaceAll("\\", "/");
}

function walkHtmlFiles(rootDir: string): string[] {
  const files: string[] = [];
  const stack: string[] = [rootDir];

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current) {
      continue;
    }

    const entries = readdirSync(current);
    for (const entry of entries) {
      const absolutePath = resolve(current, entry);
      const stats = statSync(absolutePath);

      if (stats.isDirectory()) {
        stack.push(absolutePath);
        continue;
      }

      if (!entry.toLowerCase().endsWith(".html")) {
        continue;
      }

      files.push(absolutePath);
    }
  }

  return files;
}

function hasHarnessScript(html: string): boolean {
  return /testharness\.js/i.test(html);
}

function hasUnsupportedHarnessScript(html: string): boolean {
  return /\/resources\/testdriver(?:-actions|-vendor)?\.js/i.test(html);
}

const { wptRoot, dirs, outManifest, outExpected, maxCount, requireHarness, excludes } = parseArgs();

const resolvedWptRoot = resolve(wptRoot);
if (!existsSync(resolvedWptRoot)) {
  throw new Error(`WPT root does not exist: ${resolvedWptRoot}`);
}

const allFiles: string[] = [];
for (const dir of dirs) {
  const resolvedDir = resolve(resolvedWptRoot, dir);
  if (!existsSync(resolvedDir)) {
    throw new Error(`WPT directory does not exist: ${resolvedDir}`);
  }

  allFiles.push(...walkHtmlFiles(resolvedDir));
}

const uniqueSorted = Array.from(new Set(allFiles)).sort((a, b) => a.localeCompare(b));
const filtered = uniqueSorted.filter((filePath) => {
  const relativePath = toPosix(relative(resolvedWptRoot, filePath));
  if (excludes.some((entry) => relativePath.includes(entry))) {
    return false;
  }

  if (!requireHarness) {
    return true;
  }

  const html = readFileSync(filePath, "utf8");
  return hasHarnessScript(html) && !hasUnsupportedHarnessScript(html);
});

const selected = maxCount ? filtered.slice(0, maxCount) : filtered;

const manifest: Manifest = {
  tests: selected.map((absolutePath) => {
    const relativePath = relative(process.cwd(), absolutePath);
    return {
      file: toPosix(relativePath)
    };
  })
};

const manifestPath = resolve(outManifest);
mkdirSync(dirname(manifestPath), { recursive: true });
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

if (outExpected) {
  const expectedPath = resolve(outExpected);
  if (!existsSync(expectedPath)) {
    const expected: ExpectedMap = {
      expectedFailures: []
    };
    mkdirSync(dirname(expectedPath), { recursive: true });
    writeFileSync(expectedPath, `${JSON.stringify(expected, null, 2)}\n`, "utf8");
  }
}

console.log(`Generated manifest ${toPosix(relative(process.cwd(), manifestPath))} with ${selected.length} tests`);
if (outExpected) {
  console.log(`Expected file ${toPosix(outExpected)} ${existsSync(resolve(outExpected)) ? "ready" : "missing"}`);
}
