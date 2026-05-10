import { spawn } from "node:child_process";

function parseArgs(args: string[]): string[] {
  const command: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]!;
    if (arg === "--") {
      command.push(...args.slice(index + 1));
      break;
    }

    command.push(arg);
  }

  return command;
}

function printUsage(): never {
  console.error("Usage: bun run sample -- <command> [args...]");
  process.exit(1);
}

const command = parseArgs(process.argv.slice(2));
if (command.length === 0) printUsage();

const child = spawn(command[0]!, command.slice(1), {
  detached: true,
  stdio: "inherit"
});

const exitPromise = new Promise<number>((resolve, reject) => {
  child.on("error", reject);
  child.on("close", (code, signal) => resolve(code ?? (signal ? 1 : 0)));
});

const sample = spawn("sample", [String(child.pid), "-mayDie"], {
  stdio: ["ignore", "inherit", "inherit"]
});
const samplePromise = new Promise<void>((resolve, reject) => {
  sample.on("error", reject);
  sample.on("close", () => resolve());
});

const exitCode = await exitPromise;
await samplePromise;

process.exit(exitCode);
