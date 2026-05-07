import { readFileSync } from "node:fs";

type ExpectedFailure = {
  file?: string;
  reason?: string;
  status?: string;
  subtest?: string;
};

type ExpectedFile = {
  expectedFailures?: ExpectedFailure[];
};

function arg(name: string, fallback: string): string {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) return fallback;
  return process.argv[index + 1];
}

function areaFor(file: string): string {
  const normalized = file.replace(/^\.wpt-cache\/web-platform-tests\//, "");
  if (normalized === "__global__") return normalized;
  const parts = normalized.split("/");
  if (parts.length <= 2) return parts[0] ?? normalized;
  if (parts[0] === "dom" && parts[1] === "nodes" && parts[2] === "moveBefore") return "dom/nodes/moveBefore";
  if (parts[0] === "dom" && parts[1] === "nodes" && parts[2] === "insertion-removing-steps") return "dom/nodes/insertion-removing-steps";
  if (parts[0] === "dom" && parts[1] === "nodes" && parts[2] === "Document-contentType") return "dom/nodes/Document-contentType";
  if (parts[0] === "dom" && parts[1] === "ranges" && parts[2] === "tentative") return "dom/ranges/tentative";
  if (parts[0] === "dom" && parts[2] === "tentative") return `${parts[0]}/${parts[1]}/tentative`;
  return `${parts[0]}/${parts[1]}`;
}

function formatRows(counts: Map<string, number>): string[] {
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([area, count]) => `${String(count).padStart(4, " ")}  ${area}`);
}

const expectedPath = arg("--expected", "wpt/expected/upstream-dom.json");
const expected = JSON.parse(readFileSync(expectedPath, "utf8")) as ExpectedFile;
const failures = expected.expectedFailures ?? [];

const byArea = new Map<string, number>();
const byReason = new Map<string, number>();
for (const failure of failures) {
  byArea.set(areaFor(failure.file ?? "__global__"), (byArea.get(areaFor(failure.file ?? "__global__")) ?? 0) + 1);
  const reason = failure.reason ?? "(no reason)";
  byReason.set(reason, (byReason.get(reason) ?? 0) + 1);
}

console.log(`Native WPT expected failures: ${failures.length}`);
console.log("");
console.log("By area:");
for (const row of formatRows(byArea)) console.log(row);
console.log("");
console.log("Top reasons:");
for (const [reason, count] of [...byReason.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)) {
  console.log(`${String(count).padStart(4, " ")}  ${reason}`);
}
