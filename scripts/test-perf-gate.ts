import { spawn } from "node:child_process";

function parseTimeoutMs(args: string[]): { warmTimeoutMs: number; runnerArgs: string[] } {
  const runnerArgs: string[] = [];
  let warmTimeoutMs = 150;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]!;
    const timeoutValue = arg === "--timeout" ? args[++index] : arg.startsWith("--timeout=") ? arg.slice("--timeout=".length) : null;
    if (timeoutValue !== null) {
      const value = Number.parseFloat(timeoutValue ?? "");
      if (!Number.isFinite(value) || value <= 0) {
        throw new Error("--timeout must be a positive number of seconds.");
      }
      warmTimeoutMs = value * 1000;
      continue;
    }
    runnerArgs.push(arg);
  }

  return { warmTimeoutMs, runnerArgs };
}

async function run(command: string, args: string[], label: string | null, timeoutMs: number | null): Promise<number> {
  if (label) console.log(`\n--- ${label} ---`);
  const child = spawn(command, args, { detached: true, stdio: "inherit" });

  return await new Promise((resolve, reject) => {
    let settled = false;
    const finish = (exitCode: number): void => {
      if (settled) return;
      settled = true;
      if (timeout) clearTimeout(timeout);
      resolve(exitCode);
    };
    const killGroup = (signal: NodeJS.Signals): void => {
      try {
        process.kill(-child.pid!, signal);
      } catch {}
    };
    const timeout = timeoutMs
      ? setTimeout(() => {
          killGroup("SIGTERM");
          setTimeout(() => killGroup("SIGKILL"), 500).unref();
          console.error(`${label ?? command} timed out after ${timeoutMs}ms.`);
          finish(124);
        }, timeoutMs)
      : null;

    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      if (timeout) clearTimeout(timeout);
      reject(error);
    });

    child.on("close", (code, signal) => finish(code ?? (signal ? 1 : 0)));
  });
}

const { warmTimeoutMs, runnerArgs } = parseTimeoutMs(process.argv.slice(2));

let exitCode = await run("zig", ["build", "-Doptimize=ReleaseFast", "--summary", "none"], null, null);
if (exitCode !== 0) process.exit(exitCode);

const testArgs = ["test", "--dom", "--root", "../youneedawiki", ...runnerArgs];
const timedTestArgs = ["-p", "zig-out/bin/zig-dom", ...testArgs];
exitCode = await run("/usr/bin/time", timedTestArgs, "cold perf run", null);
if (exitCode !== 0) process.exit(exitCode);

exitCode = await run("/usr/bin/time", timedTestArgs, "warm perf run", warmTimeoutMs);
process.exit(exitCode);
