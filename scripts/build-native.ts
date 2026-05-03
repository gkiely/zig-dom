import { cpSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = dirname(dirname(fileURLToPath(import.meta.url)));
const run = (command: string[]) => Bun.spawnSync(command, { cwd: rootDir, stderr: "inherit", stdout: "inherit" });

const optimizeMode = process.env.ZIG_DOM_OPTIMIZE?.trim() || "ReleaseFast";

const build = run(["zig", "build", "-Doptimize=" + optimizeMode]);
if (build.exitCode !== 0) {
  process.exit(build.exitCode);
}

const extension = process.platform === "darwin" ? "dylib" : process.platform === "win32" ? "dll" : "so";
const source = join(rootDir, "zig-out", "lib", `libzig_dom.${extension}`);
if (!existsSync(source)) {
  console.error(`Expected native library not found: ${source}`);
  process.exit(1);
}

const target = join(rootDir, "dist", "native", `libzig_dom.${extension}`);
mkdirSync(dirname(target), { recursive: true });
cpSync(source, target);
console.log(`Native library copied to ${target} (optimize=${optimizeMode})`);
