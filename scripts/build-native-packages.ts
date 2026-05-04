const platforms = ["darwin-arm64", "darwin-x64", "linux-arm64", "linux-x64", "win32-x64"];

for (const platform of platforms) {
  const result = Bun.spawnSync(["bun", "run", "scripts/build-native.ts", "--platform", platform, "--stage-package"], {
    cwd: import.meta.dir + "/..",
    stderr: "inherit",
    stdout: "inherit"
  });

  if (result.exitCode !== 0) {
    process.exit(result.exitCode);
  }
}
