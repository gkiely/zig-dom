const commands = [
  ["bun", "run", "verify:ffi"],
  ["bun", "run", "verify:dom"],
  ["bun", "run", "verify:react"]
];

for (const cmd of commands) {
  const result = Bun.spawnSync(cmd, { stderr: "inherit", stdout: "inherit" });
  if (result.exitCode !== 0) {
    process.exit(result.exitCode);
  }
}

console.log("verify:fast completed");
