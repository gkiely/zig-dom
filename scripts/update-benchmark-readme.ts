import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

type BenchmarkRow = {
  metric: string;
  "zig-dom": number | null;
  "happy-dom": number | null;
  "jsdom": number | null;
};

type BenchmarkArtifact = {
  generatedAt: string;
  rows: BenchmarkRow[];
};

type ReadmeMetric = {
  metric: string;
  label: string;
};

const README_METRICS: ReadmeMetric[] = [
  { metric: "append_10k_children_ms", label: "Append 10k children" },
  { metric: "create_10k_elements_ms", label: "Create 10k elements" },
  { metric: "query_all_class_10k_ms", label: "Query `.class` across 10k nodes" },
  { metric: "query_all_attr_10k_ms", label: "Query `[attr]` across 10k nodes" },
  { metric: "inner_html_parse_ms", label: "Parse `innerHTML`" },
  { metric: "outer_html_serialize_ms", label: "Serialize `outerHTML`" },
  { metric: "mixed_dom_workflow_10k_ms", label: "Mixed DOM workflow, 10k ops" },
  { metric: "mutation_observer_append_10k_ms", label: "Mutation observer append, 10k nodes" },
  { metric: "react_render_10k_rows_ms", label: "React render, 10k rows" },
  { metric: "react_update_10k_rows_ms", label: "React update, 10k rows" },
  { metric: "import_time_ms", label: "Import time" }
];

function formatMs(value: number | null): string {
  return value == null ? "n/a" : `${value.toFixed(2)} ms`;
}

function formatSpeedup(zigDom: number | null, happyDom: number | null): string {
  if (zigDom == null || happyDom == null || zigDom === 0 || happyDom === 0) {
    return "n/a";
  }

  if (zigDom <= happyDom) {
    return `zig-dom is ${(happyDom / zigDom).toFixed(1)}x faster`;
  }

  return `happy-dom is ${(zigDom / happyDom).toFixed(1)}x faster`;
}

function formatGeneratedAt(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`invalid benchmark generatedAt: ${value}`);
  }

  return date.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, " UTC");
}

function readBenchmarkArtifact(path: string): BenchmarkArtifact {
  const artifact = JSON.parse(readFileSync(path, "utf8")) as BenchmarkArtifact;
  if (!Array.isArray(artifact.rows)) {
    throw new Error(`benchmark artifact is missing rows: ${path}`);
  }

  return artifact;
}

function buildBenchmarkMarkdown(artifact: BenchmarkArtifact): string {
  const rowsByMetric = new Map(artifact.rows.map((row) => [row.metric, row]));
  const lines = [
    `Latest local run: ${formatGeneratedAt(artifact.generatedAt)} on \`${process.platform}-${process.arch}\`.`,
    "",
    "| Metric | zig-dom | happy-dom | jsdom | vs happy-dom |",
    "| --- | ---: | ---: | ---: | --- |"
  ];

  for (const readmeMetric of README_METRICS) {
    const row = rowsByMetric.get(readmeMetric.metric);
    if (!row) {
      throw new Error(`benchmark artifact is missing metric: ${readmeMetric.metric}`);
    }

    lines.push(`| ${readmeMetric.label} | ${formatMs(row["zig-dom"])} | ${formatMs(row["happy-dom"])} | ${formatMs(row["jsdom"])} | ${formatSpeedup(row["zig-dom"], row["happy-dom"])} |`);
  }

  return lines.join("\n");
}

const readmePath = resolve(process.cwd(), "README.md");
const artifactPath = resolve(process.cwd(), "docs", "benchmarks", "latest.json");
const readme = readFileSync(readmePath, "utf8");
const artifact = readBenchmarkArtifact(artifactPath);
const benchmarkMarkdown = buildBenchmarkMarkdown(artifact);
const benchmarkStart = readme.indexOf("Latest local run:");
if (benchmarkStart === -1) {
  throw new Error("could not find README benchmark table to update");
}

const nextHeading = readme.slice(benchmarkStart).search(/\n## /);
const benchmarkEnd = nextHeading === -1 ? readme.length : benchmarkStart + nextHeading;
const replacement = readme.endsWith("\n") || benchmarkEnd < readme.length ? `${benchmarkMarkdown}\n` : benchmarkMarkdown;
const updated = `${readme.slice(0, benchmarkStart)}${replacement}${readme.slice(benchmarkEnd)}`;

writeFileSync(readmePath, updated);
console.log("updated README.md benchmark table");
