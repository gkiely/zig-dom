import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const cacheDir = join(process.cwd(), ".wpt-cache");
const targetDir = join(cacheDir, "web-platform-tests");

if (existsSync(targetDir)) {
  console.log(`WPT cache already present at ${targetDir}`);
  process.exit(0);
}

mkdirSync(cacheDir, { recursive: true });

const clone = Bun.spawnSync(
  ["git", "clone", "--depth=1", "https://github.com/web-platform-tests/wpt.git", targetDir],
  { cwd: process.cwd(), stdout: "inherit", stderr: "inherit" }
);

if (clone.exitCode !== 0) {
  console.error("WPT sync failed. You can still use local tiny manifest tests.");
  process.exit(clone.exitCode || 1);
}

console.log(`WPT synced to ${targetDir}`);
