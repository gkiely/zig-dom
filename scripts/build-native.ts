import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = dirname(dirname(fileURLToPath(import.meta.url)));
const run = (command: string[]) => Bun.spawnSync(command, { cwd: rootDir, stderr: "inherit", stdout: "inherit" });

const platforms = {
  "darwin-arm64": { target: "aarch64-macos", extension: "dylib", names: ["libzig_dom.dylib"] },
  "darwin-x64": { target: "x86_64-macos", extension: "dylib", names: ["libzig_dom.dylib"] },
  "linux-arm64": { target: "aarch64-linux-gnu", extension: "so", names: ["libzig_dom.so"] },
  "linux-x64": { target: "x86_64-linux-gnu", extension: "so", names: ["libzig_dom.so"] },
  "win32-x64": { target: "x86_64-windows-gnu", extension: "dll", names: ["zig_dom.dll", "libzig_dom.dll"] }
} as const;

type PlatformName = keyof typeof platforms;

function argValue(name: string): string | undefined {
  const prefix = `${name}=`;
  const inline = process.argv.find((arg) => arg.startsWith(prefix));
  if (inline) {
    return inline.slice(prefix.length);
  }
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function currentPlatform(): PlatformName {
  const current = `${process.platform}-${process.arch}`;
  if (current in platforms) {
    return current as PlatformName;
  }
  throw new Error(`Unsupported native platform: ${current}`);
}

const platform = (argValue("--platform") ?? process.env.ZIG_DOM_PLATFORM ?? currentPlatform()) as PlatformName;
if (!(platform in platforms)) {
  throw new Error(`Unknown platform "${platform}". Expected one of: ${Object.keys(platforms).join(", ")}`);
}

const platformInfo = platforms[platform];
const optimizeMode = process.env.ZIG_DOM_OPTIMIZE?.trim() || "ReleaseFast";
const target = argValue("--target") ?? process.env.ZIG_DOM_TARGET ?? platformInfo.target;
const shouldStagePackage = process.argv.includes("--stage-package") || process.env.ZIG_DOM_STAGE_PACKAGE === "1";

const build = run(["zig", "build", "-Doptimize=" + optimizeMode, "-Dtarget=" + target]);
if (build.exitCode !== 0) {
  process.exit(build.exitCode);
}

const sourceCandidates = platformInfo.names.flatMap((name) => [
  join(rootDir, "zig-out", "lib", name),
  join(rootDir, "zig-out", "bin", name)
]);
const source = sourceCandidates.find(existsSync);
if (!source) {
  console.error(`Expected native library not found. Tried: ${platformInfo.names.map((name) => join(rootDir, "zig-out", "lib", name)).join(", ")}`);
  process.exit(1);
}

const libraryName = source.endsWith(".dll") ? "zig_dom.dll" : `libzig_dom.${platformInfo.extension}`;
const distTarget = join(rootDir, "dist", "native", platform, libraryName);
mkdirSync(dirname(distTarget), { recursive: true });
cpSync(source, distTarget);

const legacyTarget = join(rootDir, "dist", "native", libraryName);
if (platform === currentPlatform()) {
  mkdirSync(dirname(legacyTarget), { recursive: true });
  cpSync(source, legacyTarget);
}

if (shouldStagePackage) {
  const packageDir = join(rootDir, "npm", `zig-dom-${platform}`);
  const packageNativeDir = join(packageDir, "native", platform);
  rmSync(join(packageDir, "native"), { force: true, recursive: true });
  mkdirSync(packageNativeDir, { recursive: true });
  cpSync(source, join(packageNativeDir, libraryName));
}

console.log(`Native library copied to ${distTarget} (platform=${platform}, target=${target}, optimize=${optimizeMode})`);
